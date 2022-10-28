//
//  GooglePlaySubscriptionHandler.swift
//  
//
//  Created by Charles Wright on 10/13/22.
//

import Vapor
import Fluent
import JWT

// This endpoint handler provides support for Google Play Real Time Developer Notifications (RTDN)
// https://developer.android.com/google/play/billing/getting-ready#configure-rtdn
// Here we must receive push notifications from Google Cloud Pub/Sub that tell us when a Play Store subscription has changed
// https://cloud.google.com/pubsub/docs/push
struct GooglePlaySubscriptionHandler: EndpointHandler {
    static let GPLAY_URL_PATH = "/_swiclops/subscriptions/google/:version/notify"
    var endpoints: [Endpoint] = [
        .init(.POST, GPLAY_URL_PATH)
    ]
    
    // For authenticating requests from Google
    var email: String
    var audience: String
    
    func handle(req: Request) async throws -> Response {
        
        // https://cloud.google.com/pubsub/docs/reference/rest/v1/projects.subscriptions#oidctoken
        struct GoogleJwtPayload: JWTPayload {
            func verify(using signer: JWTSigner) throws {
                throw Abort(.notImplemented)
            }
            
            // serviceAccountEmail
            // string
            var serviceAccountEmail: String

            // audience
            // string
            // Audience to be used when generating OIDC token. The audience claim identifies the recipients that the JWT is intended for. The audience value is a single case-sensitive string. Having multiple values (array) for the audience field is not supported. More info about the OIDC JWT token audience here: https://tools.ietf.org/html/rfc7519#section-4.1.3 Note: if not specified, the Push endpoint URL will be used.
            var audience: String
        }
        
        guard let payload = try? req.jwt.verify(as: GoogleJwtPayload.self),
              payload.serviceAccountEmail == self.email,
              payload.audience == self.audience
        else {
            throw Abort(.forbidden)
        }
        
        // The body of the request should be a Google pub/sub message
        // https://cloud.google.com/pubsub/docs/push#receive_push
        struct GooglePubSubMessage: Content {
            var message: Message
            struct Message: Codable {
                var attributes: [String: String]
                var data: String
                var messageId: String
                var publishTime: Date
            }
            var subscription: String
        }
        
        throw Abort(.notImplemented)
    }
    
    
}
