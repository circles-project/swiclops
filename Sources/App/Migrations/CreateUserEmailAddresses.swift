//
//  CreateUserEmailAddresses.swift
//  
//
//  Created by Charles Wright on 3/26/22.
//

import Fluent
import Vapor

struct CreateUserEmailAddresses: AsyncMigration {
    func prepare(on database: Database) async throws {
        database.logger.debug("Creating table user_email_addresses")
        try await database.schema("user_email_addresses")
            .id()
            .field("email", .string, .required)
            .field("user_id", .string, .required)
            .field("last_updated", .datetime, .required)
            .unique(on: "email", name: "one_account_per_email")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("user_email_addresses").delete()
    }
}
