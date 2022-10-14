//
//  AccountDeactivateHandler.swift
//  
//
//  Created by Charles Wright on 9/16/22.
//

import Vapor
import Fluent

struct AccountDeactivateHandler: EndpointHandler {
    var checkers: [AuthChecker]
    var proxy: EndpointHandler
    var endpoints: [Endpoint] = [
        .init(.POST, "/account/deactivate")
    ]
    
    init(checkers: [AuthChecker], proxy: EndpointHandler) {
        self.checkers = checkers
        self.proxy = proxy
    }
    
    func handle(req: Request) async throws -> Response {
        guard let user = req.auth.get(MatrixUser.self) else {
            throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "This endpoint requires authentication")
        }
        
        // 1. Deactivate the user in all of our authentication modules
        for checker in checkers {
            req.logger.debug("Unenrolling from auth checker for \(checker.getSupportedAuthTypes())")
            try await checker.onUnenrolled(req: req, userId: user.userId)
        }
        
        // 2. Proxy the request on to the real homeserver so the account can be deactivated there as well
        return try await proxy.handle(req: req)
    }
    
}
