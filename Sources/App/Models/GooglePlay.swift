//
//  GooglePlay.swift
//  
//
//  Created by Charles Wright on 10/12/22.
//

import Vapor

enum GooglePlay {
    
    struct TransactionData: Content {
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

        // emailAddress
        // string
        // The email address of the user when the subscription was purchased. Only present for purchases made with 'Subscribe with Google'.

        // givenName
        // string
        // The given name of the user when the subscription was purchased. Only present for purchases made with 'Subscribe with Google'.

        // familyName
        // string
        // The family name of the user when the subscription was purchased. Only present for purchases made with 'Subscribe with Google'.

        // profileId
        // string
        // The Google profile id of the user when the subscription was purchased. Only present for purchases made with 'Subscribe with Google'.

        // acknowledgementState
        // integer
        // The acknowledgement state of the subscription product. Possible values are: 0. Yet to be acknowledged 1. Acknowledged
        var acknowledgementState: Int

        // externalAccountId
        // string
        // User account identifier in the third-party service. Only present if account linking happened as part of the subscription purchase flow.

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
        // An obfuscated version of the id that is uniquely associated with the user's account in your app. Present for the following purchases: * If account linking happened as part of the subscription purchase flow. * It was specified using https://developer.android.com/reference/com/android/billingclient/api/BillingFlowParams.Builder#setobfuscatedaccountid when the purchase was made.

        // obfuscatedExternalProfileId
        // string
        // An obfuscated version of the id that is uniquely associated with the user's profile in your app. Only present if specified using https://developer.android.com/reference/com/android/billingclient/api/BillingFlowParams.Builder#setobfuscatedprofileid when the purchase was made.
    }
    
}
