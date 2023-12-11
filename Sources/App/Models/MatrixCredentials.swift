//
//  MatrixCredentials.swift
//
//
//  Created by Charles Wright on 10/20/23.
//

import Vapor

struct MatrixCredentials: Codable {
    var userId: String
    var accessToken: String
    var deviceId: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case accessToken = "access_token"
        case deviceId = "device_id"
    }
}
