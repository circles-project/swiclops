
import Vapor
import Fluent

import AppStoreServerLibrary

let APP_STORE_NOTIFICATION_PATH = "/_swiclops/subscriptions/apple/:version/notify"

struct AppStoreNotificationHandler: EndpointHandler {
    typealias Environment = AppStoreServerLibrary.Environment
    typealias NotificationData = AppStoreServerLibrary.Data    // FFS Apple you could at least try to pick names that don't clash with Foundation

    var endpoints = [
        Endpoint(.POST, APP_STORE_NOTIFICATION_PATH)
    ]
    var environment: Environment = .production
    var verifiers: [String: SignedDataVerifier] = [:]
    
    func handle(req: Request) async throws -> Response {
        guard let body = try? req.content.decode(ResponseBodyV2.self)
        else {
            req.logger.error("Failed to parse App Store ResponseBodyV2 for notification")
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "Bad ResponseBodyV2")
        }

        guard let signedPayload = body.signedPayload
        else {
            req.logger.error("App Store notification: No signed payload")
            throw MatrixError(status: .badRequest, errcode: .badJson, error: "No signed payload")
        }

        // Ugh what a pain - it doesn't tell us which app is associated with the signature,
        // but we have to know the app info in order to construct a verifier.
        // Quick and dirty fix: Create a verifier for each app in our config, and just try them all.
        for verifier in self.verifiers.values {
            let verificationResult = await verifier.verifyAndDecodeNotification(signedPayload: signedPayload)

            if case let .valid(payload) = verificationResult {
                req.logger.debug("App Store notification: Verification success")
                return try await handleVerifiedPayload(payload, for: req)
            }
        }

        // If we're still here, then none of our verifiers could verify the signature
        req.logger.error("App Store notification: No verifier could verify signed payload")
        throw Abort(.internalServerError)
    }

    func getVerifier(bundleId: String, environment: Environment) -> SignedDataVerifier? {
        if environment != self.environment {
            return nil
        } else {
            return self.verifiers[bundleId]
        }

    }

    func handleVerifiedPayload(_ payload: ResponseBodyV2DecodedPayload, for req: Request) async throws -> Response {

        guard payload.version == "2.0"
        else {
            req.logger.error("App Store notification: Invalid version \(payload.version ?? "(none)") -- should be \"2.0\"")
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "Bad payload version")
        }

        guard let notificationType = payload.notificationType
        else {
            req.logger.error("App Store notification: No notification type")
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "No notificationType")
        }

        guard let data = payload.data
        else {
            req.logger.error("App Store notification: No payload data")
            throw MatrixError(status: .badRequest, errcode: .invalidParam, error: "No payload data")
        }

        req.logger.debug("App Store notification type is \(notificationType)")

        switch notificationType {
            case .consumptionRequest:
                throw Abort(.notImplemented)

            case .didChangeRenewalPref:
                // User changed their subscription level
                return try await handleDidChangeRenewalPref(data: data, subtype: payload.subtype, for: req)

            case .didChangeRenewalStatus:
                // Not much for us to do here -- the user changed their mind about whether they want to auto-renew
                // In the future we could send them a special offer if they decided to stop renewing...
                return try await OK(for: req)

            case .didFailToRenew:
                // TODO: Send the user an email to let them know that their renewal failed
                return try await OK(for: req)
            
            case .didRenew:
                return try await handleDidRenew(data: data, subtype: payload.subtype, for: req)

            case .expired:
                // TODO: Send the user an email to remind them they need to renew
                return try await OK(for: req)

            case .gracePeriodExpired:
                // TODO: Send the user an email to let them know their account is now inactive
                return try await OK(for: req)

            case .offerRedeemed:
                // We don't do offers yet
                return try await OK(for: req)

            case .priceIncrease:
                // The system has informed the user about a price increase
                // Nothing for us to do yet right now
                return try await OK(for: req)

            case .refund:
                // The App Store refunded the user's money
                // Nuke their account
                throw Abort(.notImplemented)

            case .refundDeclined:
                throw Abort(.notImplemented)

            case .refundReversed:
                throw Abort(.notImplemented)

            case .renewalExtended:
                throw Abort(.notImplemented)

            case .renewalExtension:
                throw Abort(.notImplemented)

            case .revoke:
                // The purchaser canceled family sharing, or the user left the family group - ouch!
                return try await handleRevoke(data: data, subtype: payload.subtype, for: req)

            case .subscribed:
                return try await handleSubscribed(data: data, subtype: payload.subtype, for: req)
            case .test:
                req.logger.debug("App Store notification is a test")
                return try await OK(for: req)

            default:
                req.logger.debug("App Store notification - Not handling notification of type \(notificationType)")
        }

        // If we're still here then everything must have gone OK so far
        // Return success
        return try await OK(for: req)
    }
    
    // MARK: did change renewal pref
    /*
        DID_CHANGE_RENEWAL_PREF
        A notification type that, along with its subtype, indicates that the user made a change to their subscription plan. If the subtype is UPGRADE, the user upgraded their subscription. The upgrade goes into effect immediately, starting a new billing period, and the user receives a prorated refund for the unused portion of the previous period. If the subtype is DOWNGRADE, the user downgraded their subscription. Downgrades take effect at the next renewal date and don’t affect the currently active plan.
    
        If the subtype is empty, the user changed their renewal preference back to the current subscription, effectively canceling a downgrade.
     */
    func handleDidChangeRenewalPref(data: NotificationData,
                                    subtype: Subtype?,
                                    for req: Request
    ) async throws -> Response {
        req.logger.debug("App Store notification: Handling didChangeRenewalPref")
        guard let bundleId = data.bundleId,
              let environment = data.environment,
              let verifier = getVerifier(bundleId: bundleId, environment: environment)
        else {
            req.logger.error("App Store notification: Can't get verifier for renewal notification")
            throw Abort(.internalServerError)
        }
        
        // TODO: Handle upgrades immediately
        
        // TODO: Handle downgrades by creating a new subscription record
        
        return try await OK(for: req)
    }
    
    // MARK: did renew
    /*
        DID_RENEW
        A notification type that, along with its subtype, indicates that the subscription successfully renewed. If the subtype is BILLING_RECOVERY, the expired subscription that previously failed to renew has successfully renewed. If the substate is empty, the active subscription has successfully auto-renewed for a new transaction period. Provide the customer with access to the subscription’s content or service.
     
        BILLING_RECOVERY
        Applies to the DID_RENEW notificationType. A notification with this subtype indicates that the expired subscription that previously failed to renew has successfully renewed.
     */
    func handleDidRenew(data: NotificationData,
                        subtype: Subtype?,
                        for req: Request
    ) async throws -> Response {
        req.logger.debug("App Store notification: Handling didRenew")
        guard let bundleId = data.bundleId,
                let environment = data.environment,
                let verifier = getVerifier(bundleId: bundleId, environment: environment)
        else {
            req.logger.error("App Store notification: Can't get verifier for renewal notification")
            throw Abort(.internalServerError)
        }
        
        guard let signedRenewalInfo = data.signedRenewalInfo
        else {
            req.logger.error("App Store notification: No renewal info for renewal notification")
            throw Abort(.internalServerError)
        }
        
        let verificationResult = await verifier.verifyAndDecodeRenewalInfo(signedRenewalInfo: signedRenewalInfo)

        switch verificationResult {
        case .invalid(let error):
            req.logger.error("App Store notification: Failed to verify signed renewal info: \(error)")
            throw Abort(.badRequest)
        case .valid(let renewalInfoPayload):
            let payload: JWSRenewalInfoDecodedPayload = renewalInfoPayload // For Xcode "jump to definition"
            
            let now = Date()
            
            guard let originalTransactionId = payload.originalTransactionId,
                  let productId = payload.autoRenewProductId,
                  let renewalDate = payload.renewalDate
            else {
                req.logger.error("App Store notification: Could not get required info")
                throw Abort(.badRequest)
            }
            
            guard renewalDate > now
            else {
                req.logger.error("App Store notification: Renewal date is in the past")
                throw Abort(.internalServerError)
            }
            
            // Find all currently active subscriptions with the given original transaction id
            let activeSubscriptions = try await InAppSubscription.query(on: req.db)
                                                                 .filter(\.$provider == PROVIDER_APPLE_STOREKIT2)
                                                                 .filter(\.$originalTransactionId == originalTransactionId)
                                                                 .filter(\.$startDate < now)
                                                                 .filter(\.$endDate > now)
                                                                 .filter(\.$endDate < renewalDate)
                                                                 .all()
            // Create a new subscription
            let newSubscriptions = activeSubscriptions.compactMap {
                InAppSubscription(userId: $0.userId,
                                  provider: PROVIDER_APPLE_STOREKIT2,
                                  productId: productId,
                                  transactionId: "???",
                                  originalTransactionId: originalTransactionId,
                                  bundleId: bundleId,
                                  startDate: $0.endDate!,
                                  endDate: renewalDate,
                                  familyShared: $0.familyShared)
            }
            
            try await newSubscriptions.create(on: req.db)
            
            return try await OK(for: req)
        }
    }

    // MARK: revoke
    /*
        REVOKE
        A notification type that indicates that an in-app purchase the user was entitled to through Family Sharing is no longer available through sharing. The App Store sends this notification when a purchaser disables Family Sharing for their purchase, the purchaser (or family member) leaves the family group, or the purchaser receives a refund.
     */
    func handleRevoke(data: NotificationData,
                      subtype: Subtype?,
                      for req: Request
    ) async throws -> Response {
        throw Abort(.notImplemented)
    }
    
    // MARK: subscribed
    /*
        SUBSCRIBED
        A notification type that, along with its subtype, indicates that the user subscribed to a product. If the subtype is INITIAL_BUY, the user either purchased or received access through Family Sharing to the subscription for the first time. If the subtype is RESUBSCRIBE, the user resubscribed or received access through Family Sharing to the same subscription or to another subscription within the same subscription group.
     */
    func handleSubscribed(data: NotificationData,
                          subtype: Subtype?,
                          for req: Request
    ) async throws -> Response {
        guard let bundleId = data.bundleId,
                let environment = data.environment,
                let verifier = getVerifier(bundleId: bundleId, environment: environment)
        else {
            req.logger.error("App Store notification: Can't get verifier for subscribed notification")
            throw Abort(.internalServerError)
        }

        guard let signedTransaction = data.signedTransactionInfo
        else {
            req.logger.error("App Store notification: No transaction for subscribed notification")
            throw Abort(.badRequest)
        }

        let verificationResult = await verifier.verifyAndDecodeTransaction(signedTransaction: signedTransaction)

        guard case let .valid(transactionPayload) = verificationResult
        else {
            req.logger.error("App Store notification: Verification failed for subscribed notification")
            throw Abort(.internalServerError)
        }

        let transaction: JWSTransactionDecodedPayload = transactionPayload

        guard let originalTransactionId = transaction.originalTransactionId,
              let transactionId = transaction.transactionId,
              let productId = transaction.productId,
              let appAccountToken = transaction.appAccountToken,
              let purchaseDate = transaction.purchaseDate,
              let expirationDate = transaction.expiresDate,
              let ownershipType = transaction.inAppOwnershipType
        else {
            req.logger.error("App Store notification: Could not get transaction information")
            throw Abort(.badRequest)
        }

        req.logger.debug("App Store notification: User subscribed with transaction id \(transactionId) and original transaction id \(originalTransactionId)")

        // NOTE: We don't really have to do anything here?
        //       When the user subscribes we need their client to send us their signed transaction in a UIA flow, and we will set up their account at that time
        //       Even for re-subscribe, we don't know which former accounts should be re-activated.  So we wait for their clients to connect and tell us.
        //       Turns out this one was mostly for practice...
        return try await OK(for: req)
    }

    func OK(for req: Request) async throws -> Response {
        return try await HTTPResponseStatus.ok.encodeResponse(for: req)
    }
}
