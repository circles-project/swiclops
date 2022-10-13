//
//  AppStoreSubscriptionChecker.swift
//  
//
//  Created by Charles Wright on 4/21/22.
//

import Vapor
import AnyCodable

struct AppStoreSubscriptionChecker: AuthChecker {
    let AUTH_TYPE_APPSTORE_SUBSCRIPTION = "org.futo.subscription.apple"
    let productIds: [String] // = ["org.futo.circles1month", "org.futo.circles1year"]
    let secret: String
    let environment: AppStore.Environment
    
    struct AppStoreUIARequest: Content {
        struct AuthDict: UiaAuthDict {
            var type: String
            var session: String
            var product: String
            var receipt: String
        }
        var auth: AuthDict
    }
    
    init(productIds: [String], secret: String, environment: AppStore.Environment) {
        self.productIds = productIds
        self.secret = secret
        self.environment = environment
    }
    
    func getSupportedAuthTypes() -> [String] {
        return [AUTH_TYPE_APPSTORE_SUBSCRIPTION]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        return [
            "product_ids": AnyCodable(productIds)
        ]
    }
    
    // Return the expiration date for the purchase of `productId`
    private func _validateReceiptAndGetExpirationDate(_ receipt: String, for productId: String, with req: Request) async throws -> Date {
        let client = req.client
        let uri = URI(string: environment.url)
        
        let appleRequest = AppStore.Request(
            receiptData: receipt,
            password: self.secret,
            excludeOldTransactions: true
        )
        
        let appleResponse = try await client.post(uri, headers: HTTPHeaders(), content: appleRequest)
        guard let appstoreResponse = try? appleResponse.content.decode(AppStore.Response.self)
        else {
            throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Failed to validate App Store receipt")
        }
        
        let now = Date()
        for iap in appstoreResponse.receipt.inApp {
            if iap.productId == productId {
                // Looks like this could be the one
                guard let expirationDate = iap.subscriptionExpirationDate else {
                    continue
                }
                if expirationDate > now {
                    // Cool, this is definitely our guy
                    return expirationDate
                }
            }
        }
        
        // Well, we looked at all the purchases in the receipt, and we didn't find one that matched.
        // Fail the UIA stage
        throw MatrixError(status: .forbidden, errcode: .forbidden, error: "Could not validate App Store purchase for \(productId)")
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        guard let appstoreRequest = try? req.content.decode(AppStoreUIARequest.self)
        else {
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Couldn't parse UIA request for \(AUTH_TYPE_APPSTORE_SUBSCRIPTION)")
        }
        let auth = appstoreRequest.auth
        let sessionId = auth.session
        let session = req.uia.connectSession(sessionId: sessionId)
        let receipt = auth.receipt
        let productId = auth.product
        
        guard productIds.contains(productId) else {
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Invalid product id")
        }
        
        // Get the expiration date for the given product
        let expirationDate = try await _validateReceiptAndGetExpirationDate(receipt, for: productId, with: req)
        
        // If we're still here, then there was a valid purchase of the given productId,
        // with a future expiration date of expirationDate
        // Save the purchase info in our UIA session
        await session.setData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".product_id", value: productId)
        await session.setData(for: AUTH_TYPE_APPSTORE_SUBSCRIPTION+".expiration_date", value: expirationDate)
        
        return true
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
