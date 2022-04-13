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
    
    typealias GenericContent = [String: AnyCodable]
    
    init(app: Application, homeserver: URL) {
        self.app = app
        self.homeserver = homeserver
        
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
        let homeserverURI = URI(scheme: homeserver.scheme, host: homeserver.host, path: req.url.path)
        let proxyResponse = try await req.client.post(homeserverURI, headers: req.headers, content: requestBody!)
        let responseBody = Response.Body(buffer: proxyResponse.body ?? .init())
        return Response(status: proxyResponse.status, headers: proxyResponse.headers, body: responseBody)
    }
    
    
}
