//
//  AppStore+Request.swift
//   * Based on https://github.com/slashmo/swift-app-store-receipt-validation
//   * Original author: Moritz Lang
//   * License: Apache 2.0
//
//  Created by Charles Wright on 4/21/22.
//

import Vapor

extension AppStore {
    public struct Request: Content {
        let receiptData: String
        let password: String?
        let excludeOldTransactions: Bool?

        enum CodingKeys: String, CodingKey {
            case receiptData = "receipt-data"
            case password
            case excludeOldTransactions = "exclude-old-transactions"
        }
    }
}
