//
//  PendingTokenRegistration.swift
//  
//
//  Created by Charles Wright on 3/28/22.
//

import Fluent
import Vapor

final class PendingTokenRegistration: Model {
    static let schema = "pending_token_registrations"
    
    @ID(custom: "token", generatedBy: .user)
    var id: String?
    
    @Field(key: "session")
    var session: String
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() {}
    
    init(id: String, session: String) {
        self.id = id
        self.session = session
    }
    
}

struct CreatePendingTokenRegistrations: AsyncMigration {
    func prepare(on database: Database) async throws {
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
