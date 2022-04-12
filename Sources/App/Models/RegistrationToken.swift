//
//  RegistrationToken.swift
//  
//
//  Created by Charles Wright on 3/28/22.
//

import Vapor
import Fluent

final class RegistrationToken: Model {
    static let schema = "registration_tokens"
    
    @ID(custom: "token", generatedBy: .user)
    var id: String?
    
    @Field(key: "created_by")
    var createdBy: String
    
    @Field(key: "slots")
    var slots: Int
    
    @Timestamp(key: "created_at", on: .create)
    var createAt: Date?
    
    @Field(key: "expires_at")
    var expiresAt: Date?
    
    var isExpired: Bool {
        if let expiration = self.expiresAt {
            return expiration < Date()
        }
        
        return false
    }
}

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
