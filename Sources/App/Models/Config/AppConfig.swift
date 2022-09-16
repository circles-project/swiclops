//
//  AppConfig.swift
//  
//
//  Created by Charles Wright on 9/12/22.
//

import Vapor
import Fluent
import Yams


struct AppConfig: Decodable {
    var admin: AdminApiController.Config
    var uia: UiaController.Config
    var database: DatabaseConfig
    
    init(filename: String) throws {
        let configData = try Data(contentsOf: URL(fileURLWithPath: filename))
        let decoder = YAMLDecoder()
        self = try decoder.decode(AppConfig.self, from: configData)
    }
    
    init(string: String) throws {
        let decoder = YAMLDecoder()
        self = try decoder.decode(AppConfig.self, from: string)
    }
}
