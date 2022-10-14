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
        var requestBody = try? req.content.decode(GenericContent.self)
        guard requestBody != nil else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse request")
        }
        // Remove the "auth" object that was used for UIA
        requestBody!["auth"] = nil
        
        // Now pass the rest of the request body on to the real homeserver
        let homeserverURI = URI(scheme: homeserver.scheme, host: homeserver.host, port: homeserver.port, path: req.url.path)
        req.logger.debug("ProxyHandler: Forwarding request to [\(homeserverURI)]")

        let proxyResponse1 = try await req.client.post(homeserverURI, headers: req.headers, content: requestBody!)
        
        
        if proxyResponse1.status == .unauthorized {
            // The homeserver wants to UIA -- This should be the common case, unless the user is already approved and cached on the homeserver
            // The first response contains a new UIA session with the real homeserver
            // Extract its session identifier and re-submit the request with our shared-secret auth
            struct GenericUiaResponse: Content {
                struct GenericUiaAuthDict: UiaAuthDict {
                    var type: String
                    var session: String
                }
                var auth: GenericUiaAuthDict
            }
            guard let responseBody = try? proxyResponse1.content.decode(GenericUiaResponse.self) else {
                throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Homeserver returned invalid UIA response")
            }
            let sessionId = responseBody.auth.session
            let userId = try await getUserId(for: req)
            let token = try SharedSecretAuth.token(secret: backendAuthConfig.sharedSecret, userId: userId)
            
            // Now we can send the authenticated version of the request
            requestBody!["auth"] = AnyCodable(SharedSecretAuth.AuthDict(token: token, session: sessionId))
            // And send the response back to the client
            let authedResponse = try await req.client.post(homeserverURI, headers: req.headers, content: requestBody!)
            let authedResponseBody = Response.Body(buffer: authedResponse.body ?? .init())
            return Response(status: authedResponse.status, headers: authedResponse.headers, body: authedResponseBody)
        }
        else {
            // For all other response codes, we simply proxy the response back to the client
            // Maybe we're here because the request was malformed, or maybe the client had already authenticated in the recent past
        
            let responseBody = Response.Body(buffer: proxyResponse1.body ?? .init())
            return Response(status: proxyResponse1.status, headers: proxyResponse1.headers, body: responseBody)
        }
    }
    
    private func getUserId(for req: Request) async throws -> String {
        struct WhoamiResponseBody: Content {
            var userId: String
        }
        let uri = URI(scheme: homeserver.scheme, host: homeserver.host, port: homeserver.port, path: "/_matrix/client/v3/whoAmI")
        let response = try await req.client.get(uri)
        guard let body = try? response.content.decode(WhoamiResponseBody.self) else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Couldn't get user id")
        }
        return body.userId
    }
    
    
}
