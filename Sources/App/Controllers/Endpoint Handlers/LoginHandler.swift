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
    var type: String?
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
    let endpoints: [Endpoint]
    let flows: [UiaFlow]
    
    init(app: Application, flows: [UiaFlow]) {
        self.app = app
        self.endpoints = [
            .init(.GET, "/login"),
            .init(.POST, "/login"),
        ]
        self.flows = flows
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
        
        if req.auth.get(MatrixUser.self) != nil {
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Can't /login if you already have an access_token")
        }
        
        guard let clientRequest = try? req.content.decode(LoginRequestBody.self)
        else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse /login request")
        }
        
        // We don't actually handle /login requests ourselves
        // We need to craft a /login request of the proper form, so that the homeserver can know that it came from us
        // And then we proxy it to the real homeserver
        guard let sharedSecret = app.admin?.sharedSecret
        else {
            req.logger.error("Could not get admin shared secret")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not perform backend authorization")
        }
        
        guard let config = req.application.config
        else {
            req.logger.error("Failed to get application config")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not load configuration")
        }
        
        let homeserver = config.matrix.homeserver
        
        let homeserverURI = URI(scheme: homeserver.scheme, host: homeserver.host, port: homeserver.port, path: req.url.path)
        let token = try SharedSecretAuth.token(secret: sharedSecret, userId: clientRequest.identifier.user)
        var proxyRequestBody = clientRequest
        proxyRequestBody.password = nil
        proxyRequestBody.type = "com.devture.shared_secret_auth"
        proxyRequestBody.token = token
        let proxyResponse = try await req.client.post(homeserverURI, headers: req.headers, content: proxyRequestBody)
        let responseBody = Response.Body(buffer: proxyResponse.body ?? .init())
        return Response(status: proxyResponse.status, headers: proxyResponse.headers, body: responseBody)
    }
    

}
