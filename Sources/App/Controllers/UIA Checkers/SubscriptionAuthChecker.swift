//
//  AppStoreSubscriptionChecker.swift
//  
//
//  Created by Charles Wright on 2/12/24.
//

import Vapor
import Fluent
import AnyCodable

let AUTH_TYPE_FUTO_SUBSCRIPTIONS = "org.futo.subscriptions"

struct SubscriptionAuthChecker: AuthChecker {
    var app: Application
    var checkers: [String: AuthChecker]

    init(app: Application, checkers: [String: AuthChecker]) {
        self.app = app
        self.checkers = checkers
    }

    func getSupportedAuthTypes() -> [String] {
        [AUTH_TYPE_FUTO_SUBSCRIPTIONS]
    }
    
    func getParams(req: Request,
                   sessionId: String,
                   authType: String,
                   userId: String?
    ) async throws -> [String:AnyCodable]? {

        guard authType == AUTH_TYPE_FUTO_SUBSCRIPTIONS
        else {
            req.logger.error("Subscription checker does not handle \(authType)")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Subscription checker does not handle \(authType)")
        }

        var myParams = [String:AnyCodable]()
        for (type, checker) in self.checkers {
            // NOTE: Careful to use the checker's type here, not ours
            let params = try await checker.getParams(req: req, sessionId: sessionId, authType: type, userId: userId)
            myParams[type] = AnyCodable(params)
        }

        return myParams
    }

    struct SubscriptionUiaRequest: Codable {
        var auth: AuthDict
        struct AuthDict: UiaAuthDict {
            var session: String
            var type: String
            var subscriptionType: String

            enum CodingKeys: String, CodingKey {
                case session
                case type
                case subscriptionType = "subscription_type"
            }
        }
    }
    
    func check(req: Request, authType: String) async throws -> Bool {

        guard authType == AUTH_TYPE_FUTO_SUBSCRIPTIONS
        else {
            req.logger.error("Subscription checker does not handle \(authType)")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Subscription checker does not handle \(authType)")
        }

        guard let subscriptionRequest = try? req.content.decode(SubscriptionUiaRequest.self)
        else {
            req.logger.error("Subscription checker: Invalid request")
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Invalid subscription request")
        }

        let subscriptionType = subscriptionRequest.auth.subscriptionType
        guard let checker = self.checkers[subscriptionType]
        else {
            throw MatrixError(status: .forbidden, errcode: .forbidden, error: "Subscription type not supported")
        }

        return try await checker.check(req: req, authType: subscriptionType)
    }
    
    func onLoggedIn(req: Request, userId: String) async throws -> Void {

    }

    func onEnrolled(req: Request, authType: String, userId: String) async throws -> Void {

    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        guard authType == AUTH_TYPE_FUTO_SUBSCRIPTIONS
        else {
            app.logger.error("Subscription checker: Invalid auth type \(authType)")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Invalid subscription auth type \(authType)")
        }

        // The user is enrolled for subscriptions IFF they are enrolled for one of the specific subscription types

        for (subscriptionType, checker) in self.checkers {
            if try await checker.isUserEnrolled(userId: userId, authType: subscriptionType) {
                return true
            }
        }

        return false
    }

    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        guard authType == AUTH_TYPE_FUTO_SUBSCRIPTIONS
        else {
            request.logger.error("Subscription checker: Invalid auth type \(authType)")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Unknown subscription auth type \(authType)")
        }

        // FIXME: This code is the same for every subscription checker -- Needs to be a bit more DRY

        // If we're smart, we will use this to demand a renewal from users whose subscription has lapsed
        //   * If the request is for /register, then yes we're always required to be in the flow
        //   * If the request is for /auth/subscription, then the user is explicitly asking to modify their subscription -- so keep us in the list
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
    
    func onUnenrolled(req: Request, userId: String) async throws -> Void {
        // Not implemented / Do nothing ???
    }
}
