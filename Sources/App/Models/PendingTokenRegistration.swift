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
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "token")
    var token: String
    
    @Field(key: "session")
    var session: String
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() {}
    
    init(id: UUID? = nil, token: String, session: String) {
        self.id = id
        self.token = token
        self.session = session
        self.createdAt = Date()
    }
    
}
