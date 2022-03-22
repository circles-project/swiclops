//
//  UiaRequest.swift
//  
//
//  Created by Charles Wright on 3/22/22.
//

import Vapor

struct UiaAuthDict: Content {
    var type: String
    var session: String
}

struct UiaRequest: Content {
    var auth: UiaAuthDict
}
