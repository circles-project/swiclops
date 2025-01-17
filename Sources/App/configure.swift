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

    guard let config = try? loadConfiguration(for: app) else {
        app.logger.error("No config file found")
        throw Abort(.internalServerError)
    }
    
    // Save the application config in the app's own storage, for access later at runtime
    app.config = config
    
    // database
    switch config.database {
    case .sqlite(let sqliteConfig):
        app.logger.debug("Using SQLite database")
        app.databases.use(.sqlite(.file(sqliteConfig.filename)), as: .sqlite)
    case .postgres(let postgresConfig):
        app.logger.debug("Using Postgres database")
        let config = SQLPostgresConfiguration(hostname: postgresConfig.hostname,
                                              port: postgresConfig.port,
                                              username: postgresConfig.username,
                                              password: postgresConfig.password,
                                              database: postgresConfig.database,
                                              tls: .disable)
        app.databases.use(.postgres(configuration: config), as: .psql)
    }
    
    // migrations
    app.logger.info("Adding migrations")
    app.migrations.add(CreateAcceptedTerms())
    app.migrations.add(CreateBSSpekeUsers())
    app.migrations.add(CreatePasswordHashes())
    app.migrations.add(CreatePendingTokenRegistrations())
    app.migrations.add(CreateRegistrationTokens())
    app.migrations.add(CreateInAppSubscriptions())
    app.migrations.add(CreateUserEmailAddresses())
    app.migrations.add(CreateBadWords())
    app.migrations.add(CreateUsernames())
    // app.migrations.add(UniqueUsernames())  // Apparently SQLite sucks and can't add a unique constraint to an existing table.  bah.
    
    // admin backend
    app.lifecycle.use(SynapseAdminBackend(sharedSecret: config.adminBackend.sharedSecret))
    
    // routes
    app.logger.info("Configuring routes")
    let uiaController = try UiaController(app: app, config: config.uia, matrixConfig: config.matrix)
    try app.register(collection: uiaController)
    let adminController = AdminApiController(app: app, matrixConfig: config.matrix)
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

private func loadConfiguration(for app: Application) throws -> AppConfig {
    app.logger.debug("Attempting to loading system-wide Swiclops configuration")
    if let systemConfig = try? AppConfig(filename: "/etc/swiclops/swiclops.yml") {
        app.logger.debug("Successfully loaded system-wide configuration")
        return systemConfig
    }
    app.logger.debug("Failed to load system-wide Swiclops configuration")
    
    app.logger.debug("Attempting to load local Swiclops config")
    if let localConfig = try? AppConfig(filename: "swiclops.yml") {
        app.logger.debug("Successfully loaded local config")
        return localConfig
    }
    
    app.logger.error("Failed to load any Swiclops configuration")
    throw Abort(.internalServerError)
}


