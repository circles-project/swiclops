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
    let AUTH_TYPE_PLAYSTORE_SUBSCRIPTION = "org.futo.subscription.google_play"
    var productIds: [String]
    
    init(productIds: [String]) {
        self.productIds = productIds
    }
    
    func getSupportedAuthTypes() -> [String] {
        [AUTH_TYPE_PLAYSTORE_SUBSCRIPTION]
    }
    
    func getParams(req: Request, sessionId: String, authType: String, userId: String?) async throws -> [String : AnyCodable]? {
        throw Abort(.notImplemented)
    }
    
    func check(req: Request, authType: String) async throws -> Bool {
        
        struct PlayStoreUiaRequest: Content {
            struct AuthDict: UiaAuthDict {
                var type: String
                var session: String
                var purchaseToken: String  // This one stays the same across every renewal of a given subscription
                                           // Note from: https://developer.android.com/google/play/billing/index.html "Subscription upgrades, downgrades, and other subscription purchase flows generate purchase tokens that must replace a previous purchase token."
                var orderId: String        // This one is unique for each purchase / renewal
                
                enum CodingKeys: String, CodingKey {
                    case type
                    case session
                    case purchaseToken = "purchase_token"
                    case orderId = "order_id"
                }
            }
            var auth: AuthDict
        }
        
        guard let uiaRequest = try? req.content.decode(PlayStoreUiaRequest.self) else {
            let msg = "Couldn't parse Play Store UIA request"
            req.logger.error("\(msg)") // The need for this dance is moronic.  Thanks, SwiftLog.
            throw MatrixError(status: .badRequest, errcode: .badJson, error: msg)
        }
        
        throw Abort(.notImplemented)
    }
    
    func onLoggedIn(req: Request, userId: String) async throws {
        throw Abort(.notImplemented)
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
        throw Abort(.notImplemented)
    }
    
    
}
