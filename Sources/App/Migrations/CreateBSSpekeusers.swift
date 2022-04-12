//
//  CreateBSSpekeUsers.swift
//  
//
//  Created by Charles Wright on 4/12/22.
//

import Vapor
import Fluent

struct CreateBSSpekeUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        database.logger.debug("Creating table bsspeke_users")
        try await database.schema("bsspeke_users")
            .id()
            .field("user_id", .string, .identifier(auto: false))
            .field("curve", .string, .required)
            .field("p", .string, .required)
            .field("v", .string, .required)
            .field("phf", .dictionary, .required)
            .unique(on: "user_id", "curve")  // FIXME Maybe it would be nice to support multiple passwords per curve ???
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("bsspeke_users").delete()
    }
}
