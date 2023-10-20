//
//  BackendAuthConfig.swift
//  
//
//  Created by Charles Wright on 9/20/22.
//

import Vapor

struct BackendAuthConfig: Codable {    
    var sharedSecret: String
    // FIXME: Move this into the MatrixConfig ???
    var creds: MatrixCredentials?
    var username: String?
    var password: String?
    
    enum CodingKeys: String, CodingKey {
        case sharedSecret = "shared_secret"
        case creds
    }
}
