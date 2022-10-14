//
//  ProxyHandler.swift
//  
//
//  Created by Charles Wright on 4/13/22.
//

import Vapor
import AnyCodable

extension AnyCodable: Content { }

struct ProxyHandler: EndpointHandler {
    var endpoints: [Endpoint]
    
    var app: Application
    var homeserver: URL
    var backendAuthConfig: BackendAuthConfig
    
    typealias GenericContent = [String: AnyCodable]
    
    init(app: Application, homeserver: URL, authConfig: BackendAuthConfig) {
        self.app = app
        self.homeserver = homeserver
        self.backendAuthConfig = authConfig
        
        self.endpoints = []
    }
    
    func handle(req: Request) async throws -> Response {
        //var requestBody = try? req.content.decode(GenericContent.self)
        //guard requestBody != nil else {
        guard let requestBody = try? req.content.decode(GenericContent.self) else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse request")
        }
        // Remove the "auth" object that was used for UIA
        var myRequestBody = requestBody
        myRequestBody["auth"] = nil
        
        // Now pass the rest of the request body on to the real homeserver
        let homeserverURI = URI(scheme: homeserver.scheme, host: homeserver.host, port: homeserver.port, path: req.url.path)
        req.logger.debug("ProxyHandler: Forwarding request to [\(homeserverURI)]")

        let proxyResponse1 = try await req.client.post(homeserverURI, headers: req.headers, content: myRequestBody)
        
        
        if proxyResponse1.status == .unauthorized {
            // The homeserver wants to UIA -- This should be the common case, unless the user is already approved and cached on the homeserver
            // The first response contains a new UIA session with the real homeserver
            // Extract its session identifier and re-submit the request with our shared-secret auth
            req.logger.debug("ProxyHandler: Starting UIA for [\(homeserverURI)]")

            guard let responseBody = try? proxyResponse1.content.decode(UiaIncomplete.Body.self) else {
                let msg = "Homeserver returned invalid UIA response"
                req.logger.error("ProxyHandler: \(msg)")
                req.logger.error("              Got response: \(proxyResponse1)")
                throw MatrixError(status: .internalServerError, errcode: .unknown, error: msg)
            }
            let sessionId = responseBody.session
            let userId = try await whoAmI(for: req)
            let token = try SharedSecretAuth.token(secret: backendAuthConfig.sharedSecret, userId: userId)
            req.logger.debug("ProxyHandler: Computed token [\(token)] for user [\(userId)]")
            
            // Now we can send the authenticated version of the request
            myRequestBody["auth"] = AnyCodable(SharedSecretAuth.AuthDict(token: token, session: sessionId))
            // And send the response back to the client
            let authedResponse = try await req.client.post(homeserverURI, headers: req.headers, content: myRequestBody)
            req.logger.debug("ProxyHandler: Got authed response with status \(authedResponse.status)")
            req.logger.debug("ProxyHandler: Authed response = \(authedResponse)")
            let authedResponseBody = Response.Body(buffer: authedResponse.body ?? .init())
            return Response(status: authedResponse.status, headers: authedResponse.headers, body: authedResponseBody)
        }
        else {
            // For all other response codes, we simply proxy the response back to the client
            // Maybe we're here because the request was malformed, or maybe the client had already authenticated in the recent past
            req.logger.debug("ProxyHandler: Homeserver did not require UIA for [\(homeserverURI)]")
            let responseBody = Response.Body(buffer: proxyResponse1.body ?? .init())
            return Response(status: proxyResponse1.status, headers: proxyResponse1.headers, body: responseBody)
        }
    }
    
    private func whoAmI(for req: Request) async throws -> String {
        req.logger.debug("ProxyHandler.whoAmI ???")

        let uri = URI(scheme: homeserver.scheme, host: homeserver.host, port: homeserver.port, path: "/_matrix/client/v3/account/whoami")
        let response = try await req.client.get(uri, headers: req.headers)
        struct WhoamiResponseBody: Content {
            var userId: String
            
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }
        req.logger.debug("ProxyHandler.whoAmI: Got homeserver response = \(response)")
        guard let body = try? response.content.decode(WhoamiResponseBody.self) else {
            req.logger.error("Couldn't get user id")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Couldn't get user id")
        }
        req.logger.debug("ProxyHandler.whoAmI: I am [\(body.userId)]")
        return body.userId
    }
    
    
}
