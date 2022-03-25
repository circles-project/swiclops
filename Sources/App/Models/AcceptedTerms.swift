//
//  AcceptedTerms.swift
//  
//
//  Created by Charles Wright on 3/24/22.
//

import Vapor
import Fluent

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
    
    init(policy: String, userId: String, version: String) {
        self.policy = policy
        self.userId = userId
        self.version = version
    }
}
