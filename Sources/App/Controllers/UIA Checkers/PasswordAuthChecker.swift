//
//  PasswordAuthChecker.swift
//  
//
//  Created by Charles Wright on 3/22/22.
//

import Fluent
import Vapor
import AnyCodable

struct PasswordPolicy: Content {
    var minimumLength: Int
    // FIXME: Add zxcvbn
    // * Swift wrapper around C: https://github.com/vzsg/zxcvbn-swift
    // * Rust library that we could wrap: https://github.com/shssoichiro/zxcvbn-rs
    
    func check(password: String) async -> Bool {
        if password.count < self.minimumLength {
            return false
        }
        return true
    }
}

struct PasswordAuthChecker: AuthChecker {
    
    struct LoginUiaRequest: Content {
        struct AuthDict: UiaAuthDict {
            var type: String
            var session: String

            // FIXME: This should actually be flexible to handle different things
            //       See https://spec.matrix.org/v1.2/client-server-api/#identifier-types
            struct mIdUser: Content {
                var type: String
                var user: String
            }
            
            var identifier: mIdUser
            var password: String
        }
        
        var auth: AuthDict
    }

    struct EnrollUiaRequest: Content {
        struct AuthDict: UiaAuthDict {
            var type: String
            var session: String
            var newPassword: String
            
            enum CodingKeys: String, CodingKey {
                case type
                case session
                case newPassword = "new_password"
            }
        }
        var auth: AuthDict
    }
    
    
    static let AUTH_TYPE_LOGIN: String = "m.login.password"
    static let AUTH_TYPE_ENROLL: String = "m.enroll.password"
    
    var app: Application
    var policy: PasswordPolicy
    
    init(app: Application) {
        self.app = app
        self.policy = PasswordPolicy(minimumLength: 8)
    }
    
    func getSupportedAuthTypes() -> [String] {
        [
            PasswordAuthChecker.AUTH_TYPE_LOGIN,
            PasswordAuthChecker.AUTH_TYPE_ENROLL
        ]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        switch authType  {
        case PasswordAuthChecker.AUTH_TYPE_LOGIN:
            return nil
        case PasswordAuthChecker.AUTH_TYPE_ENROLL:
            // FIXME: Why not just encode the Policy itself here???
            return ["minimum_length": AnyCodable(self.policy.minimumLength)]
        default:
            throw Abort(.badRequest)
        }
        
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        switch authType {
        case PasswordAuthChecker.AUTH_TYPE_LOGIN:
            let result = try await self._checkLogin(req: req)
            return result
        case PasswordAuthChecker.AUTH_TYPE_ENROLL:
            let result = try await self._checkEnroll(req: req)
            return result
        default:
            throw Abort(.badRequest)
        }
    }
    
    func _checkLogin(req: Request) async throws -> Bool {
        guard let loginRequest = try? req.content.decode(LoginUiaRequest.self)
        else {
            throw Abort(.badRequest)
        }
        let auth = loginRequest.auth
        guard PasswordAuthChecker.AUTH_TYPE_LOGIN == auth.type,
              "m.id.user" == auth.identifier.type
        else {
            throw Abort(.badRequest)
        }
        
        // Get the stored password hash for this user
        //   - Note that this also verifies whether the user is enrolled with us
        let userId = auth.identifier.user
        guard let hashes = try? await PasswordHash.query(on: req.db)
                                                  .filter(\.$id == userId)
                                                  .all()
        else {
            throw Abort(.forbidden)
        }
        // Extract the password from the request
        let password = auth.password
        // NOTE: Here we're allowing for the possibility that a user might
        //       have more than one hashed password at a time.
        //       I'm not sure how likely that is, but I figured we'd allow it for now.
        for hash in hashes {
            if hash.hashFunc != "bcrypt" {
                continue
            }
            // Compare hashed password with the stored password hash
            guard let success = try? await req.password.async.verify(password, created: hash.digest)
            else {
                throw Abort(.internalServerError)
            }
            if success {
                return true
            }
        }
        // If none of the stored hashes match the password, reject the request
        return false
    }
    
    func _checkEnroll(req: Request) async throws -> Bool {
        req.logger.debug("\(PasswordAuthChecker.AUTH_TYPE_ENROLL): Checking...")
        // Extract the proposed new password from the request
        guard let enrollRequest = try? req.content.decode(EnrollUiaRequest.self),
              enrollRequest.auth.type == PasswordAuthChecker.AUTH_TYPE_ENROLL
        else {
            req.logger.debug("\(PasswordAuthChecker.AUTH_TYPE_ENROLL): Couldn't decode request")
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Invalid request")
        }
        let auth = enrollRequest.auth
        let password = auth.newPassword
        // Check that the password satisfies our policy
        let satisfiesPolicy = await self.policy.check(password: password)
        // If not, return false / Abort with 401 so the user can try again
        if !satisfiesPolicy {
            req.logger.debug("Password is too short for policy")
            throw MatrixError(status: .unauthorized, errcode: .invalidParam, error: "Password does not satisfy policy")
        }
        // Otherwise,
        //   Hash the password
        let digest = try await req.password.async.hash(password)
        req.logger.debug("\(PasswordAuthChecker.AUTH_TYPE_ENROLL): Password hash is [\(digest)]")
        //   Connect to our persistent UIA session state
        let session = req.uia.connectSession(sessionId: auth.session)
        //   Actually save the digest into the session state
        await session.setData(for: PasswordAuthChecker.AUTH_TYPE_ENROLL+".digest", value: digest)

        req.logger.debug("\(PasswordAuthChecker.AUTH_TYPE_ENROLL): Success!")
        return true
    }
    
    func onSuccess(req: Request, authType: String, userId: String) async throws {
        req.logger.debug("PasswordAuthChecker.onEnrolled()")
        guard authType == PasswordAuthChecker.AUTH_TYPE_ENROLL else {
            req.logger.debug("PasswordAuthChecker.onEnroll but authType is not \(PasswordAuthChecker.AUTH_TYPE_ENROLL) -- doing nothing")
            return
        }
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            req.logger.error("PasswordAuthChecker.onEnrolled: Couldn't decode UIA request")
            throw Abort(.badRequest)
        }
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)
        // Look for a hashed password in the session state
        // If we find one, then we just enrolled this user for our auth.  Otherwise, maybe we were in the flows to authenticate the user with an existing password, and they just enrolled with some other auth method.
        if let digest = await session.getData(for: PasswordAuthChecker.AUTH_TYPE_ENROLL+".digest") as? String  {
            req.logger.debug("\(PasswordAuthChecker.AUTH_TYPE_ENROLL): Finishing enrollment for user [\(userId)]")
            // Save the new hash in the database
            let record = PasswordHash(userId: userId, hashFunc: "bcrypt", digest: digest)
            try await record.create(on: req.db)
        } else {
            req.logger.error("PasswordAuthChecker: Can't enroll user \(userId) because there is no digest in the UIA session")
            throw Abort(.internalServerError)
        }    }
    
    
    func onLoggedIn(req: Request, authType: String, userId: String) async throws {
        try await onSuccess(req: req, authType: authType, userId: userId)
    }
    
    func onEnrolled(req: Request, authType: String, userId: String) async throws {
        try await onSuccess(req: req, authType: authType, userId: userId)
    }
    
    func isUserEnrolled(userId: String, authType: String) async -> Bool {
        switch authType {
        case PasswordAuthChecker.AUTH_TYPE_ENROLL:
            // Anyone is eligible to enroll at any time
            return true
            
        case PasswordAuthChecker.AUTH_TYPE_LOGIN:
            // Query the database for any records with the given userId
            // If we found any valid records, return true
            // Otherwise return false
            if let _ = try? await PasswordHash.query(on: app.db)
                                              .filter(\.$id == userId)
                                              .first()
            {
                return true
            }
            else {
                return false
            }
            
        default:
            // Any other authType is some sort of error
            return false
        }
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        // Nobody gets out of doing password auth.  If it's in the config, keep it in the advertised flow(s).
        return true
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // Verify that this request is for us
        // Verify that the given user is enrolled with us
        // Remove the user's entry from our database
        
        try await PasswordHash.query(on: req.db)
                              .filter(\.$id == userId)
                              .delete()
    }
    
    
}
