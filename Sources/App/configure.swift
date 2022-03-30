import Fluent
import FluentPostgresDriver
import Leaf
import Vapor
import Yams

// configures your application
public func configure(_ app: Application) throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

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
    
    var uiaController = UiaController(app: app,
                                      config: .init(homeserver: URL(string: "https://kombucha.social/")!,
                                                    routes: []),
                                      checkers: ["m.login.password": PasswordAuthChecker(app: app)]
    )
    


    // register routes
    try app.register(collection: uiaController)
    try routes(app)
}

struct AppConfig: Decodable {
    var uia: UiaController.Config
}

func loadConfiguration(filename: String) throws {
    let configData = try Data(contentsOf: URL(fileURLWithPath: filename))
    let decoder = YAMLDecoder()
    let config = try decoder.decode(AppConfig.self, from: configData)
}
