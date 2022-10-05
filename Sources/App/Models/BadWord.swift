//
//  BadWord.swift
//  
//
//  Created by Charles Wright on 10/5/22.
//

import Foundation
import Vapor
import Fluent

final class BadWord: Model {
    static let schema = "bad_words"
        
    @ID(custom: "word", generatedBy: .user)
    var id: String?
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Field(key: "added_by")
    var addedBy: String
    
    @Field(key: "source")
    var source: String
    
    @Field(key: "notes")
    var notes: String?
    
    init() { }
    
    init(word: String, addedBy: String, source: String, notes: String?) {
        self.id = word
        self.addedBy = addedBy
        self.source = source
        self.notes = notes
    }
}
