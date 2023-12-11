//
//  Application+admin.swift
//
//
//  Created by Charles Wright on 10/23/23.
//

import Vapor




struct AdminBackendKey: StorageKey {
    typealias Value = SynapseAdminBackend
}

class SynapseAdminBackend: LifecycleHandler {
    var creds: MatrixCredentials?
    var sharedSecret: String
    
    init(creds: MatrixCredentials? = nil, sharedSecret: String) {
        self.creds = creds
        self.sharedSecret = sharedSecret
    }
    
    public func login(app: Application) async throws {
        
        // This only works if we have a MatrixConfig in the application's config
        guard let config = app.config
        else {
            app.logger.error("login failed - Can't log in without a config")
            throw Abort(.internalServerError)
        }
        
        guard let username = config.adminBackend.username,
              let password = config.adminBackend.password
        else {
            app.logger.error("login failed - Can't log in without username and password")
            throw Abort(.internalServerError)
        }
              
        let homeserver = config.matrix.homeserver
        let domain = config.matrix.domain

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
        self.creds = creds
    }
    
    public func logout(app: Application) async throws {
        if let creds = self.creds {
            guard let config = app.config
            else {
                app.logger.error("logout() - Failure - Can't get application config")
                throw Abort(.internalServerError)
            }
            
            let homeserver = config.matrix.homeserver
            
            let url = URI(scheme: homeserver.scheme, host: homeserver.host, port: homeserver.port, path: "/_matrix/client/v3/logout")
            let headers = HTTPHeaders([
                ("Accept", "application/json"),
                ("Authorization", "Bearer \(creds.accessToken)")
            ])
            app.logger.debug("logout() - Sending /logout request")
            let response = try await app.client.post(url, headers: headers)
            if response.status == .ok {
                app.logger.debug("logout() - Success")
            } else {
                app.logger.error("logout() - Failure - Received HTTP \(response.status.code) \(response.status.reasonPhrase)")
            }
        } else {
            app.logger.debug("logout() - No need to log out - We don't have any creds")
        }
    }
    
    func willBoot(_ app: Application) throws {
        app.admin = self
    }
    
    func didBoot(_ app: Application) throws {
        Task {
            try await self.login(app: app)
        }
    }
    
    func shutdown(_ app: Application) {
        Task {
            try await self.logout(app: app)
        }
    }
}

extension Application {
    
    // FIXME: What we really need is app.admin.creds
    //        And then we can have app.amin.login() and app.admin.logout() etc
    //        And app.admin.config for its config ...
    

    
    var admin: SynapseAdminBackend? {
        get {
            self.storage[AdminBackendKey.self]
        }
        set {
            self.storage[AdminBackendKey.self] = newValue
        }
    }

}
