//
//  GooglePlay.swift
//  
//
//  Created by Charles Wright on 10/12/22.
//

import Vapor

enum GooglePlay {
    // MARK: Money
    // https://developers.google.com/android-publisher/api-ref/rest/v3/Money
    struct Money: Codable {
        // The three-letter currency code defined in ISO 4217.
        var currencyCode: String
        
        // string (int64 format)
        // The whole units of the amount. For example if currencyCode is "USD", then 1 unit is one US dollar.
        var units: String
        
        var nanos: Int
    }
    
    // MARK: SubscriptionPurchase
    // https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptions#resource:-subscriptionpurchase
    struct SubscriptionPurchase: Content {
        // kind
        // string
        // This kind represents a subscriptionPurchase object in the androidpublisher service.
        var kind: String

        // startTimeMillis
        // string (int64 format)
        // Time at which the subscription was granted, in milliseconds since the Epoch.
        var startTimeMillis: Int64

        // expiryTimeMillis
        // string (int64 format)
        // Time at which the subscription will expire, in milliseconds since the Epoch.
        var expiryTimeMillis: Int64

        // autoResumeTimeMillis
        // string (int64 format)
        // Time at which the subscription will be automatically resumed, in milliseconds since the Epoch. Only present if the user has requested to pause the subscription.
        var autoResumeTimeMillis: Int64?

        // autoRenewing
        // boolean
        // Whether the subscription will automatically be renewed when it reaches its current expiry time.
        var autoRenewing: Bool
        
        // priceCurrencyCode
        // string
        // ISO 4217 currency code for the subscription price. For example, if the price is specified in British pounds sterling, priceCurrencyCode is "GBP".
        var priceCurrencyCode: String

        // priceAmountMicros
        // string (int64 format)
        // Price of the subscription, For tax exclusive countries, the price doesn't include tax. For tax inclusive countries, the price includes tax. Price is expressed in micro-units, where 1,000,000 micro-units represents one unit of the currency. For example, if the subscription price is €1.99, priceAmountMicros is 1990000.
        var priceAmountMicros: Int64

        // introductoryPriceInfo
        // object (IntroductoryPriceInfo)
        // Introductory price information of the subscription. This is only present when the subscription was purchased with an introductory price. This field does not indicate the subscription is currently in introductory price period.
        var introductoryPriceInfo: IntroductoryPriceInfo
        
        // https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptions#IntroductoryPriceInfo
        struct IntroductoryPriceInfo: Codable {
            // introductoryPriceCurrencyCode
            // string
            // ISO 4217 currency code for the introductory subscription price. For example, if the price is specified in British pounds sterling, priceCurrencyCode is "GBP".
            var introductoryPriceCurrencyCode: String

            // introductoryPriceAmountMicros
            // string (int64 format)
            // Introductory price of the subscription, not including tax. The currency is the same as priceCurrencyCode. Price is expressed in micro-units, where 1,000,000 micro-units represents one unit of the currency. For example, if the subscription price is €1.99, priceAmountMicros is 1990000.
            var introductoryPriceAmountMicros: Int64

            // introductoryPricePeriod
            // string
            // Introductory price period, specified in ISO 8601 format. Common values are (but not limited to) "P1W" (one week), "P1M" (one month), "P3M" (three months), "P6M" (six months), and "P1Y" (one year).
            var introductoryPricePeriod: String

            // introductoryPriceCycles
            // integer
            // The number of billing period to offer introductory pricing.
            var introductoryPriceCycles: Int
        }

        // countryCode
        // string
        // ISO 3166-1 alpha-2 billing country/region code of the user at the time the subscription was granted.
        var countryCode: String

        // developerPayload
        // string
        // A developer-specified string that contains supplemental information about an order.
        var developerPayload: String

        // paymentState
        // integer
        // The payment state of the subscription. Possible values are: 0. Payment pending 1. Payment received 2. Free trial 3. Pending deferred upgrade/downgrade
        // Not present for canceled, expired subscriptions.
        var paymentState: Int?

        // cancelReason
        // integer
        // The reason why a subscription was canceled or is not auto-renewing. Possible values are: 0. User canceled the subscription 1. Subscription was canceled by the system, for example because of a billing problem 2. Subscription was replaced with a new subscription 3. Subscription was canceled by the developer
        var cancelReason: Int?

        // userCancellationTimeMillis
        // string (int64 format)
        // The time at which the subscription was canceled by the user, in milliseconds since the epoch. Only present if cancelReason is 0.
        var userCancellationTimeMillis: Int64?

        // cancelSurveyResult
        // object (SubscriptionCancelSurveyResult)
        // Information provided by the user when they complete the subscription cancellation flow (cancellation reason survey).
        var cancelSurveyResult: SubscriptionCancelSurveyResult?
        // https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptions#SubscriptionCancelSurveyResult
        struct SubscriptionCancelSurveyResult: Codable {
            //cancelSurveyReason
            //integer
            // The cancellation reason the user chose in the survey. Possible values are: 0. Other 1. I don't use this service enough 2. Technical issues 3. Cost-related reasons 4. I found a better app
            var cancelSurveyReason: Int

            // userInputCancelReason
            // string
            // The customized input cancel reason from the user. Only present when cancelReason is 0.
            var userInputCancelReason: String
        }

        // orderId
        // string
        // The order id of the latest recurring order associated with the purchase of the subscription. If the subscription was canceled because payment was declined, this will be the order id from the payment declined order.
        var orderId: String

        // linkedPurchaseToken
        // string
        // The purchase token of the originating purchase if this subscription is one of the following: 0. Re-signup of a canceled but non-lapsed subscription 1. Upgrade/downgrade from a previous subscription
        // For example, suppose a user originally signs up and you receive purchase token X, then the user cancels and goes through the resignup flow (before their subscription lapses) and you receive purchase token Y, and finally the user upgrades their subscription and you receive purchase token Z. If you call this API with purchase token Z, this field will be set to Y. If you call this API with purchase token Y, this field will be set to X. If you call this API with purchase token X, this field will not be set.
        var linkedPurchaseToken: String?

        // purchaseType
        // integer
        // The type of purchase of the subscription. This field is only set if this purchase was not made using the standard in-app billing flow. Possible values are: 0. Test (i.e. purchased from a license testing account) 1. Promo (i.e. purchased using a promo code)
        var purchaseType: Int?

        // priceChange
        // object (SubscriptionPriceChange)
        // The latest price change information available. This is present only when there is an upcoming price change for the subscription yet to be applied.
        // Once the subscription renews with the new price or the subscription is canceled, no price change information will be returned.

        // profileName
        // string
        // The profile name of the user when the subscription was purchased. Only present for purchases made with 'Subscribe with Google'.
        var profileName: String?
        
        // emailAddress
        // string
        // The email address of the user when the subscription was purchased. Only present for purchases made with 'Subscribe with Google'.
        var emailAddress: String?

        // givenName
        // string
        // The given name of the user when the subscription was purchased. Only present for purchases made with 'Subscribe with Google'.
        var givenName: String?

        // familyName
        // string
        // The family name of the user when the subscription was purchased. Only present for purchases made with 'Subscribe with Google'.
        var familyName: String?

        // profileId
        // string
        // The Google profile id of the user when the subscription was purchased. Only present for purchases made with 'Subscribe with Google'.
        var profileId: String?

        // acknowledgementState
        // integer
        // The acknowledgement state of the subscription product. Possible values are: 0. Yet to be acknowledged 1. Acknowledged
        var acknowledgementState: Int

        // externalAccountId
        // string
        // User account identifier in the third-party service. Only present if account linking happened as part of the subscription purchase flow.
        var externalAccountId: String?

        // promotionType
        // integer
        // The type of promotion applied on this purchase. This field is only set if a promotion is applied when the subscription was purchased. Possible values are: 0. One time code 1. Vanity code
        var promotionType: Int?

        // promotionCode
        // string
        // The promotion code applied on this purchase. This field is only set if a vanity code promotion is applied when the subscription was purchased.
        var promotionCode: String?

        // obfuscatedExternalAccountId
        // string
        // An obfuscated version of the id that is uniquely associated with the user's account in your app. Present for the following purchases:
        //   * If account linking happened as part of the subscription purchase flow.
        //   * It was specified using https://developer.android.com/reference/com/android/billingclient/api/BillingFlowParams.Builder#setobfuscatedaccountid when the purchase was made.
        var obfuscatedExternalAccountId: String?

        // obfuscatedExternalProfileId
        // string
        // An obfuscated version of the id that is uniquely associated with the user's profile in your app. Only present if specified using https://developer.android.com/reference/com/android/billingclient/api/BillingFlowParams.Builder#setobfuscatedprofileid when the purchase was made.
        var obfuscatedExternalProfileId: String?
    }
 
    // MARK: SubscriptionPurchaseV2
    // FIXME: This is incomplete...
    // https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2#resource:-subscriptionpurchasev2
    struct SubscriptionPurchaseV2: Content {
        // kind
        // string
        // This kind represents a SubscriptionPurchaseV2 object in the androidpublisher service.
        var kind: String

        // regionCode
        // string
        // ISO 3166-1 alpha-2 billing country/region code of the user at the time the subscription was granted.
        var regionCode: String

        // latestOrderId
        // string
        // The order id of the latest order associated with the purchase of the subscription. For autoRenewing subscription, this is the order id of signup order if it is not renewed yet, or the last recurring order id (success, pending, or declined order). For prepaid subscription, this is the order id associated with the queried purchase token.
        var latestOrderId: String

        // lineItems[]
        // object (SubscriptionPurchaseLineItem)
        // Item-level info for a subscription purchase. The items in the same purchase should be either all with AutoRenewingPlan or all with PrepaidPlan.
        // https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2#subscriptionpurchaselineitem
        var lineItems: [SubscriptionPurchaseLineItem]
        struct SubscriptionPurchaseLineItem: Codable {

            var productId: String

            // A timestamp in RFC3339 UTC "Zulu" format, with nanosecond resolution and up to nine fractional digits. Examples: "2014-10-02T15:01:23Z" and "2014-10-02T15:01:23.045123456Z".
            var expiryTime: Date

            var plan_type: PlanType
            // Ugh Typescript unions are horrible in Swift
            enum PlanType: Codable {
                case autoRenewing(AutoRenewingPlan)
                case prepaid(PrepaidPlan)
                
                struct AutoRenewingPlan: Codable {
                    var autoRenewEnabled: Bool
                    var priceChangeDetails: SubscriptionItemPriceChangeDetails
                    struct SubscriptionItemPriceChangeDetails: Codable {
                        var newPrice: Money

                        var priceChangeMode: PriceChangeMode
                        enum PriceChangeMode: String, Codable {
                            case unspecified = "PRICE_CHANGE_MODE_UNSPECIFIED"
                            case decrease = "PRICE_DECREASE"
                            case increase = "PRICE_INCREASE"
                            case optOutIncrease = "OPT_OUT_PRICE_INCREASE"
                        }
                        
                        var priceChangeState: PriceChangeState
                        enum PriceChangeState: String, Codable {
                            case unspecified = "PRICE_CHANGE_STATE_UNSPECIFIED"
                            case outstanding = "OUTSTANDING"
                            case confirmed = "CONFIRMED"
                            case applied = "APPLIED"
                        }
                        
                        var expectedNewPriceChargeTime: String
                    }
                }
                
                struct PrepaidPlan: Codable {
                    // A timestamp in RFC3339 UTC "Zulu" format, with nanosecond resolution and up to nine fractional digits. Examples: "2014-10-02T15:01:23Z" and "2014-10-02T15:01:23.045123456Z".
                    var allowExtendAfterTime: String
                }
                
                enum CodingKeys: String, CodingKey {
                    case autoRenewingPlan
                    case prepaidPlan
                }
                
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    
                    if let auto = try container.decodeIfPresent(AutoRenewingPlan.self, forKey: .autoRenewingPlan) {
                        self = .autoRenewing(auto)
                        return
                    } else {
                        let prepaid = try container.decode(PrepaidPlan.self, forKey: .prepaidPlan)
                        self = .prepaid(prepaid)
                    }
                }
                
                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    
                    switch self {
                    case .autoRenewing(let auto):
                        try container.encode(auto, forKey: .autoRenewingPlan)
                    case .prepaid(let prepaid):
                        try container.encode(prepaid, forKey: .prepaidPlan)
                    }
                }
            }

        }
        
        // startTime
        // string (Timestamp format)
        // Time at which the subscription was granted. Not set for pending subscriptions (subscription was created but awaiting payment during signup).
        // A timestamp in RFC3339 UTC "Zulu" format, with nanosecond resolution and up to nine fractional digits. Examples: "2014-10-02T15:01:23Z" and "2014-10-02T15:01:23.045123456Z".
        var startTime: Date

        // subscriptionState
        // enum (SubscriptionState)
        // The current state of the subscription.
        var subscriptionState: SubscriptionState
        // https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2#subscriptionstate
        enum SubscriptionState: String, Codable {
            // Unspecified subscription state.
            case unspecified = "SUBSCRIPTION_STATE_UNSPECIFIED"

            // Subscription was created but awaiting payment during signup. In this state, all items are awaiting payment.
            case pending = "SUBSCRIPTION_STATE_PENDING"
            
            // Subscription is active. - (1) If the subscription is an auto renewing plan, at least one item is autoRenewEnabled and not expired. - (2) If the subscription is a prepaid plan, at least one item is not expired.
            case active = "SUBSCRIPTION_STATE_ACTIVE"

            // Subscription is paused. The state is only available when the subscription is an auto renewing plan. In this state, all items are in paused state.
            case paused = "SUBSCRIPTION_STATE_PAUSED"

            // Subscription is in grace period. The state is only available when the subscription is an auto renewing plan. In this state, all items are in grace period.
            case inGracePeriod = "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"

            // Subscription is on hold (suspended). The state is only available when the subscription is an auto renewing plan. In this state, all items are on hold.
            case onHold = "SUBSCRIPTION_STATE_ON_HOLD"
            
            // Subscription is canceled but not expired yet. The state is only available when the subscription is an auto renewing plan. All items have autoRenewEnabled set to false.
            case canceled = "SUBSCRIPTION_STATE_CANCELED"
            
            // Subscription is expired. All items have expiryTime in the past.
            case expired = "SUBSCRIPTION_STATE_EXPIRED"
        }
        
        // linkedPurchaseToken
        // string
        // The purchase token of the old subscription if this subscription is one of the following: * Re-signup of a canceled but non-lapsed subscription * Upgrade/downgrade from a previous subscription. * Convert from prepaid to auto renewing subscription. * Convert from an auto renewing subscription to prepaid. * Topup a prepaid subscription.
        var linkedPurchaseToken: String?

        // pausedStateContext
        // object (pausedStateContext)
        // Additional context around paused subscriptions. Only present if the subscription currently has subscriptionState SUBSCRIPTION_STATE_PAUSED.
        var pausedStateContext: PausedStateContext?
        // https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2#pausedstatecontext
        struct PausedStateContext: Codable {
            // autoResumeTime
            // string (Timestamp format)
            // Time at which the subscription will be automatically resumed.
            // A timestamp in RFC3339 UTC "Zulu" format, with nanosecond resolution and up to nine fractional digits. Examples: "2014-10-02T15:01:23Z" and "2014-10-02T15:01:23.045123456Z".
            var autoResumeTime: Date
        }

        // canceledStateContext
        // object (CanceledStateContext)
        // Additional context around canceled subscriptions. Only present if the subscription currently has subscriptionState SUBSCRIPTION_STATE_CANCELED.
        var canceledStateContext: CanceledStateContext?
        // Ugh what a mess: https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2#canceledstatecontext
        struct CanceledStateContext: Codable {
            var cancellationReason: CancellationReason
            
            enum CancellationReason: Codable {
                case userInitiated(UserInitiatedCancellation)
                case systemInitiated(SystemInitiatedCancellation)
                case developerInitiated(DeveloperInitiatedCancellation)
                case replacement(ReplacementCancellation)
            
                // https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2#UserInitiatedCancellation
                struct UserInitiatedCancellation: Codable {
                    var cancelSurveyResult: CancelSurveyResult
                    struct CancelSurveyResult: Codable {
                        var reason: CancelSurveyReason
                        enum CancelSurveyReason: String, Codable {
                            case unspecified = "CANCEL_SURVEY_REASON_UNSPECIFIED"
                            case notEnoughUSage = "CANCEL_SURVEY_REASON_NOT_ENOUGH_USAGE"
                            case technicalIssues = "CANCEL_SURVEY_REASON_TECHNICAL_ISSUES"
                            case costRelated = "CANCEL_SURVEY_REASON_COST_RELATED"
                            case foundBetterApp = "CANCEL_SURVEY_REASON_FOUND_BETTER_APP"
                            case others = "CANCEL_SURVEY_REASON_OTHERS"
                        }
                        var reasonUserInput: String
                    }
                    var cancelTime: String
                }
                
                struct SystemInitiatedCancellation: Codable {
                    // Empty
                }
                
                struct DeveloperInitiatedCancellation: Codable {
                    // Empty
                }
                
                struct ReplacementCancellation: Codable {
                    // Empty
                }
                
                enum CodingKeys: String, CodingKey {
                    case userInitiatedCancellation
                    case systemInitiatedCancellation
                    case developerInitiatedCancellation
                    case replacementCancellation
                }
                
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    
                    if let user = try container.decodeIfPresent(UserInitiatedCancellation.self, forKey: .userInitiatedCancellation) {
                        self = .userInitiated(user)
                        return
                    }
                    
                    if let system = try container.decodeIfPresent(SystemInitiatedCancellation.self, forKey: .systemInitiatedCancellation) {
                        self = .systemInitiated(system)
                        return
                    }
                    
                    if let developer = try container.decodeIfPresent(DeveloperInitiatedCancellation.self, forKey: .developerInitiatedCancellation) {
                        self = .developerInitiated(developer)
                        return
                    }
                    
                    if let replacement = try container.decodeIfPresent(ReplacementCancellation.self, forKey: .replacementCancellation) {
                        self = .replacement(replacement)
                        return
                    }
                    
                    throw MatrixError(status: .internalServerError, errcode: .unknown, error: "Error parsing cancellation reason")
                }
                
                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    
                    switch self {
                    case .userInitiated(let user):
                        try container.encode(user, forKey: .userInitiatedCancellation)
                        return
                    case .systemInitiated(let system):
                        try container.encode(system, forKey: .systemInitiatedCancellation)
                        return
                    case .developerInitiated(let developer):
                        try container.encode(developer, forKey: .developerInitiatedCancellation)
                        return
                    case .replacement(let replacement):
                        try container.encode(replacement, forKey: .replacementCancellation)
                        return
                    }
                }
                
            }
            
        }
        
        // testPurchase
        // object (TestPurchase)
        // Only present if this subscription purchase is a test purchase.
        var testPurchase: TestPurchase?
        struct TestPurchase: Codable {
            // Empty - https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2#testpurchase
        }

        // acknowledgementState
        //enum (AcknowledgementState)
        // The acknowledgement state of the subscription.
        var acknowledgementState: AcknowledgementState
        enum AcknowledgementState: String, Codable {
            case unspecified = "ACKNOWLEDGEMENT_STATE_UNSPECIFIED"    // Unspecified acknowledgement state.
            case pending = "ACKNOWLEDGEMENT_STATE_PENDING"            // The subscription is not acknowledged yet.
            case acknowledged = "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED"  // The subscription is acknowledged.
        }

        // externalAccountIdentifiers
        // object (ExternalAccountIdentifiers)
        // User account identifier in the third-party service.
        // https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2#externalaccountidentifiers
        var externalAccountIdentifiers: ExternalAccountIdentifiers
        struct ExternalAccountIdentifiers: Codable {
            // Only present if account linking happened as part of the subscription purchase flow.
            var externalAccountId: String?
            
            // Present for the following purchases:
            //   * If account linking happened as part of the subscription purchase flow.
            //   * It was specified using https://developer.android.com/reference/com/android/billingclient/api/BillingFlowParams.Builder#setobfuscatedaccountid when the purchase was made.
            var obfuscatedExternalAccountId: String?
            
            // Only present if specified using https://developer.android.com/reference/com/android/billingclient/api/BillingFlowParams.Builder#setobfuscatedprofileid when the purchase was made.
            var obfuscatedExternalProfileId: String?
        }

        // subscribeWithGoogleInfo
        // object (SubscribeWithGoogleInfo)
        // User profile associated with purchases made with 'Subscribe with Google'.
        // https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2#subscribewithgoogleinfo
        var subscribeWithGoogleInfo: SubscribeWithGoogleInfo
        struct SubscribeWithGoogleInfo: Codable {
            var profileId: String
            var profileName: String
            var emailAddress: String
            var givenName: String
            var familyName: String
        }
    }
    
}
