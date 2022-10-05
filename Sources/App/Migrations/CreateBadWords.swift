//
//  CreateBadWords.swift
//  
//
//  Created by Charles Wright on 10/5/22.
//

import Vapor
import Fluent

struct CreateBadWords: AsyncMigration {
    
    func prepare(on database: Database) async throws {
        database.logger.debug("Creating table bad_words")
        try await database.schema("bad_words")
            .field("word", .string, .identifier(auto: false))
            .field("created_at", .datetime)
            .field("added_by", .string, .required)
            .field("source", .string, .required)
            .field("notes", .string)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("bad_words").delete()
    }
    
}
