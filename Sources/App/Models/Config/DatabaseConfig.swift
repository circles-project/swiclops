//
//  DatabaseConfig.swift
//  
//
//  Created by Charles Wright on 9/12/22.
//

import Vapor
import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver

struct PostgresDatabaseConfig: Decodable {
    var hostname: String
    var port: Int
    var username: String
    var password: String
    var database: String
    
    enum CodingKeys: String, CodingKey {
        case hostname
        case port
        case username
        case password
        case database
    }
    
    init(hostname: String?, port: Int?, username: String?, password: String?, database: String?) {
        self.hostname = hostname ?? Environment.get("DATABASE_HOST") ?? "localhost"
        self.port = port ?? Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? PostgresConfiguration.ianaPortNumber
        self.username = username ?? Environment.get("DATABASE_USERNAME") ?? "swiclops"
        self.password = password ?? Environment.get("DATABASE_PASSWORD") ?? "swiclops"
        self.database = database ?? Environment.get("DATABASE_NAME") ?? "swiclops"
    }
}

struct SqliteDatabaseConfig: Decodable {
    var filename: String
}

enum DatabaseConfig: Decodable {
    case postgres(PostgresDatabaseConfig)
    case sqlite(SqliteDatabaseConfig)
    
    enum CodingKeys: String, CodingKey {
        case postgres
        case sqlite
        case type
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type: String = try container.decode(String.self, forKey: .type)
        switch type {
        case "postgres":
            //let config = decoder.decode(PostgresDatabaseConfig.self)
            self = try .postgres(PostgresDatabaseConfig(from: decoder))
        case "sqlite":
            self = try .sqlite(SqliteDatabaseConfig(from: decoder))
        default:
            throw ConfigurationError(msg: "Invalid database type: \(type)")
        }
    }
}
