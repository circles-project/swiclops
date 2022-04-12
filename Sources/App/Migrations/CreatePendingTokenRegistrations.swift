//
//  CreatePendingTokenRegistrations.swift
//  
//
//  Created by Charles Wright on 4/12/22.
//

import Fluent
import Vapor

struct CreatePendingTokenRegistrations: AsyncMigration {
    func prepare(on database: Database) async throws {
        database.logger.debug("Creating table pending_token_registrations")
        try await database.schema("pending_token_registrations")
            .field("token", .string, .identifier(auto: false))
            .field("session", .string, .required)
            .field("created_at", .datetime, .required)
            .unique(on: "token", "session")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("pending_token_registrations").delete()
    }
}
