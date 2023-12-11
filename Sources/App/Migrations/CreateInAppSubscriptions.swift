//
//  CreateSubscriptions.swift
//
//
//  Created by Charles Wright on 4/12/22.
//
import Fluent
import Vapor

struct CreateInAppSubscriptions: AsyncMigration {
    func prepare(on database: Database) async throws {
        database.logger.debug("Creating table subscriptions")
        try await database.schema("in_app_subscriptions")
            .id()
            .field("user_id", .string, .required)
            .field("provider", .string, .required)
            .field("product_id", .string, .required)
            .field("transaction_id", .string, .required)
            .field("original_transaction_id", .string, .required)
            .field("bundle_id", .string, .required)
            .field("start_date", .date, .required)
            .field("end_date", .date)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("in_app_subscriptions").delete()
    }
}
