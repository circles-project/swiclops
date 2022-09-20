//
//  BackendAuthConfig.swift
//  
//
//  Created by Charles Wright on 9/20/22.
//

import Vapor

struct BackendAuthConfig: Codable {
    enum BackendAuthType: String, Codable {
        case devtureSharedSecret = "com.devture.shared_secret_auth"
    }
    var type: BackendAuthType
    var sharedSecret: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case sharedSecret = "shared_secret"
    }
}
