//
//  Subscription.swift
//
//
//  Created by Charles Wright on 3/30/21.
//
import Fluent
import Vapor

final class Subscription: Model {
    static let schema = "subscriptions"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "user_id")
    var userId: String
    
    @Field(key: "provider")
    var provider: String
    
    @Field(key: "identifier")
    var identifier: String
    
    @Field(key: "start_date")
    var startDate: Date
    
    @Field(key: "end_date")
    var endDate: Date?
    
    @Field(key: "level")
    var level: String
    
    init() {}
    
    init(id: UUID? = nil, userId: String, provider: String, identifier: String, startDate: Date, endDate: Date?, level: String) {
        self.id = id
        self.userId = userId
        self.provider = provider
        self.identifier = identifier
        self.startDate = startDate
        self.endDate = endDate
        self.level = level
    }
}

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
