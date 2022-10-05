//
//  LoadReservedUsernamesCommand.swift
//  
//
//  Created by Charles Wright on 10/5/22.
//

import Vapor
import Fluent

struct LoadReservedUsernamesCommand: Command {
    var help: String = "Load a list of reserved usernames from a plain text file"
    
    struct Signature: CommandSignature {
        
        @Argument(name: "filename")
        var filename: String
        
        @Option(name: "reason", short: "r")
        var reason: String?
    }

    func run(using context: CommandContext, signature: Signature) throws {
        context.console.print("Loading reserved usernames")
        
        let db = context.application.db
        
        let names: [String] = try String
            .init(contentsOfFile: signature.filename)
            .split(separator: "\n")
            .compactMap {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        context.console.print("Loaded \(names.count) reserved usernames from file [\(signature.filename)]")
        
        let records = names.map {
            Username($0, status: .reserved, reason: signature.reason)
        }
        
        context.console.print("Inserting \(records.count) 'reserved' records into the usernames database")
        try records.create(on: db).wait()
        context.console.print("Done")
    }
}
