//
//  CreateRegistrationTokens.swift
//  
//
//  Created by Charles Wright on 4/12/22.
//

import Vapor
import Fluent

struct CreateRegistrationTokens: AsyncMigration {
    func prepare(on database: Database) async throws {
        database.logger.debug("Creating table registration_tokens")
        try await database.schema("registration_tokens")
            .field("token", .string, .identifier(auto: false))
            .field("created_by", .string, .required)
            .field("slots", .int, .required)
            .field("created_at", .datetime, .required)
            .field("expires_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("registration_tokens").delete()
    }
}
