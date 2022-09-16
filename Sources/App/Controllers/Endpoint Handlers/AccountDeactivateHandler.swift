//
//  AccountDeactivateHandler.swift
//  
//
//  Created by Charles Wright on 9/16/22.
//

import Vapor
import Fluent

struct AccountDeactivateHandler: EndpointHandler {
    var app: Application
    var proxy: EndpointHandler
    var endpoints: [Endpoint] = [
        .init(.POST, "/account/deactivate")
    ]
    
    init(app: Application, proxy: EndpointHandler) {
        self.app = app
        self.proxy = proxy
    }
    
    func handle(req: Request) async throws -> Response {
        // 1. Deactivate the user in all of our authentication modules
        throw Abort(.notImplemented)
        // 2. Proxy the request on to the real homeserver so the account can be deactivated there as well
        proxy.handle(req: req)
    }
    
}
