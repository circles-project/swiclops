//
//  ListTokensCommand.swift
//  
//
//  Created by Charles Wright on 9/12/22.
//

import Vapor
import Fluent

struct ListTokensCommand: Command {
    var help: String = "List the current registration tokens"
    
    struct Signature: CommandSignature {
        @Option(name: "active", short: "a")
        var active: Bool?
        
        @Option(name: "user", short: "u")
        var user: String?
    }

    func run(using context: CommandContext, signature: Signature) throws {
        context.console.print("Listing registration tokens")
        
        let logger = context.application.logger
        let db = context.application.db

    
        
            
        var query = RegistrationToken.query(on: db)
        if let user = signature.user {
            query = query.filter(\.$createdBy == user)
        }
        if let active = signature.active {
            if active {
                let now = Date()
                query = query.filter(\.$expiresAt > now)
            }
        }
        
        context.console.print("Querying database")
        //let tokens = try await query.all().wait()
        let tokens = try RegistrationToken.query(on: context.application.db).all().wait()
        context.console.print("Query finished")
        
        for token in tokens {
            context.console.print("Found token [\(token.id!)]")
        }

        logger.info("Done")
        
    }
}
