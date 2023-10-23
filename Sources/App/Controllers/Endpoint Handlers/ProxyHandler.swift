//
//  ProxyHandler.swift
//  
//
//  Created by Charles Wright on 4/13/22.
//

import Vapor
import AnyCodable
import Foundation


struct ProxyHandler: EndpointHandler {
    var endpoints: [Endpoint]
    
    var app: Application
    var allocator: ByteBufferAllocator
    
    typealias GenericContent = [String: AnyCodable]
    
    init(app: Application) {
        self.app = app
        
        self.endpoints = []
        
        self.allocator = .init()
    }
    
    func forward(req: Request, to uri: URI, with content: GenericContent? = nil) async throws -> ClientResponse {
        req.logger.debug("ProxyHandler: Forwarding \(req.method) request to [\(uri)]")
        // Debugging: Did we craft a reasonable thing here as our request???
        /*
        if let body = content {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let json = try encoder.encode(body)
            let string = String(data: json, encoding: .utf8)!
            req.logger.debug("ProxyHandler: POST request body = \(string)")
        }
        */

        switch req.method {
            
        case .POST:
            return try await req.client.post(uri, headers: req.headers, content: content!)

        case .GET:
            return try await req.client.get(uri, headers: req.headers)

        case .PUT:
            return try await req.client.put(uri, headers: req.headers, content: content!)

        case .DELETE:
            // WTF Vapor, DELETE is allowed to have a body https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods/DELETE
            return try await req.client.delete(uri, headers: req.headers) { clientReq in
                let encoder = JSONEncoder()
                //try clientReq.encode(content, using: encoder)
                clientReq.body = try encoder.encodeAsByteBuffer(content, allocator: self.allocator)
            }

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
        
        guard let config = req.application.config
        else {
            req.logger.error("Failed to get application config")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not load configuration")
        }
        
        let homeserver = config.matrix.homeserver
        
        // Now pass the rest of the request body on to the real homeserver
        let homeserverURI = URI(scheme: homeserver.scheme, host: homeserver.host, port: homeserver.port, path: req.url.path)

        //let proxyResponse1 = try await req.client.post(homeserverURI, headers: req.headers, content: myRequestBody)
        let proxyResponse1 = try await forward(req: req, to: homeserverURI, with: myRequestBody)
        
        
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
            guard let sharedSecret = app.admin?.sharedSecret
            else {
                req.logger.error("Could not get admin shared secret")
                throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not perform backend auth")
            }
            let token = try SharedSecretAuth.token(secret: sharedSecret, userId: userId)
            req.logger.debug("ProxyHandler: Computed token [\(token)] for user [\(userId)]")
            
            // Now we can send the authenticated version of the request
            myRequestBody["auth"] = AnyCodable(SharedSecretAuth.AuthDict(token: token,
                                                                         session: sessionId,
                                                                         identifier: [
                                                                            "type": "m.id.user",
                                                                            "user": userId,
                                                                         ]
                                                                        ))


            //let authedResponse = try await req.client.post(homeserverURI, headers: req.headers, content: myRequestBody)
            let authedResponse = try await forward(req: req, to: homeserverURI, with: myRequestBody)
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
        
        guard let config = req.application.config
        else {
            req.logger.error("Failed to get application config")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not load configuration")
        }
        
        let homeserver = config.matrix.homeserver

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
