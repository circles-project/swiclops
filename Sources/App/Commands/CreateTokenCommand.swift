//
//  CreateTokenCommand.swift
//  
//
//  Created by Charles Wright on 9/9/22.
//

import Vapor
import Fluent

struct CreateTokenCommand: Command {
    var help: String = "Creates a new registration token"
    
    struct Signature: CommandSignature {
        @Argument(name: "token")
        var token: String
        
        @Argument(name: "user")
        var user: String
        
        @Argument(name: "slots")
        var slots: Int
        
        @Option(name: "lifetime", short: "l")
        var lifetime: Int?
        
    }

    func run(using context: CommandContext, signature: Signature) throws {
        context.console.print("Creating a registration token")
        
        let logger = context.application.logger
        let db = context.application.db
        
        var expirationDate: Date?
        
        if let days = signature.lifetime {
            let seconds = Double(days * 24 * 60 * 60)
            expirationDate = Date(timeIntervalSinceNow: seconds)
        }
        
        var token = RegistrationToken(id: signature.token,
                                      createdBy: signature.user,
                                      slots: signature.slots,
                                      expiresAt: expirationDate)
        
        logger.info("Creating token [\(token.id!)]")
        
        try token.save(on: db).wait()

        logger.info("Done")
    }
}
