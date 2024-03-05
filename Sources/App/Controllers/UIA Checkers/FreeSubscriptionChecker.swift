//
//  FreeSubscriptionChecker.swift
//
//
//  Created by Charles Wright on 1/3/24.
//

import Vapor
import Fluent

import AnyCodable

let AUTH_TYPE_FREE_SUBSCRIPTION = "org.futo.subscriptions.free_forever"

struct FreeSubscriptionChecker: AuthChecker {
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
        return [:]
    }

    func check(req: Request, authType: String) async throws -> Bool {
        guard AUTH_TYPE_FREE_SUBSCRIPTION == authType,
              let uiaRequest = try? req.content.decode(UiaRequest.self)
        else {
            req.logger.error("FreeSubscriptionChecker: Wrong auth type: \(authType)")
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Invalid auth type: \(authType)")
        }

        // For free subscriptions, it's easy to enroll.  Just submit the UIA request with this type at registration.
        // But to authenticate any other request, you must already be enrolled with a free subscription on record in the database.

        if req.url.path.hasSuffix("/register") {
            req.logger.debug("FreeSubscriptionChecker: Success!")
            return true
        } else {
            let auth = uiaRequest.auth
            let sessionId = auth.session
            let session = req.uia.connectSession(sessionId: sessionId)

            guard let userId = try await session.getData(for: "user_id") as? String
            else {
                req.logger.warning("No user id - Failing free subscription check")
                return false
            }

            if try await isUserEnrolled(userId: userId, authType: AUTH_TYPE_FREE_SUBSCRIPTION) {
                req.logger.debug("Free subscription check: Success for user \(userId)")
                return true
            } else {
                req.logger.debug("Free subscription check: Fail: No known subscription for user \(userId)")
                return false
            }
        }
        
    }
    
    func onSuccess(req: Request, authType: String, userId: String) async throws {
        // Do nothing
    }
    
    func onLoggedIn(req: Request, authType: String, userId: String) async throws {
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
        
        do {
            req.logger.debug("Creating subscription record")
            try await subscription.create(on: req.db)
            req.logger.debug("Successfully created subscription record")
        } catch {
            req.logger.error("Failed to create subscription record: \(error)")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to create subscription record")
        }
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
        // We use this for the paid subscription types to enforce renewal for users whose subscription has lapsed
        //   * If the request is for /register, then yes we're always required to be in the flow
        //   * If the request is for /auth/subscription, then the user is explicitly asking to modify their subscription -- so normally we'd stay in the list.  But you can't modify a free forever subscription.  Hmmm....
        //   * If the request is for /login, then we're only required for users whose subscription has lapsed
        //   * If the request is for /refresh, then we're only required for users whose subscription has lapsed
        //   * If the request is for some other endpoint, then... why are we there in the first place???  Maybe for account recovery???
        //   ==> So really, it's only for /register and /auth/subscription where we are always required

        // We are always required for registration
        if request.url.path.hasSuffix("/register") {
            return true
        }
        // Don't take us out of the list if the user is explicitly trying to update their subscription
        else if request.url.path.hasSuffix("/auth/subscription") {
            return true
        }
        // This stage might not be required for other endpoints IF the user already has a valid subscription
        else if try await isUserEnrolled(userId: userId, authType: authType) {
            return false
        }
        // Otherwise keep us in the list, because either the user's subscription has lapsed, or they never had one
        else {
            return true
        }
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // Can't unenroll from a free subscription
        // Buuuuuut I'm not sure that we need to throw an error and fail the session if someone tries
        //throw Abort(.badRequest)
    }
    
    
}
