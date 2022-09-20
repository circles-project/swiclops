//
//  TokenAdminHandler.swift
//  
//
//  Created by Charles Wright on 9/16/22.
//

import Vapor
import Fluent

struct TokenAdminHandler: EndpointHandler {
    var app: Application
    var homeserver: URL
    var endpoints: [Endpoint] = [
        .init(.GET, "/registration_tokens"),
        .init(.GET, "/registration_tokens/:token"),
        .init(.POST, "/registration_tokens/new"),
        .init(.PUT, "/registration_tokens/:token"),
        .init(.DELETE, "/registration_tokens/:token"),
    ]
    
    init(app: Application, homeserver: URL) {
        self.app = app
        self.homeserver = homeserver
    }
    
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
        // First we need to verify that the user is an admin on the homeserver -- right?
        // Or do we not care???
        // Send a request to GET /_matrix/client/:version/whoami
        let version = req.parameters.get("version") ?? "v3"
        let uri1 = URI(host: self.homeserver.host, path: "/_matrix/client/\(version)/whoami")
        let response1 = try await req.client.get(uri1)
        
        // Extract username from the response
        struct WhoamiResponseBody: Content {
            var userId: String
            var deviceId: String
            var isGuest: Bool
        }
        guard let r1ResponseBody = try? response1.content.decode(WhoamiResponseBody.self) else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not get user id")
        }
        let userId = r1ResponseBody.userId
        
        // Send a request to GET /_synapse/admin/v2/users/:user_id
        let uri2 = URI(host: self.homeserver.host, path: "/_matrix/admin/v2/users/\(userId)")
        let response2 = try await req.client.get(uri2)
        
        // Verify that the user is an admin
        // https://matrix-org.github.io/synapse/latest/admin_api/user_admin_api.html
        struct AdminUsersResponseBody: Content {
            var name: String
            var displayname: String
            var isGuest: Bool
            var admin: Bool
            var deactivated: Bool
        }
        guard let r2ResponseBody = try? response2.content.decode(AdminUsersResponseBody.self) else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not verify user info")
        }
        guard r2ResponseBody.admin && !r2ResponseBody.isGuest && !r2ResponseBody.deactivated else {
            throw MatrixError(status: .forbidden, errcode: .forbidden, error: "User is not allowed to create registration tokens")
        }
        
        throw Abort(.notImplemented)
    }
    
    private func handleUpdate(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
    private func handleDelete(req: Request) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
}
