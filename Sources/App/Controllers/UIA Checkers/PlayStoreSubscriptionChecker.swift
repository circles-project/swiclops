//
//  PlayStoreSubscriptionChecker.swift
//  
//
//  Created by Charles Wright on 10/5/22.
//

import Vapor
import Fluent

import AnyCodable

let AUTH_TYPE_PLAYSTORE_SUBSCRIPTION = "org.futo.subscription.google_play"

struct PlayStoreSubscriptionChecker: AuthChecker {
    
    let PROVIDER_GOOGLE_PLAY = "google_play"
    var app: Application
    var config: Config
    struct Config: Codable {
        var productIds: [String]
        var packageIds: [String]
    }
    
    init(app: Application, config: Config) {
        self.app = app
        self.config = config
    }
    
    func getSupportedAuthTypes() -> [String] {
        [
            AUTH_TYPE_PLAYSTORE_SUBSCRIPTION
        ]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        return [
            "product_ids": AnyCodable(self.config.productIds)
        ]
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        
        struct PlayStoreUiaRequest: Content {
            struct AuthDict: UiaAuthDict {
                var type: String
                var session: String
                
                var package: String        // Which app made the purchase? In the future we might have multiple different apps, eg the social app plus a photo gallery plus a chat client etc etc etc
                
                var subscriptionId: String // The purchased subscription ID (for example, 'monthly001').
                
                var token: String          // The token provided to the user's device when the subscription was purchased.
                
                enum CodingKeys: String, CodingKey {
                    case type
                    case session
                    case package
                    case subscriptionId = "subscription_id"
                    case token = "token"
                }
            }
            var auth: AuthDict
        }
        
        guard let uiaRequest = try? req.content.decode(PlayStoreUiaRequest.self) else {
            let msg = "Couldn't parse Play Store UIA request"
            req.logger.error("\(msg)") // The need for this dance is moronic.  Thanks, SwiftLog.
            throw MatrixError(status: .badRequest, errcode: .badJson, error: msg)
        }
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)

        let package = auth.package
        let subscriptionId = auth.subscriptionId
        let token = auth.token
        
        // First order of business: Are these valid parameters for our available subscriptions?
        if !config.productIds.contains(subscriptionId) {
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Invalid subscription product id")
        }
        // Also check that the package identifier is valid
        if !config.packageIds.contains(package) {
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Unknown package id")
        }
        
        // Ok we have a valid request from the client
        // Now we need to validate their subscription purchase
        // See https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptions/get
        let validationURL = URI(
            string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(package)/purchases/subscriptions/\(subscriptionId)/tokens/\(token)"
        )
        
        // Send a GET request to the validation URL
        let googleResponse = try await req.client.get(validationURL)
        
        // The response should contain transaction data
        guard let transaction = try? googleResponse.content.decode(GooglePlay.SubscriptionPurchase.self) else {
            req.logger.error("Failed to validate subscription purchase")
            throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "Failed to validate subscription purchase")
        }
        
        // Verify that the subscription period includes the current time
        let now = Date()
        let wiggleRoom: TimeInterval = 5 * 60.0  // Allow for clocks to be off by up to 5 minutes
        let startDate = Date(timeIntervalSince1970: Double(transaction.startTimeMillis)) - wiggleRoom
        let endDate = Date(timeIntervalSince1970: Double(transaction.expiryTimeMillis)) + wiggleRoom
        
        guard startDate.distance(to: now) > 0 && now.distance(to: endDate) > 0 else {
            req.logger.error("Subscription is not currently valid")
            throw MatrixError(status: .unauthorized, errcode: .invalidParam, error: "Subscription is not currently valid")
        }
        
        // If the transaction needs to be acknowledged, then go ahead and send the acknowledgement now
        // Otherwise Google will automatically cancel it after X hours
        if transaction.acknowledgementState == 0 {
            let acknowledgementURL = URI(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(package)/purchases/subscriptions/\(subscriptionId)/tokens/\(token):acknowledge")
            let ackResponse = try await req.client.post(acknowledgementURL)
            guard ackResponse.status == .ok else {
                req.logger.error("Failed to acknowledge transaction")
                throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to acknowledge transaction")
            }
        }

        // Ok everything seems to check out.  Looks like we're good to go.
        // Store the subscription info in the UIA state so we can save it to the database in onEnroll()
        await session.setData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".subscription_id", value: subscriptionId)
        await session.setData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".token", value: token)
        await session.setData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".start_date", value: startDate)
        await session.setData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".end_date", value: endDate)
        
        // And we're good!
        req.logger.debug("Successfully validated Google Play subscription")
        return true
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, authType: String, userId: String) async throws {
        // FIXME: Pull the subscription information out of the UIA session and save it to the database
        //   * Subscription product id
        //   * Identifier token
        //   * Expiration date
        
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            let msg = "Couldn't parse UIA request"
            req.logger.error("Couldn't parse UIA request")
            throw MatrixError(status: .internalServerError, errcode: .badJson, error: msg)
        }
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)
        
        guard let subscriptionProductId = await session.getData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".subscription_id") as? String,
              let token = await session.getData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".token") as? String,
              let startDate = await session.getData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".start_date") as? Date,
              let endDate = await session.getData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".end_date") as? Date
        else {
            req.logger.error("Could not retrieve subscription infofor Google Play")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Error finalizing Google Play subscription")
        }
        
        let subscription = Subscription(userId: userId,
                                        provider: PROVIDER_GOOGLE_PLAY,
                                        identifier: token,
                                        startDate: startDate,
                                        endDate: endDate,
                                        level: subscriptionProductId)
        
        try await subscription.save(on: req.db)
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        let subscriptions = try await Subscription
                                        .query(on: app.db)
                                        .filter(\.$userId == userId)
                                        .filter(\.$provider == PROVIDER_GOOGLE_PLAY)
                                        .all()

        return !subscriptions.isEmpty
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        // Don't ever remove us from the flows -- If we're there, we're there for a reason!
        return true
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // We need to make sure that this is safe to call for ALL of our checkers
        //throw Abort(.notImplemented)
    }
    
    
}
