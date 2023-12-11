//
//  AdminBackendConfig.swift
//  
//
//  Created by Charles Wright on 9/20/22.
//

import Vapor

struct AdminBackendConfig: Codable {
    var sharedSecret: String
    
    var username: String?
    var password: String?
    
    enum CodingKeys: String, CodingKey {
        case sharedSecret = "shared_secret"
        case username
        case password
    }
}
