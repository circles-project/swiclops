//
//  UiaRequest.swift
//  
//
//  Created by Charles Wright on 3/22/22.
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
