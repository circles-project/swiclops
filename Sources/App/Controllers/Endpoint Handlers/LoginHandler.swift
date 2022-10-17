//
//  LoginHandler.swift
//  
//
//  Created by Charles Wright on 4/13/22.
//

import Vapor
import Crypto

struct LoginRequestBody: Content {
    struct Identifier: Codable {
        let type: String
        let user: String
    }
    var identifier: Identifier
    var type: String
    var password: String?
    var token: String?
    var deviceId: String?
    var initialDeviceDisplayName: String?
    var refreshToken: Bool?
    
    enum CodingKeys: String, CodingKey {
        case identifier
        case type
        case password
        case token
        case deviceId = "device_id"
        case initialDeviceDisplayName = "initial_device_display_name"
        case refreshToken = "refresh_token"
    }
}

struct LoginHandler: EndpointHandler {
    
    let app: Application
    let homeserver: URL
    let endpoints: [Endpoint]
    let flows: [UiaFlow]
    let authConfig: BackendAuthConfig
    
    init(app: Application, homeserver: URL, flows: [UiaFlow], authConfig: BackendAuthConfig) {
        self.app = app
        self.homeserver = homeserver
        self.endpoints = [
            .init(.GET, "/login"),
            .init(.POST, "/login"),
        ]
        self.flows = flows
        self.authConfig = authConfig
    }
    
    func handle(req: Request) async throws -> Response {
        switch req.method {
        case .GET:
            return try await handleGet(req: req) as! Response
        case .POST:
            return try await handlePost(req: req)
        default:
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Operation not supported")
        }
    }
    
    func handleGet(req: Request) async throws -> ResponseEncodable {
        
        struct LoginGetResponseUIA: Content {
            var flows: [UiaFlow]
        }
        let responseBody = LoginGetResponseUIA(flows: self.flows)
        return responseBody
    }
    
    func handlePost(req: Request) async throws -> Response {
        guard let clientRequest = try? req.content.decode(LoginRequestBody.self)
        else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse /login request")
        }
        
        // We don't actually handle /login requests ourselves
        // We need to craft a /login request of the proper form, so that the homeserver can know that it came from us
        // And then we proxy it to the real homeserver
        let homeserverURI = URI(scheme: homeserver.scheme, host: homeserver.host, port: homeserver.port, path: req.url.path)
        let token = try SharedSecretAuth.token(secret: self.authConfig.sharedSecret, userId: clientRequest.identifier.user)
        let proxyRequestBody = LoginRequestBody(identifier: clientRequest.identifier, type: self.authConfig.type.rawValue, token: token)
        let proxyResponse = try await req.client.post(homeserverURI, headers: req.headers, content: proxyRequestBody)
        let responseBody = Response.Body(buffer: proxyResponse.body ?? .init())
        return Response(status: proxyResponse.status, headers: proxyResponse.headers, body: responseBody)
    }
    

}
