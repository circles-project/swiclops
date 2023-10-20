//
//  BackendAuthConfig.swift
//  
//
//  Created by Charles Wright on 9/20/22.
//

import Vapor

struct BackendAuthConfig: Codable {    
    var sharedSecret: String
    var creds: MatrixCredentials?
    
    enum CodingKeys: String, CodingKey {
        case sharedSecret = "shared_secret"
        case creds
    }
}
