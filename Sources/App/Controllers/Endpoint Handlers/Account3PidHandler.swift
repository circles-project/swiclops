//
//  Account3PidHandler.swift
//  
//
//  Created by Charles Wright on 9/16/22.
//

import Vapor
import Fluent

struct Account3PidHandler: EndpointHandler {
    var endpoints: [Endpoint] = [
        .init(.GET, "/account/3pid"),
        .init(.POST, "/account/3pid/add"),
        .init(.POST, "/account/3pid/delete"),
    ]
    
    func handle(req: Request) async throws -> Response {
        guard let command = req.url.path.pathComponents.last?.description else {
            throw MatrixError(status: .badRequest, errcode: .unrecognized, error: "Invalid request")
        }
        switch (req.method, command) {
        case (.GET, "3pid"):
            return try await handleGet(req: req)
        case (.POST, "add"):
            return try await handleAdd(req: req)
        case (.POST, "delete"):
            return try await handleDelete(req: req)
        default:
            throw MatrixError(status: .badRequest, errcode: .unrecognized, error: "Invalid request")
        }
    }
    
    func handleGet(req: Request) async throws -> Response {
        guard let user = req.auth.get(MatrixUser.self) else {
            throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "This endpoint requires authentication")
        }
                
        let records = try await UserEmailAddress.query(on: req.db)
                                                .filter(\.$userId == user.userId)
                                                .all()
        
        struct GetResponseBody: Content {
            struct Threepid: Codable {
                var addedAt: UInt
                var address: String
                var medium: String
                var validatedAt: UInt
            }
            var threepids: [Threepid]
            
            init(_ emailRecords: [UserEmailAddress]) {
                self.threepids = emailRecords.map { rec in
                    Threepid(addedAt: UInt(rec.lastUpdated!.timeIntervalSince1970),
                             address: rec.email,
                             medium: "email",
                             validatedAt: UInt(rec.lastUpdated!.timeIntervalSince1970))
                }
            }
        }
        
        let responseBody = GetResponseBody(records)
        return try await responseBody.encodeResponse(for: req)
    }
    
    func handleAdd(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
    func handleDelete(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
}
