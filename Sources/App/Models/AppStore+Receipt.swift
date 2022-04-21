//
//  AppStore+Receipt.swift
//   * Based on https://github.com/slashmo/swift-app-store-receipt-validation
//   * Original author: Moritz Lang
//   * License: Apache 2.0
//  Created by Charles Wright on 4/21/22.
//

import Vapor

extension AppStore {
    public struct Receipt: Content {
        public let bundleId: String
        public let applicationVersion: String
        public let inApp: [InAppPurchase]
        public let originalApplicationVersion: String
        public let receiptCreationDate: Date
        public let receiptExpirationDate: Date?

        enum CodingKeys: String, CodingKey {
            case bundleId = "bundle_id"
            case applicationVersion = "application_version"
            case inApp = "in_app"
            case originalApplicationVersion = "original_application_version"
            case receiptCreationDate = "receipt_creation_date_ms"
            case receiptExpirationDate = "receipt_expiration_date_ms"
        }
    }
}

public extension AppStore.Receipt {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.bundleId = try container.decode(String.self, forKey: .bundleId)
        self.applicationVersion = try container.decode(String.self, forKey: .applicationVersion)
        self.inApp = try container.decode([AppStore.InAppPurchase].self, forKey: .inApp)
        self.originalApplicationVersion = try container.decode(String.self, forKey: .originalApplicationVersion)
        self.receiptCreationDate = try container.decodeAppStoreDate(forKey: .receiptCreationDate)
        self.receiptExpirationDate = try container.decodeAppStoreDateIfPresent(forKey: .receiptExpirationDate)
    }
}
