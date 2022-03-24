//
//  UIA.swift
//  
//
//  Created by Charles Wright on 3/24/22.
//

import Vapor

protocol UiaAuthDict: Content {
    var type: String { get }
    var session: String { get }
}

struct UiaRequest: Content {
    struct AuthDict: UiaAuthDict {
        var type: String
        var session: String
    }
    var auth: AuthDict
}

struct UiaFlow: Content {
    var stages: [String]
}

struct UiaResponse: Content {
    var flows: [UiaFlow]
    
    var completed: [String]?
    
    var params: [String: [String: String]]
    
    var session: String
}
