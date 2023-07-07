//
//  AccountAuthHandler.swift
//  
//
//  Created by Charles Wright on 10/18/22.
//

import Vapor

struct AccountAuthHandler: EndpointHandler {
    var endpoints: [Endpoint] = [
        .init(.POST, "/account/auth"),
        .init(.GET, "/account/auth"),
    ]
    
    var flows: [UiaFlow]
    
    init(flows: [UiaFlow]) {
        self.flows = flows
    }
    
    func handle(req: Request) async throws -> Response {
        switch req.method {
        case .POST:
            return try await handlePost(req: req)
        case .GET:
            return try await handleGet(req: req)
        default:
            throw MatrixError(status: .notFound, errcode: .notFound, error: "Method \(req.method) not supported for \(req.url.path)")
        }
    }
    
    func handleGet(req: Request) async throws -> Response {
        struct ResponseBody: Content {
            var flows: [UiaFlow]
        }
        let responseBody = ResponseBody(flows: self.flows)
        return try await responseBody.encodeResponse(for: req)
    }
    
    func handlePost(req: Request) async throws -> Response {
        guard let user = req.auth.get(MatrixUser.self) else {
            throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "This endpoint requires authentication")
        }
        
        req.logger.debug("/account/auth returning HTTP 200 OK for user [\(user.userId)]")
        
        let emptyDict: [String:String] = [:]
        
        return try await emptyDict.encodeResponse(status: .ok, for: req)
    }
    
    
}
