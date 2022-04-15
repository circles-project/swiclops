//
//  WhoamiResponseBody.swift
//  
//
//  Created by Charles Wright on 4/15/22.
//

import Vapor

struct WhoamiResponseBody: Content {
    var deviceId: String?
    var isGuest: Bool?
    var userId: String
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case isGuest = "is_guest"
        case userId = "user_id"
    }
}
