//
//  LoginHandler.swift
//  
//
//  Created by Charles Wright on 4/13/22.
//

import Vapor

struct LoginRequestBody: Content {
    struct Identifier: Codable {
        let type: String
        let user: String
    }
    var identifier: Identifier
    var type: String?
    var password: String?
}

struct LoginHandler: EndpointHandler {
    
    let app: Application
    let homeserver: URL
    let endpoints: [Endpoint]
    
    init(app: Application, homeserver: URL) {
        self.app = app
        self.homeserver = homeserver
        self.endpoints = [
            //(.GET, "/login"),
            .init(.POST, "/login"),
        ]
    }
    
    func handle(req: Request) async throws -> Response {
        switch req.method {
        case .POST:
            return try await handlePost(req: req)
        default:
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Operation not supported")
        }
    }
    
    func handlePost(req: Request) async throws -> Response {
        guard let clientRequest = try? req.content.decode(LoginRequestBody.self)
        else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse /login request")
        }
        
        // We don't actually handle /login requests ourselves
        // We need to craft a /login request of the proper form, so that the homeserver can know that it came from us
        // And then we proxy it to the real homeserver
        let homeserverURI = URI(scheme: homeserver.scheme, host: homeserver.host, path: req.url.path)
        let proxyRequestBody = LoginRequestBody(identifier: clientRequest.identifier, type: "swiclops.password", password: "hunter2") // FIXME: Update this to use https://github.com/devture/matrix-synapse-shared-secret-auth
        let proxyResponse = try await req.client.post(homeserverURI, headers: req.headers, content: proxyRequestBody)
        let responseBody = Response.Body(buffer: proxyResponse.body ?? .init())
        return Response(status: proxyResponse.status, headers: proxyResponse.headers, body: responseBody)
    }
}
