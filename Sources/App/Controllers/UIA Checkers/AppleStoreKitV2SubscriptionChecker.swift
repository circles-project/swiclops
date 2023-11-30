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

let SUBSCRIPTION_PROVIDER_APPLE = "apple_storekit_v2"

struct AppleStoreKitV2SubscriptionChecker: AuthChecker {
    let AUTH_TYPE_APPSTORE_SUBSCRIPTION = "org.futo.subscription.apple_storekit_v2"
    
    var config: Config
    struct Config: Codable {
        struct AppInfo: Codable {
            var appleId: Int64
            var name: String
        }
        let apps: [String: AppInfo]
        
        struct ProductInfo: Codable {
            var level: Int
            var shareable: Bool
            var quota: UInt64
        }
        let products: [String: ProductInfo]
        
        let secret: String
        let environment: AppStoreServerLibrary.Environment
        
        var bundleIds: [String] {
            Array(self.apps.keys)
        }
        
        var appAppleIds: [Int64] {
            self.apps.values.map { $0.appleId }
        }
        
        var productIds: [String] {
            Array(self.products.keys)
        }
    }
    
    // See https://developer.apple.com/videos/play/wwdc2021/10174
    // For StoreKit2 we need
    // * Latest transaction ID if this is a new purchase -- But maybe not present if we already had access via family sharing etc
    // * Original transaction ID
    // * UUID for the user (aka "app account token")
    // * Product ID
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
    
    struct StoreKitV2Request: Content {
        struct AuthDict: UiaAuthDict {
            var type: String
            var session: String
            
            var appAppleId: Int64
            var bundleId: String
            var productId: String
            var signedTransaction: String
            
            enum CodingKeys: String, CodingKey {
                case type
                case session
                case appAppleId = "app_apple_id"
                case bundleId = "bundle_id"
                case productId = "product_id"
                case signedTransaction = "signed_transaction"
            }
        }
        
        var auth: AuthDict
    }
    
    
    
    init(config: Config) {
        self.config = config
    }
    
    func getSupportedAuthTypes() -> [String] {
        return [AUTH_TYPE_APPSTORE_SUBSCRIPTION]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        return [
            "product_ids": AnyCodable(self.config.productIds)
        ]
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        guard let storekitRequest = try? req.content.decode(StoreKitV2Request.self)
        else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse UIA request for \(AUTH_TYPE_APPSTORE_SUBSCRIPTION)")
        }
        let auth = storekitRequest.auth
        let sessionId = auth.session
        let session = req.uia.connectSession(sessionId: sessionId)
        
        guard let app = config.apps[auth.bundleId]
        else {
            req.logger.error("Invalid bundle id")
            throw MatrixError(status: .unauthorized, errcode: .invalidParam, error: "Invalid bundle id")
        }
        
        guard app.appleId == auth.appAppleId
        else {
            req.logger.error("Invalid app Apple id")
            throw MatrixError(status: .unauthorized, errcode: .invalidParam, error: "Invalid app Apple ID")
        }
                
        guard let verifier = try? SignedDataVerifier(rootCertificates: [],
                                                     bundleId: auth.bundleId,
                                                     appAppleId: auth.appAppleId,
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
                  config.productIds.contains(productId)
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
                        
            guard let expirationDate = payload.expiresDate,
                  expirationDate > now
            else {
                req.logger.error("Subscription is expired")
                throw MatrixError(status: .unauthorized, errcode: .unauthorized, error: "Subscription has expired")
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
                                             provider: SUBSCRIPTION_PROVIDER_APPLE,
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
