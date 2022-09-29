//
//  UserEmailAddress.swift
//  
//
//  Created by Charles Wright on 3/26/22.
//

import Fluent
import Vapor

final class UserEmailAddress: Model, Content {
    
    static let schema = "user_email_addresses"
    
    //@ID(custom: "email", generatedBy: .user)
    //var id: String?
    
    @ID(key: "id")
    var id: UUID?
    
    @Field(key: "email")
    var email: String
    
    @Field(key: "user_id")
    var userId: String
    
    @Timestamp(key: "last_updated", on: .update)
    var lastUpdated: Date?
 
    init() { }
    
    init(id: UUID? = nil, userId: String, email: String) {
        self.id = id
        self.userId = userId
        self.email = email
    }
}
