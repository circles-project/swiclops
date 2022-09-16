//
//  TokenAdminHandler.swift
//  
//
//  Created by Charles Wright on 9/16/22.
//

import Vapor
import Fluent

struct TokenAdminHandler: EndpointHandler {
    var endpoints: [Endpoint] = [
        .init(.GET, "/registration_tokens"),
        .init(.GET, "/registration_tokens/:token"),
        .init(.POST, "/registration_tokens/new"),
        .init(.PUT, "/registration_tokens/:token"),
        .init(.DELETE, "/registration_tokens/:token"),
    ]
    
    func handle(req: Request) async throws -> Response {
        switch req.method {
        case .GET:
            return try await handleGet(req: req)
        case .POST:
            return try await handleCreate(req: req)
        case .PUT:
            return try await handleUpdate(req: req)
        case .DELETE:
            return try await handleDelete(req: req)
        default:
            throw MatrixError(status: .badRequest, errcode: .unrecognized, error: "Invalid request")
        }
    }
    
    private func handleGet(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
    private func handleGetOne(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
    private func handleGetAll(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
    private func handleCreate(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
    private func handleUpdate(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
    private func handleDelete(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
}
