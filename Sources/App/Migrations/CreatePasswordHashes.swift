//
//  CreatePasswordHashes.swift
//  
//
//  Created by Charles Wright on 4/12/22.
//

import Vapor
import Fluent

struct CreatePasswordHashes: AsyncMigration {
    func prepare(on database: Database) async throws {
        database.logger.debug("Creating table password_hashes")
        try await database.schema("password_hashes")
            .field("user_id", .string, .identifier(auto: false))
            .field("hash_func", .string, .required)
            .field("digest", .string, .required)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("password_hashes").delete()
    }
}
