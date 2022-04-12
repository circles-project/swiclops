//
//  AcceptedTerms.swift
//  
//
//  Created by Charles Wright on 3/24/22.
//

import Fluent
import Vapor

final class AcceptedTerms: Model, Content {
    static let schema = "accepted_terms"
    
    @ID(key: "uuid")
    var id: UUID?
    
    @Field(key: "user_id")
    var userId: String
    
    @Field(key: "policy")
    var policy: String
    
    @Field(key: "version")
    var version: String
    
    @Timestamp(key: "accepted_at", on: .create)
    var acceptedAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, policy: String, userId: String, version: String) {
        self.id = id
        self.policy = policy
        self.userId = userId
        self.version = version
    }
}

struct CreateAcceptedTerms: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("accepted_terms")
            .id()
            .field("user_id", .string, .required)
            .field("policy", .string, .required)
            .field("version", .string, .required)
            .field("accepted_at", .datetime, .required)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("accepted_terms").delete()
    }
}
