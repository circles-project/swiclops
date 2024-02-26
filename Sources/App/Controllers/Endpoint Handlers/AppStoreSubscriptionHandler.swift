
import Vapor
import Fluent

import AppStoreServerLibrary

let APP_STORE_NOTIFICATION_PATH = "/_swiclops/subscriptions/apple/:version/notify"

struct AppStoreSubscriptionHandler: EndpointHandler {
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
            req.logger.error("App Store notification: Invalid version \(payload.version) -- should be \"2.0\"")
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
                throw Abort(.notImplemented)

            case .didChangeRenewalStatus:
                throw Abort(.notImplemented)

            case .didFailToRenew:
                throw Abort(.notImplemented)

            case .didRenew:
                throw Abort(.notImplemented)

            case .expired:
                throw Abort(.notImplemented)

            case .gracePeriodExpired:
                throw Abort(.notImplemented)

            case .offerRedeemed:
                throw Abort(.notImplemented)

            case .priceIncrease:
                throw Abort(.notImplemented)

            case .refund:
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
                throw Abort(.notImplemented)

            case .subscribed:
                return try await handleSubscribed(data: data, for: req)
            case .test:
                req.logger.debug("App Store notification is a test")

            default:
                req.logger.debug("App Store notification - Not handling notification of type \(notificationType)")
        }

        // If we're still here then everything must have gone OK so far
        // Return success
        return try await HTTPResponseStatus.ok.encodeResponse(for: req)
    }

    func handleSubscribed(data: NotificationData, for req: Request) async throws -> Response {
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
                let identifier = transaction.appAccountToken,
                let expirationDate = transaction.expiresDate
        else {
            req.logger.error("App Store notification: Could not get transaction information")
            throw Abort(.badRequest)
        }

        req.logger.debug("App Store notification: User subscribed with transaction id \(transactionId) and original transaction id \(originalTransactionId)")

        // NOTE: We don't really have to do anything here?
        //       This one was mostly for practice...
        return try await OK(for: req)
    }

    func OK(for req: Request) async throws -> Response {
        return try await HTTPResponseStatus.ok.encodeResponse(for: req)
    }
}