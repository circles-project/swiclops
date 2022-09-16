//
//  AccountPasswordHandler.swift
//  
//
//  Created by Charles Wright on 9/16/22.
//

import Vapor
import Fluent

struct AccountPasswordHandler: EndpointHandler {
    var endpoints: [Endpoint] = [
        .init(.POST, "/_matrix/client/:version/account/password")
    ]
    
    func handle(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
}
