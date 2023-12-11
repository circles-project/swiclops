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
    //var domain: String
    //var homeserver: URL
    var adminBackend: AdminBackendConfig
    var matrix: MatrixConfig
    var uia: UiaController.Config
    var database: DatabaseConfig
    
    enum CodingKeys: String, CodingKey {
        case adminBackend = "admin_backend"
        case matrix
        case uia
        case database
    }
    
    init(filename: String) throws {
        let configData = try Data(contentsOf: URL(fileURLWithPath: filename))
        print("Loaded config data from file [\(filename)]")
        let decoder = YAMLDecoder()
        self = try decoder.decode(AppConfig.self, from: configData)
    }
    
    init(string: String) throws {
        let decoder = YAMLDecoder()
        self = try decoder.decode(AppConfig.self, from: string)
    }
}
