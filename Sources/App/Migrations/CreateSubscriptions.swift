//
//  CreateSubscriptions.swift
//
//
//  Created by Charles Wright on 4/12/22.
//
import Fluent
import Vapor

struct CreateSubscriptions: AsyncMigration {
    func prepare(on database: Database) async throws {
        database.logger.debug("Creating table subscriptions")
        try await database.schema("subscriptions")
            .id()
            .field("user_id", .string, .required)
            .field("provider", .string, .required)
            .field("identifier", .string, .required)
            .field("start_date", .date, .required)
            .field("end_date", .date)
            .field("level", .string, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("subscriptions").delete()
    }
}
