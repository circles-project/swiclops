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
