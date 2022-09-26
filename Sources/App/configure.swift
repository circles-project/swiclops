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
    
    //app.views.use(.leaf)

    // Use Vapor's built-in passwords with Bcrypt
    app.passwords.use(.bcrypt)
    
    /*
    let testConfigString = """
    uia:
      domain: "circu.li"
      homeserver: "https://matrix.circu.li/"
      registration_shared_secret: "hunter2"
      bsspeke_oprf_secret: "0123456789abcdef0123456789abcdef"
      default_flows:
        - stages: ["m.login.password"]
        - stages: ["m.login.bsspeke-ecc.oprf", "m.login.bsspeke-ecc.verify"]
      routes:
        - path: "/login"
          method: "POST"
          flows:
            - stages: ["m.login.dummy", "m.login.foo"]
            - stages: ["m.login.terms", "m.login.password"]
        - path: "/register"
          method: "POST"
          flows:
            - stages: ["m.login.registration_token", "m.login.terms", "m.enroll.email.request_token", "m.enroll.email.submit_token", "m.enroll.password"]
        - path: "/account/auth"
          method: "POST"
          flows:
            - stages: ["m.login.password"]
            - stages: ["m.login.bsspeke-ecc.oprf", "m.login.bsspeke-ecc.verify"]
            
    #database:
    #  type: postgres
    #  hostname: localhost
    #  port: 5432
    #  username: swiclops
    #  password: hunter2
    #  database: swiclops
    database:
      type: sqlite
      filename: "swiclops.sqlite"
    """
    let config = try AppConfig(string: testConfigString)
    */

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
    app.migrations.add(CreateAcceptedTerms())
    app.migrations.add(CreateBSSpekeUsers())
    app.migrations.add(CreatePasswordHashes())
    app.migrations.add(CreatePendingTokenRegistrations())
    app.migrations.add(CreateRegistrationTokens())
    app.migrations.add(CreateSubscriptions())
    app.migrations.add(CreateUserEmailAddresses())
    
    // routes
    let uiaController = UiaController(app: app, config: config.uia, matrixConfig: config.matrix)
    try app.register(collection: uiaController)
    let adminController = AdminApiController(app: app, config: config.admin, matrixConfig: config.matrix)
    try app.register(collection: adminController)
    //try routes(app)
    
    // commands
    app.commands.use(CreateTokenCommand(), as: "create-token")
    app.commands.use(ListTokensCommand(), as: "list-tokens")
    app.commands.use(SetPasswordCommand(), as: "set-password")
}

private func _loadConfiguration() throws -> AppConfig {
    if let systemConfig = try? AppConfig(filename: "/etc/swiclops/swiclops.yml") {
        return systemConfig
    }
    let localConfig = try AppConfig(filename: "swiclops.yml")
    return localConfig
}
