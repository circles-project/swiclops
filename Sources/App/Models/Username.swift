//
//  Username.swift
//  
//
//  Created by Charles Wright on 10/5/22.
//

import Vapor
import Fluent

final class Username: Model {
    static var schema = "usernames"
    
    enum Status: String, Codable {
        case none
        case reserved
        case pending
        case enrolled
        case inactive
    }
    
    @ID(custom: "username", generatedBy: .user)
    var id: String?
    
    @Field(key: "status")
    var status: Status
    
    @OptionalField(key: "reason")
    var reason: String?
    
    @Timestamp(key: "created", on: .create)
    var created: Date?
    
    @Timestamp(key: "updated", on: .update)
    var updated: Date?
    
    init() {
        self.status = .none
    }
    
    init(_ id: String? = nil, status: Status, reason: String? = nil) {
        self.id = id
        self.status = status
        self.reason = reason
    }
}
