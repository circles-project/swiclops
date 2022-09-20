//
//  EmailConfig.swift
//  
//
//  Created by Charles Wright on 9/20/22.
//

import Vapor
import Fluent

struct EmailConfig: Codable {
    var postmarkToken: String
    
    enum CodingKeys: String, CodingKey {
        case postmarkToken = "postmark_token"
    }
}
