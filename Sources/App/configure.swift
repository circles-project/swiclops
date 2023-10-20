import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
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
    
    // We need CORS in order to support web clients
    // https://docs.vapor.codes/advanced/middleware/#cors-middleware
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin]
    )
    let cors = CORSMiddleware(configuration: corsConfiguration)
    // cors middleware should come before default error middleware using `at: .beginning`
    app.middleware.use(cors, at: .beginning)
    
    //app.views.use(.leaf)

    // Use Vapor's built-in passwords with Bcrypt
    app.passwords.use(.bcrypt)
    
    // Enable compression in the HTTP client
    app.http.client.configuration.decompression = .enabled(limit: .ratio(100))

    guard let config = try? _loadConfiguration() else {
        app.logger.error("No config file found")
        throw Abort(.internalServerError)
    }
    
    // database
    switch config.database {
    case .sqlite(let sqliteConfig):
        app.logger.debug("Using SQLite database")
        app.databases.use(.sqlite(.file(sqliteConfig.filename)), as: .sqlite)
    case .postgres(let postgresConfig):
        app.logger.debug("Using Postgres database")
        app.databases.use(.postgres(hostname: postgresConfig.hostname,
                                    port: postgresConfig.port,
                                    username: postgresConfig.username,
                                    password: postgresConfig.password,
                                    database: postgresConfig.database),
                          as: .psql)
    }
    
    // migrations
    app.logger.info("Adding migrations")
    app.migrations.add(CreateAcceptedTerms())
    app.migrations.add(CreateBSSpekeUsers())
    app.migrations.add(CreatePasswordHashes())
    app.migrations.add(CreatePendingTokenRegistrations())
    app.migrations.add(CreateRegistrationTokens())
    app.migrations.add(CreateSubscriptions())
    app.migrations.add(CreateUserEmailAddresses())
    app.migrations.add(CreateBadWords())
    app.migrations.add(CreateUsernames())
    
    // routes
    app.logger.info("Configuring routes")
    let uiaController = try UiaController(app: app, config: config.uia, matrixConfig: config.matrix)
    try app.register(collection: uiaController)
    let adminController = AdminApiController(app: app, config: config.admin, matrixConfig: config.matrix)
    try app.register(collection: adminController)
    //try routes(app)
    
    // commands
    app.logger.info("Configuring commands")
    app.commands.use(CreateTokenCommand(), as: "create-token")
    app.commands.use(ListTokensCommand(), as: "list-tokens")
    app.commands.use(SetPasswordCommand(), as: "set-password")
    app.commands.use(LoadBadWordsCommand(), as: "load-badwords")
    app.commands.use(LoadReservedUsernamesCommand(), as: "load-reserved-usernames")
}

private func _loadConfiguration() throws -> AppConfig {
    if let systemConfig = try? AppConfig(filename: "/etc/swiclops/swiclops.yml") {
        return systemConfig
    }
    let localConfig = try AppConfig(filename: "swiclops.yml")
    return localConfig
}

// FIXME: Call this from somewhere when we start up
private func login(app: Application,
                   homeserver: URL,
                   username: String,
                   password: String
) async throws -> MatrixCredentials? {

    let requestBody = LoginRequestBody(identifier: .init(type: "m.id.user", user: username),
                                       type: "m.login.password",
                                       password: password)
    
    let uri = URI(scheme: homeserver.scheme,
                  host: homeserver.host,
                  port: homeserver.port,
                  path: "/_matrix/client/v3/login")
    
    let headers = HTTPHeaders([
        ("Content-Type", "application/json"),
        ("Accept", "application/json")
    ])
    
    app.logger.debug("Sending login request for admin creds")
    let response = try await app.client.post(uri, headers: headers, content: requestBody)

    guard response.status == .ok
    else {
        app.logger.error("Login failed - got HTTP \(response.status.code) \(response.status.reasonPhrase)")
        throw MatrixError(status: response.status, errcode: .unauthorized, error: "Login failed")
    }
    
    let decoder = JSONDecoder()
    guard let buffer = response.body,
          let creds = try? decoder.decode(MatrixCredentials.self, from: buffer)
    else {
        app.logger.error("Failed to parse admin credentials")
        throw MatrixError(status: .internalServerError, errcode: .badJson, error: "Failed to get admin credentials")
    }
    
    app.logger.debug("Login success!")
    app.logger.debug("user_id: \(creds.userId)\tdevice_id: \(creds.deviceId)\taccess_token: \(creds.accessToken)")
    return creds
}
