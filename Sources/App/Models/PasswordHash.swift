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
    
    @Field(key: "hashed_password")
    var hashed: String
    
    // When this password was created.
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    // When this password was last updated.
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() { }
    
    init(userId: String, hashFunc: String, hashed: String) {
        self.id = userId
        self.hashFunc = hashFunc
        self.hashed = hashed
    }
    
}
