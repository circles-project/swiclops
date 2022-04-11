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
        
        guard let tokenRecord = try? await RegistrationToken.query(on: req.db)
            .filter(\.$id == token)
            .first()
        else {
            // No such token
            // Request denied.
            throw Abort(.forbidden)
        }

        if tokenRecord.isExpired {
            throw Abort(.forbidden)
        }
        
        let numExistingRegistrations = try await Subscription.query(on: req.db)
            .filter(\.$provider == "token")
            .filter(\.$identifier == token)
            .count()
        
        if tokenRecord.slots <= numExistingRegistrations {
            // This token is all used up
            throw Abort(.forbidden)
        }
        
        // Ok, it looks like we've got a good token
        // But we also need to check whether there are already too many pending registrations for it
        let oneHourAgo = Date(timeIntervalSinceNow: -3600) // One hour ago
        let numPendingRegistrations = try await PendingTokenRegistration.query(on: req.db)
            .filter(\.$id == token)
            .filter(\.$createdAt > oneHourAgo)
            .count()
        
        if tokenRecord.slots <= numExistingRegistrations + numPendingRegistrations {
            throw Abort(.forbidden)
        }
        
        // Add ourselves to the list of pending registrations for this token
        let myPendingRegistration = PendingTokenRegistration(id: token, session: sessionId)
        try await myPendingRegistration.create(on: req.db)
        
        // Finally, add the token to our UIA session state storage
        let session = req.uia.connectSession(sessionId: sessionId)
        await session.setData(for: "registration_token", value: token)
        
        return true
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, userId: String) async throws {
        // Yay the user's registration was successful
        
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            throw Abort(.badRequest)
        }
        
        let auth = uiaRequest.auth
        let sessionId = auth.session
        
        let session = req.uia.connectSession(sessionId: sessionId)
        guard let token = await session.getData(for: "registration_token") as? String else {
            throw Abort(.internalServerError)
        }
        
        let mySubscription = Subscription(userId: userId,
                                          provider: "token",
                                          identifier: token,
                                          startDate: Date(),
                                          endDate: nil,
                                          level: "standard"
        )
        
        try await req.db.transaction { transaction in
            try await PendingTokenRegistration.query(on: transaction)
                .filter(\.$id == token)
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
        throw Abort(.notImplemented)
    }
    
    
}
