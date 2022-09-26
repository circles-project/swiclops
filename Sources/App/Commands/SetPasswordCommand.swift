//
//  SetPasswordCommand.swift
//  
//
//  Created by Charles Wright on 9/26/22.
//

import Vapor
import Fluent

struct SetPasswordCommand: Command {
    var help: String = "Set the password for the given user, so the user can log in with m.login.password"

    struct Signature: CommandSignature {
        @Argument(name: "user")
        var user: String
        
        @Argument(name: "password")
        var password: String
    }
    
    func run(using context: CommandContext, signature: Signature) throws {
        context.console.print("Setting password for user \(signature.user)")
        
        let app = context.application
        let db = app.db
        
        //   Hash the password
        let digest = try app.password.hash(signature.password)
        context.console.print("\tPassword hash is [\(digest)]")
        
        // Save the new hash in the database
        let record = PasswordHash(userId: signature.user, hashFunc: "bcrypt", digest: digest)
        try record.create(on: db).wait()
        
        context.console.print("Done")
    }
}
