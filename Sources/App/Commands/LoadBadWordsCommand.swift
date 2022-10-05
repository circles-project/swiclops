//
//  LoadBadWordsCommand.swift
//  
//
//  Created by Charles Wright on 10/5/22.
//

import Vapor
import Fluent

struct LoadBadWordsCommand: Command {
    var help: String = "Load a list of bad words from a plain text file"
    
    struct Signature: CommandSignature {
        @Argument(name: "user")
        var user: String
        
        @Argument(name: "filename")
        var filename: String
        
        @Argument(name: "source")
        var source: String
        
        @Option(name: "notes", short: "n")
        var notes: String?
    }

    func run(using context: CommandContext, signature: Signature) throws {
        context.console.print("Loading bad words")
        
        let db = context.application.db
        
        let words: [String] = try String
            .init(contentsOfFile: signature.filename)
            .split(separator: "\n")
            .compactMap {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        context.console.print("Loaded \(words.count) bad words from file [\(signature.filename)]")
        
        let records = words.map {
            BadWord(word: $0, addedBy: signature.user, source: signature.source, notes: signature.notes)
        }
        
        context.console.print("Inserting \(records.count) records into the bad words database")
        try records.create(on: db).wait()
        context.console.print("Done")
    }
}
