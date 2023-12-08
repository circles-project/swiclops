//
//  AppStoreSubscriptionChecker.swift
//  
//
//  Created by Charles Wright on 4/21/22.
//

import Vapor
import Fluent
import AnyCodable

import AppStoreServerLibrary

struct AppleStoreKitV2SubscriptionChecker: AuthChecker {
    let AUTH_TYPE_APPSTORE_SUBSCRIPTION = "org.futo.subscription.apple_storekit_v2"
    let PROVIDER_APPLE_STOREKIT2 = "apple_storekit_v2"

    // MARK: config
    var config: Config
    struct Config: Codable {
        struct AppInfo: Codable {
            var appleId: Int64
            var bundleId: String
            var name: String
            var secret: String?
            
            enum CodingKeys: String, CodingKey {
                case appleId = "apple_id"
                case bundleId = "bundle_id"
                case name
                case secret
            }
        }
        let apps: [AppInfo]
        
        struct ProductInfo: Codable {
            var level: Int
            var productId: String
            var shareable: Bool
            var quota: UInt64
            
            enum CodingKeys: String, CodingKey {
                case level
                case productId = "product_id"
                case shareable
                case quota
            }
        }
        let products: [ProductInfo]
        
        let secret: String?
        let environment: AppStoreServerLibrary.Environment
        
        let gracePeriodDays: UInt?
        
        enum CodingKeys: String, CodingKey {
            case apps
            case products
            case secret
            case environment
            case gracePeriodDays = "grace_period_days"
        }
        
                
        var bundleIds: [String] {
            self.apps.map { $0.bundleId }
        }
        
        var appAppleIds: [Int64] {
            self.apps.map { $0.appleId }
        }
        
        var productIds: [String] {
            self.products.map { $0.productId }
        }
    }
    
    var certs: [Foundation.Data]
    var logger: Vapor.Logger
    
    // See https://developer.apple.com/videos/play/wwdc2021/10174
    // For StoreKit2 we need
    // ...
    // * Or maybe just send us the new signed transaction??? -- "signed transactions" are the new name for StoreKit2 app receipts
    //   - Client can grab the JSON representation of the transaction to send to us
    //     `var Transaction.jsonRepresentation: Data { get }`
    //     See https://developer.apple.com/documentation/storekit/transaction/3868410-jsonrepresentation
    //   - The signed transaction is Base64(header) + "." + Base64(payload) + "." + sign(Base64(header) + "." + Base64(payload))
    //     ie, header + payload + signature
    //   - Header and payload are just base64-encoded JSON
    //   - Header contains the algorithm `"alg": "ES256"` and the certificate chain to verify the signature
    //   - Payload contains
    //     * transactionId
    //     * originalTransactionId
    //     * bundleId
    //     * productId
    //     * subscriptionGroupIdentifier
    //     * purchaseDate                  // All dates are now milliseconds since epoch
    //     * originalPurchaseDate
    //     * expiresDate
    //     * type (eg auto-renewable subscription, etc)
    //     * appAccountToken
    //     * revocationDate                // When to stop providing service
    //     * revocationReason
    //     * offerType                     // promotional, intro, ...
    //     * offerIdentifier
    
    // MARK: Request struct
    struct StoreKitV2Request: Content {
        struct AuthDict: UiaAuthDict {
            var type: String
            var session: String
            
            var bundleId: String
            var productId: String
            var signedTransaction: String
            
            enum CodingKeys: String, CodingKey {
                case type
                case session
                case bundleId = "bundle_id"
                case productId = "product_id"
                case signedTransaction = "signed_transaction"
            }
        }
        
        var auth: AuthDict
    }
    
    // MARK: init
    
    init(config: Config, app: Application) {
        self.config = config
        
        let logger = app.logger
        
        let certFilenames = [
            "AppleIncRootCertificate",
            "AppleComputerRootCertificate",
            "AppleRootCA-G2",
            "AppleRootCA-G3",
        ]
        
        self.certs = certFilenames.compactMap {
            guard let url = Bundle.main.url(forResource: $0, withExtension: ".cer", subdirectory: "Certs")
            else {
                logger.error("Failed to get bundle URL for \($0)")
                return nil
            }
            
            guard let data = try? Data(contentsOf: url)
            else {
                logger.error("Failed to load data for \($0) from \(url)")
                return nil
            }
            
            return data
        }
        
        self.logger = logger
    }
    
    func getSupportedAuthTypes() -> [String] {
        return [AUTH_TYPE_APPSTORE_SUBSCRIPTION]
    }
    
    // MARK: getParams
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        return [
            "product_ids": AnyCodable(self.config.productIds)
        ]
    }
    
    // MARK: check
    
    func check(req: Request, authType: String) async throws -> Bool {
        guard let storekitRequest = try? req.content.decode(StoreKitV2Request.self)
        else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse UIA request for \(AUTH_TYPE_APPSTORE_SUBSCRIPTION)")
        }
        let auth = storekitRequest.auth
        let sessionId = auth.session
        let session = req.uia.connectSession(sessionId: sessionId)
        
        guard let userId = await session.getData(for: "user_id") as? String else {
            req.logger.debug("Could not determine user id")
            throw MatrixError(status: .internalServerError, errcode: .forbidden, error: "Could not determine user id")
        }
        
        guard let app = config.apps.first(where: { $0.bundleId == auth.bundleId })
        else {
            req.logger.error("Invalid bundle id")
            throw MatrixError(status: .unauthorized, errcode: .invalidParam, error: "Invalid bundle id")
        }
                
        guard let verifier = try? SignedDataVerifier(rootCertificates: self.certs,
                                                     bundleId: auth.bundleId,
                                                     appAppleId: app.appleId,
                                                     environment: config.environment,
                                                     enableOnlineChecks: true)
        else {
            req.logger.error("Failed to initialize verifier")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to initialize verifier")
        }

        req.logger.debug("Attempting to verify and decode transaction")
        let verificationResult = await verifier.verifyAndDecodeTransaction(signedTransaction: auth.signedTransaction)
        switch verificationResult {
        case .invalid(let verificationError):
            req.logger.error("Verification failed: \(verificationError)")
            throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "Verification failed")
            
        case .valid(let decodedPayload):
            // payload is a JWSTransactionDecodedPayload
            
            let payload: JWSTransactionDecodedPayload = decodedPayload // This is only here to make Xcode show "Jump to Definition" and provide auto-complete hints in the UI
            
            // Check that the transaction is for one of our auto-renewable subscriptions
            
            guard let productId = payload.productId,
                  let product = config.products.first(where: {$0.productId == productId })
            else {
                req.logger.error("Invalid product id")
                throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "Invalid product id")
            }
            
            guard payload.type == .autoRenewableSubscription
            else {
                req.logger.error("Purchase is not an auto-renewable subscription")
                throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "Not a subscription purchase")
            }
            
            // Check that the subscription is not expired or revoked or upgraded
            
            let now = Date()

            let graceDays = config.gracePeriodDays ?? 0
            let gracePeriod = TimeInterval(24*60*60*graceDays)
            
            guard let expirationDate = payload.expiresDate,
                  expirationDate + gracePeriod > now
            else {
                req.logger.error("Subscription is expired")
                throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "Subscription has expired")
            }
            
            if expirationDate > now {
                req.logger.warning("Subscription is in the grace period but we allow this")
            }
            
            if let revocationDate = payload.revocationDate {
                guard revocationDate > now
                else {
                    req.logger.error("Subscription is revoked")
                    throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "Subscription has been revoked")
                }
            }
            
            if let isUpgraded = payload.isUpgraded {
                guard !isUpgraded
                else {
                    req.logger.error("Subscription has been superceded by an upgrade")
                    throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "Subscription has been upgraded")
                }
            }
            
            // Make sure we have an original transaction id -- We require this as the unique id for this subscription
            
            guard let originalTransactionId = payload.originalTransactionId
            else {
                req.logger.error("No original transaction id")
                throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "No original transaction id")
            }
            
            // We also need to know the latest transaction id, to ensure that it hasn't already been used
            
            guard let transactionId = payload.transactionId
            else {
                req.logger.error("No transaction id")
                throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "No transaction id")
            }

            // Check that the subscription hasn't already been used
            
            if product.shareable {
            
                // If this is a family-shareable subscription, then we must check that the family hasn't already exceeded their number of accounts

                let FAMILY_SHARING_MAX_ACCOUNTS = 6
                
                let users = try await InAppSubscription
                                            .query(on: req.db)
                                            .filter(\.$provider == PROVIDER_APPLE_STOREKIT2)
                                            .filter(\.$originalTransactionId == originalTransactionId)  // Match on the original transaction id
                                            .filter(\.$startDate < now)
                                            .filter(\.$endDate > now)
                                            .unique()
                                            .all(\.$userId)
                
                guard users.count <= FAMILY_SHARING_MAX_ACCOUNTS
                else {
                    req.logger.error("Family sharing is already full for this subscription")
                    throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Family sharing is already full")
                }
            }
            else {
                
                // If this is NOT a family-shareable subscription, then we must check that it hasn't been used already
                
                let otherUserIds = try await InAppSubscription
                                                .query(on: req.db)
                                                .filter(\.$provider == PROVIDER_APPLE_STOREKIT2)
                                                .filter(\.$transactionId == transactionId)        // Match on the new id for this transaction
                                                .filter(\.$startDate < now)
                                                .filter(\.$endDate > now)
                                                .unique()
                                                .all(\.$userId)
                
                // We should only ever get one result here
                // However, try to handle some amount of craziness
                for otherUserId in otherUserIds {
                    guard otherUserId == userId
                    else {
                        req.logger.error("Non-shareable subscription is already in use by another user")
                        throw MatrixError(status: .forbidden, errcode: .invalidParam, error: "Subscription purchase is already in use")
                    }
                }

            }
            
            // OK the subscription looks like it's good
            
            // Extract any other relevant information out of the payload and save it in our UIA session
            
            await session.setData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".product_id", value: productId)
            
            let startDate = payload.originalPurchaseDate ?? payload.purchaseDate ?? now
            await session.setData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".start_date", value: startDate)
            
            await session.setData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".expiration_date", value: expirationDate)
            
            await session.setData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".original_transaction_id", value: originalTransactionId)
            
            let familyShared = payload.inAppOwnershipType == .familyShared
            await session.setData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".family_shared", value: familyShared)
            
            if let appAccountToken = payload.appAccountToken {
                await session.setData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".app_account_token", value: appAccountToken)
            }

            // Let the UIA controller know that this stage is complete
            
            return true
        }
        
    }
    
    private func getRequestedSubscription(for userId: String, from req: Request) async throws -> InAppSubscription {
        req.logger.debug("Getting Apple StoreKit2 subscription info from request \(req.id)")
        
        guard let uiaRequest = try? req.content.decode(UiaRequest.self)
        else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse UIA request")
        }
        let auth = uiaRequest.auth
        let sessionId = auth.session
        let session = req.uia.connectSession(sessionId: sessionId)
        
        guard let productId = await session.getData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".product_id") as? String
        else {
            req.logger.error("No product id")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "No product id for new subscription")
        }
        
        let startDate = (await session.getData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".start_date") as? Date) ?? Date()
        
        guard let expirationDate = await session.getData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".expiration_date") as? Date
        else {
            req.logger.error("No expiration date")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "No expiration date for new subscription")
        }
        
        guard let transactionId = await session.getData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".transaction_id") as? String
        else {
            req.logger.error("No transaction id")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "No transaction id for new subscription")
        }
        
        guard let originalTransactionId = await session.getData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".original_transaction_id") as? String
        else {
            req.logger.error("No original transaction id")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "No original transaction id for new subscription")
        }
        
        guard let bundleId = await session.getData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".bundle_id") as? String
        else {
            req.logger.error("No bundle id")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "No bundle id for new subscription")
        }
        
        guard let familyShared = await session.getData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".family_shared") as? Bool
        else {
            req.logger.error("Couldn't get family sharing status")
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "No family sharing status for new subscription")
        }
        
        let appAccountToken = await session.getData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".app_account_token") as? UUID
                
        let subscription = InAppSubscription(userId: userId,
                                             provider: PROVIDER_APPLE_STOREKIT2,
                                             productId: productId,
                                             transactionId: transactionId,
                                             originalTransactionId: originalTransactionId,
                                             bundleId: bundleId,
                                             startDate: startDate,
                                             endDate: expirationDate,
                                             familyShared: familyShared)
        return subscription
    }
    
    func createSubscription(for userId: String, making req: Request) async throws {
        req.logger.debug("Creating subscription for user \(userId)")
        
        let subscription = try await getRequestedSubscription(for: userId, from: req)

        req.logger.debug("Creating subscription record")
        try await subscription.create(on: req.db)
    }
    
    // FIXME: Maybe we need to make this a generic part of the AuthChecker protocol
    func onSuccess(req: Request, userId: String) async throws {
        // Save the subscription in the database
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        // Do nothing
    }
    
    func onEnrolled(req: Request, authType: String, userId: String) async throws {
        // FIXME: Pull the subscription information out of the UIA session and save it to the database
        //   * Product id
        //   * Expiration date
        throw Abort(.notImplemented)
    }
    
    func isUserEnrolled(userId: String, authType: String) async throws -> Bool {
        throw Abort(.notImplemented)
    }
    
    func isRequired(for userId: String, making request: Request, authType: String) async throws -> Bool {
        // Don't ever remove us from the flows -- If we're there, we're there for a reason!
        // FIXME: If we're smart, we could actually use this to demand a renewal from users whose subscription has lapsed
        //   * If the request is for /register, then yes we're required to be in the flow
        //   * If the request is for /login, then we're only required for users whose subscription has lapsed
        //   * If the request is for some other endpoint, then... why are we there in the first place???  Maybe for account recovery???
        //     - Probably it's safest to return `true` if we're unsure what to do
        //   ==> So really, it's only for /login where we might not be required.
        return true
    }
    
    func onUnenrolled(req: Request, userId: String) async throws {
        //throw Abort(.notImplemented)
    }
    
    
}
