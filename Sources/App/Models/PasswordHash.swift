//
//  PasswordHash.swift
//  
//
//  Created by Charles Wright on 3/22/22.
//

import Fluent
import Vapor

final class PasswordHash: Model, Content {
    static let schema = "password_hashes"
    
    @ID(custom: "user_id", generatedBy: .user)
    var id: String?
    
    @Field(key: "hash_func")
    var hashFunc: String
    
    @Field(key: "digest")
    var digest: String
    
    // When this password was created.
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    // When this password was last updated.
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() { }
    
    init(userId: String, hashFunc: String, digest: String) {
        self.id = userId
        self.hashFunc = hashFunc
        self.digest = digest
    }
    
}

struct CreatePasswordHashes: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("password_hashes")
            .field("user_id", .string, .identifier(auto: false))
            .field("hash_func", .string, .required)
            .field("digest", .string, .required)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("password_hashes").delete()
    }
}
