//
//  AppStore+Response.swift
//   * Based on https://github.com/slashmo/swift-app-store-receipt-validation
//   * Original author: Moritz Lang
//   * License: Apache 2.0
//  Created by Charles Wright on 4/21/22.
//

import Vapor

extension AppStore {
    struct Status: Codable {
        let status: Int
    }

    public struct Response: Content {
        let receipt: Receipt // json
        let latestReceipt: String?
        let latestReceiptInfo: Receipt? // json
//    let latestExpiredReceiptInfo: Any? // json
//    let pendingRenewalInfo: Any?
        let isRetryable: Bool?
        let environment: Environment

        enum CodingKeys: String, CodingKey {
            case receipt
            case latestReceipt = "latest_receipt"
            case latestReceiptInfo = "latest_receipt_info"
            case isRetryable = "is-retryable"
            case environment
        }
    }
}
