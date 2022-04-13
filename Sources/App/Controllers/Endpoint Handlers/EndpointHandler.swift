//
//  EndpointHandler.swift
//  
//
//  Created by Charles Wright on 4/13/22.
//

import Vapor

struct Endpoint {
    let method: HTTPMethod
    let path: String
    
    init(_ method: HTTPMethod, _ path: String) {
        self.method = method
        self.path = path
    }
    
    var pathComponents: [PathComponent] {
        path.split(separator: "/").map {
            PathComponent(stringLiteral: String($0))
        }
    }
}

extension Endpoint: Hashable {
    func hash(into hasher: inout Hasher) {
        method.rawValue.hash(into: &hasher)
        path.hash(into: &hasher)
    }
}

protocol EndpointHandler {
    var endpoints: [Endpoint] { get }
    
    func handle(req: Request) async throws -> Response
}
