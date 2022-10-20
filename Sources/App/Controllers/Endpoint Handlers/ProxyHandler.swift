//
//  ProxyHandler.swift
//  
//
//  Created by Charles Wright on 4/13/22.
//

import Vapor
import AnyCodable
import Foundation

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
    
    func forward(req: Request, uri: URI, headers: HTTPHeaders, content: GenericContent? = nil) async throws -> ClientResponse {
        switch req.method {
        case .POST:
            return try await req.client.post(uri, headers: headers, content: content!)
        case .GET:
            return try await req.client.get(uri, headers: headers)
        case .PUT:
            return try await req.client.put(uri, headers: headers, content: content!)
        case .DELETE:
            return try await req.client.delete(uri, headers: headers)
        default:
            throw MatrixError(status: .internalServerError, errcode: .unrecognized, error: "Bad HTTP method")
        }
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

       
        //let proxyResponse1 = try await req.client.post(homeserverURI, headers: req.headers, content: myRequestBody)
        let proxyResponse1 = try await forward(req: req, uri: homeserverURI, headers: req.headers)
        
        
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
            if true {
                let flows = responseBody.flows
                req.logger.debug("Homeserver offers the following flows for UIA: \(flows)")
                if let params = responseBody.params {
                    req.logger.debug("Homeserver provided the following UIA params: \(params)")
                } else {
                    req.logger.debug("Homeserver did not provide any UIA params")
                }
            }
            let token = try SharedSecretAuth.token(secret: backendAuthConfig.sharedSecret, userId: userId)
            req.logger.debug("ProxyHandler: Computed token [\(token)] for user [\(userId)]")
            
            // Now we can send the authenticated version of the request
            myRequestBody["auth"] = AnyCodable(SharedSecretAuth.AuthDict(token: token,
                                                                         session: sessionId,
                                                                         identifier: [
                                                                            "type": "m.id.user",
                                                                            "user": userId,
                                                                         ]
                                                                        ))

            // Debugging: Did we craft a reasonable thing here as our request???
            if true {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let json = try encoder.encode(myRequestBody)
                let string = String(data: json, encoding: .utf8)!
                req.logger.debug("ProxyHandler: About to send request with body = \(string)")
            }
            //let authedResponse = try await req.client.post(homeserverURI, headers: req.headers, content: myRequestBody)
            let authedResponse = try await forward(req: req, uri: homeserverURI, headers: req.headers)
            req.logger.debug("ProxyHandler: Got authed response with status \(authedResponse.status)")
            req.logger.debug("ProxyHandler: Authed response = \(authedResponse)")
            let authedResponseBody = Response.Body(buffer: authedResponse.body ?? .init())
            // And send the response back to the client
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
        //req.logger.debug("ProxyHandler.whoAmI Sending request to \(uri) with headers = \(req.headers)")
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
