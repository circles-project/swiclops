//
//  CreateAcceptedTerms.swift
//  
//
//  Created by Charles Wright on 4/12/22.
//

import Vapor
import Fluent

struct CreateAcceptedTerms: AsyncMigration {
    func prepare(on database: Database) async throws {
        database.logger.debug("Creating table accepted_terms")
        try await database.schema("accepted_terms")
            .id()
            .field("user_id", .string, .required)
            .field("policy", .string, .required)
            .field("version", .string, .required)
            .field("accepted_at", .datetime, .required)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("accepted_terms").delete()
    }
}
