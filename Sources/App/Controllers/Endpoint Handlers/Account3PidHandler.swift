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
        .init(.GET, "/_matrix/client/:version/account/3pid"),
        .init(.POST, "/_matrix/client/:version/account/3pid/add"),
        .init(.POST, "/_matrix/client/:version/account/3pid/delete"),
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
        throw Abort(.notImplemented)
    }
    
    func handleAdd(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
    func handleDelete(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
}
