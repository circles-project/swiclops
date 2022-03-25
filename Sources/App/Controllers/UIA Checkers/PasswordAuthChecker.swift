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
    
    func check(password: String) async -> Bool {
        if password.count < self.minimumLength {
            return false
        }
        return true
    }
}

struct PasswordAuthChecker: AuthChecker {
    
    let AUTH_TYPE_LOGIN: String = "m.login.password"
    let AUTH_TYPE_ENROLL: String = "m.enroll.password"
    
    var app: Application
    var policy: PasswordPolicy
    
    init(app: Application) {
        self.app = app
        self.policy = PasswordPolicy(minimumLength: 8)
    }
    
    func getSupportedAuthTypes() -> [String] {
        [AUTH_TYPE_LOGIN, AUTH_TYPE_ENROLL]
    }
    
    func getParams(req: Request, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        switch authType  {
        case AUTH_TYPE_LOGIN:
            return nil
        case AUTH_TYPE_ENROLL:
            return ["minimum_length": AnyCodable(self.policy.minimumLength)]
        default:
            throw Abort(.badRequest)
        }
        
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        switch authType {
        case AUTH_TYPE_LOGIN:
            let result = try await self._checkLogin(req: req)
            return result
        case AUTH_TYPE_ENROLL:
            let result = try await self._checkEnroll(req: req)
            return result
        default:
            throw Abort(.badRequest)
        }
    }
    
    func _checkLogin(req: Request) async throws -> Bool {
        guard let loginRequest = try? req.content.decode(PasswordLoginUiaRequest.self)
        else {
            throw Abort(.badRequest)
        }
        let auth = loginRequest.auth
        guard AUTH_TYPE_LOGIN == auth.type,
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
        throw Abort(.forbidden)
        //return false
    }
    
    func _checkEnroll(req: Request) async throws -> Bool {
        // Extract the proposed new password from the request
        guard let enrollRequest = try? req.content.decode(PasswordEnrollUiaRequest.self),
              enrollRequest.auth.type == AUTH_TYPE_ENROLL
        else {
            throw Abort(.badRequest)
        }
        let auth = enrollRequest.auth
        let password = auth.newPassword
        // Check that the password satisfies our policy
        let satisfiesPolicy = await self.policy.check(password: password)
        // If not, return false / Abort with 401 so the user can try again
        if !satisfiesPolicy {
            throw Abort(.unauthorized)
        }
        // Otherwise,
        //   Hash the password
        let digest = try await req.password.async.hash(password)
        //   Connect to our persistent UIA session state
        let session = req.uia.connectSession(sessionId: auth.session)
        //   Actually save the digest into the session state
        session.setData(for: AUTH_TYPE_ENROLL+".digest", value: digest)

        return true
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, userId: String) async throws {
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            throw Abort(.badRequest)
        }
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)
        // Find the hashed password in the session state
        guard let digest = session.getData(for: AUTH_TYPE_ENROLL+".digest") else {
            throw Abort(.internalServerError)
        }
        // Save the new hash in the database
        let record = PasswordHash(userId: userId, hashFunc: "bcrypt", digest: digest)
        try await record.create(on: req.db)
    }
    
    func isEnrolled(userId: String, authType: String) async -> Bool {
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
