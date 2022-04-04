import Fluent
import FluentPostgresDriver
import Leaf
import Vapor
import Yams

struct ConfigurationError: Error {
    let msg: String
}

// configures your application
public func configure(_ app: Application) throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    // Vapor docs say to clear all the existing middleware if you're using custom error middleware
    // https://docs.vapor.codes/4.0/errors/#error-middleware
    app.middleware = .init()
    app.middleware.use(MatrixErrorMiddleware())

    app.databases.use(.postgres(
        hostname: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? PostgresConfiguration.ianaPortNumber,
        username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
        password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
        database: Environment.get("DATABASE_NAME") ?? "vapor_database"
    ), as: .psql)

    app.migrations.add(CreateTodo())

    app.views.use(.leaf)

    // Use Vapor's built-in passwords with Bcrypt
    app.passwords.use(.bcrypt)
    
    //let config = try AppConfig(filename: "swiclops.yaml")
    let testConfigString = """
    uia:
      homeserver: "https://matrix.kombucha.social/"
      routes:
        - path: "/_matrix/client/r0/login"
          method: "POST"
          flows:
            - stages: ["m.login.dummy", "m.login.foo"]
            - stages: ["m.login.terms", "m.login.password"]
        - path: "/_matrix/client/r0/register"
          method: "POST"
          flows:
            - stages: ["m.login.registration_token", "m.login.terms", "m.enroll.email.request_token", "m.enroll.email.submit_token", "m.enroll.password"]
            
    database:
      type: postgres
      hostname: localhost
      port: 5432
      username: swiclops
      password: hunter2
      database: swiclops
    #database:
    #  type: sqlite
    #  filename: "swiclops.sqlite"
    """
    let config = try AppConfig(string: testConfigString)
    
    let uiaController = UiaController(app: app, config: config.uia)
    
    // register routes
    try app.register(collection: uiaController)
    try routes(app)
}

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
        self.username = username ?? Environment.get("DATABASE_USERNAME") ?? "vapor_username"
        self.password = password ?? Environment.get("DATABASE_PASSWORD") ?? "vapor_password"
        self.database = database ?? Environment.get("DATABASE_NAME") ?? "vapor_database"
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

struct AppConfig: Decodable {
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


/* // Example config
 
 database:
   - type: "sqlite"
 
 uia:
  - homeserver: "matrix-synapse"
    routes:
      -
 
 */
