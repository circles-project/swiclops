//
//  CreateUsernames.swift
//  
//
//  Created by Charles Wright on 10/5/22.
//

import Vapor
import Fluent

struct CreateUsernames: AsyncMigration {
    func prepare(on database: Database) async throws {
        database.logger.debug("Creating table usernames")
        try await database.schema("usernames")
            .field("username", .string, .identifier(auto: false))
            .field("status", .string, .required)
            .field("reason", .string)
            .field("created", .datetime)
            .field("updated", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("usernames").delete()
    }
}
