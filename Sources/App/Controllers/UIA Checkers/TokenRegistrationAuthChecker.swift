//
//  RegistrationTokenAuthChecker.swift
//  
//
//  Created by Charles Wright on 3/28/22.
//

import Vapor
import Fluent
import AnyCodable

struct TokenRegistrationAuthChecker: AuthChecker {
    let AUTH_TYPES = ["org.matrix.msc3231.login.registration_token", "m.login.registration_token"]
    
    let PROVIDER_REGISTRATION_TOKENS = "registration_tokens"
    
    struct TokenRegistrationUiaRequest: Content {
        struct AuthDict: UiaAuthDict {
            var type: String
            var session: String
            var token: String
        }
        var auth: AuthDict
    }
    
    func getSupportedAuthTypes() -> [String] {
        return AUTH_TYPES
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        return nil
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        guard let uiaRequest = try? req.content.decode(TokenRegistrationUiaRequest.self),
              AUTH_TYPES.contains(uiaRequest.auth.type)
        else {
            throw Abort(.badRequest)
        }
        
        let auth = uiaRequest.auth
        let token = auth.token
        let sessionId = auth.session
        
        req.logger.debug("TokenRegistration: Checking auth for session [\(sessionId)] with token [\(token)]")
        
        guard let tokenRecord = try? await RegistrationToken.query(on: req.db)
            .filter(\.$id == token)
            .first()
        else {
            // No such token
            // Request denied.
            req.logger.warning("TokenRegistration: Error: No such token [\(token)]")
            //throw Abort(.forbidden)
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "No such token")
        }
        req.logger.debug("Found registration token")

        if tokenRecord.isExpired {
            req.logger.warning("Token is expired")
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Token is expired")
        }
        
        let numExistingRegistrations = try await InAppSubscription.query(on: req.db)
            .filter(\.$provider == PROVIDER_REGISTRATION_TOKENS)
            .filter(\.$productId == token)
            .count()
        
        if tokenRecord.slots <= numExistingRegistrations {
            // This token is all used up
            req.logger.warning("Token is used up")
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Token is used up")
        }
        
        // Ok, it looks like we've got a good token
        // But we also need to check whether there are already too many pending registrations for it
        let oneHourAgo = Date(timeIntervalSinceNow: -3600) // One hour ago
        let numPendingRegistrations = try await PendingTokenRegistration.query(on: req.db)
            .filter(\.$token == token)
            .filter(\.$createdAt > oneHourAgo)
            .count()
        
        if tokenRecord.slots <= numExistingRegistrations + numPendingRegistrations {
            req.logger.warning("No slots left on token")
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "No slots left on token")
        }
        
        // Add ourselves to the list of pending registrations for this token
        req.logger.debug("Creating pending registration")
        let myPendingRegistration = PendingTokenRegistration(token: token, session: sessionId)
        req.logger.debug("Saving pending registration")
        try await myPendingRegistration.create(on: req.db)
        
        // Finally, add the token to our UIA session state storage
        let session = req.uia.connectSession(sessionId: sessionId)
        await session.setData(for: "registration_token", value: token)
        
        req.logger.debug("Token registration success")
        
        return true
    }
    
    func onSuccess(req: Request, authType: String, userId: String) async throws {
        // Do nothing
    }
    
    func onLoggedIn(req: Request, authType: String, userId: String) async throws {
        // Do nothing
        // FIXME: Actually maybe we should throw an error here -- Using a registration token to log in is just weird
    }
    
    func onEnrolled(req: Request, authType: String, userId: String) async throws {
        // Yay the user's registration was successful
        req.logger.debug("m.login.registration_token: Finalizing enrollment for user [\(userId)]")
        
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            req.logger.error("m.login.registration_token: Couldn't decode UIA request")
            throw Abort(.badRequest)
        }
        
        let auth = uiaRequest.auth
        let sessionId = auth.session
        
        let session = req.uia.connectSession(sessionId: sessionId)
        guard let token = await session.getData(for: "registration_token") as? String else {
            req.logger.error("m.login.registration_token: Can't finalize enrollment because registration_token is missing")
            throw Abort(.internalServerError)
        }
        
        // Yo dawg, we heard you liked tokens...
        // Obviously this isn't a real in-app purchase
        // Just use the token itself for any identifiers that we need
        let mySubscription = InAppSubscription(userId: userId,
                                               provider: PROVIDER_REGISTRATION_TOKENS,
                                               productId: token,
                                               transactionId: token,
                                               originalTransactionId: token,
                                               bundleId: "registration_token",
                                               startDate: Date(),
                                               endDate: nil,
                                               familyShared: false
        )
        
        try await req.db.transaction { transaction in
            try await PendingTokenRegistration.query(on: transaction)
                .filter(\.$token == token)
                .filter(\.$session == sessionId)
                .delete()
            
            try await mySubscription.create(on: transaction)
        }
        
        
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        // No existing user is enrolled for registration tokens
        return false
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        // Nobody should be using a registration token once they're registered
        return false
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // This doesn't even make sense
        // We need to make sure that this is safe to call for ALL of our checkers
        //throw Abort(.notImplemented)
    }
    
    
}
