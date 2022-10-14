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
        
        // 1. Proxy the request on to the real homeserver so the account can be deactivated there as well
        let response = try await proxy.handle(req: req)
        
        // 2. If we succesfully deactivated the account with the homeserver, only then do we deactivate the user in all of our authentication modules
        if response.status == .ok {
            for checker in checkers {
                req.logger.debug("Unenrolling from auth checker for \(checker.getSupportedAuthTypes())")
                try await checker.onUnenrolled(req: req, userId: user.userId)
            }
        }
        
        return response
    }
    
}
