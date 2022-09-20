//
//  MatrixConfig.swift
//  
//
//  Created by Charles Wright on 9/20/22.
//

import Vapor

struct MatrixConfig: Codable {
    var domain: String
    var homeserver: URL
}
