//
//  AccountAuthHandler.swift
//  
//
//  Created by Charles Wright on 10/18/22.
//

import Vapor

struct AccountAuthHandler: EndpointHandler {
    var endpoints: [Endpoint] = [
        .init(.POST, "/account/auth")
    ]
    
    func handle(req: Request) async throws -> Response {
        guard let user = req.auth.get(MatrixUser.self) else {
            throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "This endpoint requires authentication")
        }
        
        req.logger.debug("/account/auth returning HTTP 200 OK for user [\(user.userId)]")
        
        let emptyDict: [String:String] = [:]
        
        return try await emptyDict.encodeResponse(status: .ok, for: req)
    }
    
    
}
