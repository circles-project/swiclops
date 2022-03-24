//
//  UiaResponse.swift
//  
//
//  Created by Charles Wright on 3/22/22.
//

import Vapor

struct UiaFlow: Content {
    var stages: [String]
}

struct UiaResponse: Content {
    var flows: [UiaFlow]
    
    var completed: [String]?
    
    var params: [String: [String: String]]
    
    var session: String
}
