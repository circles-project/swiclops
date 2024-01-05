//
//  FreeSubscriptionChecker.swift
//
//
//  Created by Charles Wright on 1/3/24.
//

import Vapor
import Fluent

import AnyCodable

struct FreeSubscriptionChecker: AuthChecker {
    let AUTH_TYPE_FREE_SUBSCRIPTION = "org.futo.subscriptions.free_forever"
    let PROVIDER_FREE_FOREVER = "free_forever"
    let FREE_SUBSCRIPTION_PRODUCT_ID = "free_subscription"

    var app: Application

    init(app: Application) {
        self.app = app
    }
    
    func getSupportedAuthTypes() -> [String] {
        [AUTH_TYPE_FREE_SUBSCRIPTION]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        return nil
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        guard AUTH_TYPE_FREE_SUBSCRIPTION == authType,
              let uiaRequest = try? req.content.decode(UiaRequest.self)
        else {
            req.logger.error("FreeSubscriptionChecker: Wrong auth type: \(authType)")
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Invalid auth type: \(authType)")
        }
        
        guard uiaRequest.auth.type == AUTH_TYPE_FREE_SUBSCRIPTION else {
            req.logger.error("FreeSubscriptionChecker: Bad auth type: \(authType) -- Doesn't match `authType` function parameter")
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Invalid auth type: \(authType)")
        }
        
        req.logger.debug("FreeSubscriptionChecker: Success!")
        return true
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, authType: String, userId: String) async throws {
        
        guard let uiaRequest = try? req.content.decode(UiaRequest.self)
        else {
            req.logger.error("Couldn't parse UIA request")
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse UIA request")
        }
        
        let sessionId = uiaRequest.auth.session
        
        let now = Date()
        let subscription = InAppSubscription(userId: userId,
                                             provider: PROVIDER_FREE_FOREVER,
                                             productId: FREE_SUBSCRIPTION_PRODUCT_ID,
                                             transactionId: sessionId,
                                             originalTransactionId: sessionId,
                                             bundleId: "free",
                                             startDate: now,
                                             endDate: nil,
                                             familyShared: false)
        
        req.logger.debug("Creating subscription record")
        try await subscription.create(on: req.db)
        req.logger.debug("Successfully created subscription record")
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        let record = try await InAppSubscription.query(on: app.db)
                                                .filter(\.$provider == PROVIDER_FREE_FOREVER)
                                                .filter(\.$userId == userId)
                                                .first()
        if record != nil {
            return true
        } else {
            return false
        }
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        return true
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // Can't unenroll from a free subscription
        // Buuuuuut I'm not sure that we need to throw an error and fail the session if someone tries
        //throw Abort(.badRequest)
    }
    
    
}
