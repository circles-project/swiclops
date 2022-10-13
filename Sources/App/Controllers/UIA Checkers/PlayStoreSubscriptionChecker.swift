//
//  PlayStoreSubscriptionChecker.swift
//  
//
//  Created by Charles Wright on 10/5/22.
//

import Vapor
import Fluent

import AnyCodable


struct PlayStoreSubscriptionChecker: AuthChecker {
    static let AUTH_TYPE_PLAYSTORE_SUBSCRIPTION = "org.futo.subscription.google_play"
    
    var productIds: [String]
    
    init(productIds: [String]) {
        self.productIds = productIds
    }
    
    func getSupportedAuthTypes() -> [String] {
        [
            PlayStoreSubscriptionChecker.AUTH_TYPE_PLAYSTORE_SUBSCRIPTION
        ]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        throw Abort(.notImplemented)
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
        if !productIds.contains(subscriptionId) {
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Invalid subscription product id")
        }
        // FIXME: Also check package
        
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
            throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "Failed to validate subscription purchase")
        }
        
        // Verify that the subscription period includes the current time
        let now = Date()
        let startDate = Date(timeIntervalSince1970: Double(transaction.startTimeMillis))
        let endDate = Date(timeIntervalSince1970: Double(transaction.expiryTimeMillis))
        let wiggleRoom: TimeInterval = 5 * 60.0  // Allow for clocks to be off by up to 5 minutes
        
        guard startDate.distance(to: now) > -wiggleRoom && now.distance(to: endDate) > 0 else {
            throw MatrixError(status: .unauthorized, errcode: .invalidParam, error: "Subscription is not currently valid")
        }
        
        // If the transaction needs to be acknowledged, then go ahead and send the acknowledgement now
        // Otherwise Google will automatically cancel it after X hours
        if transaction.acknowledgementState == 0 {
            let acknowledgementURL = URI(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(package)/purchases/subscriptions/\(subscriptionId)/tokens/\(token):acknowledge")
            let ackResponse = try await req.client.post(acknowledgementURL)
            guard ackResponse.status == .ok else {
                throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to acknowledge transaction")
            }
        }

        // Ok everything seems to check out.  Looks like we're good to go.
        // Store the subscription info in the UIA state so we can save it to the database in onEnroll()
        await session.setData(for: PlayStoreSubscriptionChecker.AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".subscription_id", value: subscriptionId)
        await session.setData(for: PlayStoreSubscriptionChecker.AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".token", value: token)
        
        // And we're good!
        return true
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, authType: String, userId: String) async throws {
        throw Abort(.notImplemented)
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        throw Abort(.notImplemented)
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        throw Abort(.notImplemented)
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        // We need to make sure that this is safe to call for ALL of our checkers
        //throw Abort(.notImplemented)
    }
    
    
}
