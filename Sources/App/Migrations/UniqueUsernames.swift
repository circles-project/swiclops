//
//  UniqueUsernames.swift
//
//
//  Created by Charles Wright on 11/14/23.
//

import Vapor
import Fluent

struct UniqueUsernames: AsyncMigration {
    func prepare(on database: Database) async throws {
        database.logger.debug("Adding unique constraint for table usernames")
        try await database.schema("usernames")
            .unique(on: "username", name: "no_duplicate_usernames")
            .update()
    }

    func revert(on database: Database) async throws {
        database.logger.debug("Removing unique constraint for table usernames")
        try await database.schema("usernames")
            .deleteConstraint(name: "no_duplicate_usernames")
            .update()
    }
}
