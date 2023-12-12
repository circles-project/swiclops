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
        var developerId: String?
        var packageIds: [String]
        
        struct ProductInfo: Codable {
            var level: Int
            var subscriptionId: String
            var shareable: Bool
            var quota: UInt64
            
            enum CodingKeys: String, CodingKey {
                case level
                case subscriptionId = "subscription_id"
                case shareable
                case quota
            }
        }
        let products: [ProductInfo]

        enum CodingKeys: String, CodingKey {
            case developerId = "developer_id"
            case packageIds = "package_ids"
            case products
        }
        
        var productIds: [String] {
            self.products.map { $0.subscriptionId }
        }
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
                
                var orderId: String        // Order id -- like the transaction id in the App Store
                var package: String        // Which app made the purchase? In the future we might have multiple different apps, eg the social app plus a photo gallery plus a chat client etc etc etc
                
                var subscriptionId: String // The purchased subscription ID (for example, 'monthly001').
                
                var token: String          // The token provided to the user's device when the subscription was purchased.
                
                enum CodingKeys: String, CodingKey {
                    case type
                    case session
                    case orderId = "order_id"
                    case package
                    case subscriptionId = "subscription_id"
                    case token = "token"
                }
            }
            var auth: AuthDict
        }
        
        guard let uiaRequest = try? req.content.decode(PlayStoreUiaRequest.self)
        else {
            req.logger.error("Couldn't parse Play Store UIA request")
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse Play Store UIA request")
        }
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)

        let package = auth.package
        let subscriptionId = auth.subscriptionId
        let orderId = auth.orderId
        let token = auth.token
        
        // First order of business: Are these valid parameters for our available subscriptions?
        if !config.productIds.contains(subscriptionId) {
            req.logger.error("Invalid subscription product id")
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Invalid subscription product id")
        }
        // Also check that the package identifier is valid
        if !config.packageIds.contains(package) {
            req.logger.error("Unknown package id")
            throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Unknown package id")
        }
        
        let VALIDATE_PURCHASES_WITH_GOOGLE = false
        #if VALIDATE_PURCHASES_WITH_GOOGLE
        
        // Ok we have a valid request from the client
        // Now we need to validate their subscription purchase
        // See https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptions/get
        let validationURL = URI(
            //string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(package)/purchases/subscriptions/\(subscriptionId)/tokens/\(token)"
            string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(package)/purchases/subscriptionsv2/tokens/\(token)"
        )
        
        // Send a GET request to the validation URL
        let googleResponse = try await req.client.get(validationURL)
        
        guard googleResponse.status.code == 200
        else {
            req.logger.error("Play Store request failed")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to validate subscription purchase")
        }
        
        // The response should contain transaction data
        guard let purchase = try? googleResponse.content.decode(GooglePlay.SubscriptionPurchaseV2.self)
        else {
            req.logger.error("Failed to validate subscription purchase")
            throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "Failed to validate subscription purchase")
        }
        
        guard let lineItem = purchase.lineItems.first(where: { $0.productId == subscriptionId })
        else {
            req.logger.error("Failed to find a line item for subscription product \(subscriptionId)")
            throw MatrixError(status: .unauthorized, errcode: .invalidParam, error: "Failed to validate subscription purchase")
        }
        
        guard purchase.subscriptionState == .active
        else {
            req.logger.error("Subscription is not active")
            throw MatrixError(status: .unauthorized, errcode: .invalidParam, error: "Subscription is not active")
        }
        
        // Verify that the subscription period includes the current time
        let now = Date()
        let wiggleRoom: TimeInterval = 5 * 60.0  // Allow for clocks to be off by up to 5 minutes
        let startDate = purchase.startTime
        let endDate = lineItem.expiryTime
        
        guard startDate - wiggleRoom < now,
              now < endDate + wiggleRoom
        else {
            req.logger.error("Subscription is not currently valid")
            throw MatrixError(status: .unauthorized, errcode: .invalidParam, error: "Subscription is not currently valid")
        }
        
        // If the transaction needs to be acknowledged, then go ahead and send the acknowledgement now
        // Otherwise Google will automatically cancel it after X hours
        if purchase.acknowledgementState != .acknowledged {
            let acknowledgementURL = URI(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(package)/purchases/subscriptions/\(subscriptionId)/tokens/\(token):acknowledge")
            let ackResponse = try await req.client.post(acknowledgementURL)
            guard ackResponse.status == .ok
            else {
                req.logger.error("Failed to acknowledge transaction")
                throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to acknowledge transaction")
            }
        }
        
        #else
        // Because we're not really validating the token with the Play Store API yet, we need to fake some data that would normally come from Google
        let startDate = Date()
        let endDate = startDate + TimeInterval(2592000.0) // 60 sec * 60 minutes * 24 hours * 30 days for testing
        #endif

        // Ok everything seems to check out.  Looks like we're good to go.
        // Store the subscription info in the UIA state so we can save it to the database in onEnroll()
        await session.setData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".subscription_id", value: subscriptionId)
        await session.setData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".order_id", value: orderId)
        await session.setData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".package_id", value: package)
        await session.setData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".token", value: token)
        await session.setData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".start_date", value: startDate)
        await session.setData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".end_date", value: endDate)
        
        // And we're good!
        req.logger.debug("Successfully validated Google Play subscription")
        return true
    }
    
    func getRequestedSubscription(for userId: String, making req: Request) async throws -> InAppSubscription? {
        guard let uiaRequest = try? req.content.decode(UiaRequest.self) else {
            let msg = "Couldn't parse UIA request"
            req.logger.error("Couldn't parse UIA request")
            throw MatrixError(status: .internalServerError, errcode: .badJson, error: msg)
        }
        let auth = uiaRequest.auth
        let session = req.uia.connectSession(sessionId: auth.session)
        
        guard let subscriptionId = await session.getData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".subscription_id") as? String
        else {
            req.logger.error("Couldn't find requested subscription id")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to find requested subscription id")
        }
        
        guard let orderId = await session.getData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".order_id") as? String
        else {
            req.logger.error("Couldn't find subscription order id")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to find subscription order id")
        }
        
        guard let packageId = await session.getData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".package_id") as? String
        else {
            req.logger.error("Couldn't find requested package id")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to find requested package id")
        }
        
        guard let token = await session.getData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".token") as? String
        else {
            req.logger.error("Couldn't find subscription token")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to find subscription token")
        }
        
        guard let startDate = await session.getData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".start_date") as? Date
        else {
            req.logger.error("Couldn't find requested start date")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to find requested start date")
        }
        
        guard let endDate = await session.getData(for: AUTH_TYPE_PLAYSTORE_SUBSCRIPTION+".end_date") as? Date
        else {
            req.logger.error("Couldn't find requested end date")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to find requested end date")
        }
        
        // FIXME: Return the requested subscription
        return InAppSubscription(userId: userId,
                                 provider: PROVIDER_GOOGLE_PLAY,
                                 productId: subscriptionId,
                                 transactionId: orderId,
                                 originalTransactionId: "n/a", // FIXME: Decide what to do about this
                                 bundleId: packageId,
                                 startDate: startDate,
                                 endDate: endDate,
                                 familyShared: false) // FIXME: Figure out how to tell if a Play Store subscription is family shared
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
        
        guard let subscription = try await getRequestedSubscription(for: userId, making: req)
        else {
            req.logger.error("Couldn't get requested Play Store subscription")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Could not find requested Play Store subscription info")
        }
        
        try await subscription.save(on: req.db)
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        let now = Date()
        let subscriptions = try await InAppSubscription
                                        .query(on: app.db)
                                        .filter(\.$userId == userId)
                                        .filter(\.$provider == PROVIDER_GOOGLE_PLAY)
                                        .filter(\.$startDate < now)
                                        .filter(\.$endDate > now)
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
