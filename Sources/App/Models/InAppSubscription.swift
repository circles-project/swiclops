//
//  Subscription.swift
//
//
//  Created by Charles Wright on 3/30/21.
//
import Fluent
import Vapor

final class InAppSubscription: Model {
    static let schema = "in_app_subscriptions"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "user_id")
    var userId: String
    
    @Field(key: "provider")
    var provider: String
    
    @Field(key: "product_id")
    var productId: String
    
    @Field(key: "transaction_id")
    var transactionId: String
    
    @Field(key: "original_transaction_id")
    var originalTransactionId: String
    
    @Field(key: "bundle_id")
    var bundleId: String
    
    @Field(key: "start_date")
    var startDate: Date
    
    @OptionalField(key: "end_date")
    var endDate: Date?
    
    @Field(key: "family_shared")
    var familyShared: Bool
    
    init() {}
    
    init(id: UUID? = nil,
         userId: String,
         provider: String,
         productId: String,
         transactionId: String,
         originalTransactionId: String,
         bundleId: String,
         startDate: Date,
         endDate: Date?,
         familyShared: Bool
    ) {
        self.id = id
        self.userId = userId
        self.provider = provider
        self.productId = productId
        self.transactionId = transactionId
        self.originalTransactionId = originalTransactionId
        self.bundleId = bundleId
        self.startDate = startDate
        self.endDate = endDate
        self.familyShared = familyShared
    }
}
