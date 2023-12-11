//
//  AppStore.swift
//   * Based on https://github.com/slashmo/swift-app-store-receipt-validation
//   * Original author: Moritz Lang
//   * License: Apache 2.0
//  Created by Charles Wright on 4/21/22.
//

import Vapor

import AppStoreServerLibrary

public enum AppStore {
    public typealias Environment = AppStoreServerLibrary.Environment
    
    public enum Error: Swift.Error {
        /// The App Store could not read the JSON object you provided.
        case invalidJSONObject

        /// The data in the receipt-data property was malformed or missing.
        case receiptDataMalformedOrMissing

        /// The receipt could not be authenticated.
        case receiptCouldNotBeAuthenticated

        /// The shared secret you provided does not match the shared secret on file for your account.
        case sharedSecretDoesNotMatchTheSharedSecretOnFileForAccount

        /// The receipt server is not currently available.
        case receiptServerIsCurrentlyUnavailable

        /// This receipt is valid but the subscription has expired. When this status code is returned to your server, the receipt data
        /// is also decoded and returned as part of the response.
        /// _Only returned for iOS 6 style transaction receipts for auto-renewable subscriptions._
        case receiptIsValidButSubscriptionHasExpired

        /// This receipt is from the test environment, but it was sent to the production environment for verification.
        /// Send it to the test environment instead.
        case receiptIsFromTestEnvironmentButWasSentToProductionEnvironment

        /// This receipt is from the production environment, but it was sent to the test environment for verification.
        /// Send it to the production environment instead.
        case receiptIsFromProductionEnvironmentButWasSentToTestEnvironment

        /// This receipt could not be authorized. Treat this the same as if a purchase was never made.
        case receiptCouldNotBeAuthorized

        /// Internal data access error.
        case internalDataAccessError

        /// Catch all error introduced by this library to handle unknown status codes
        case unknownError

        init(statusCode: Int) {
            switch statusCode {
            case 21000:
                self = .invalidJSONObject
            case 21002:
                self = .receiptDataMalformedOrMissing
            case 21003:
                self = .receiptCouldNotBeAuthenticated
            case 21004:
                self = .sharedSecretDoesNotMatchTheSharedSecretOnFileForAccount
            case 21005:
                self = .receiptServerIsCurrentlyUnavailable
            case 21006:
                self = .receiptIsValidButSubscriptionHasExpired
            case 21007:
                self = .receiptIsFromTestEnvironmentButWasSentToProductionEnvironment
            case 21008:
                self = .receiptIsFromProductionEnvironmentButWasSentToTestEnvironment
            case 21010:
                self = .receiptCouldNotBeAuthorized
            case 21100 ... 21199:
                self = .internalDataAccessError
            default:
                self = .unknownError
            }
        }
    }
    



}




extension KeyedDecodingContainer {
    func decodeAppStoreDate(forKey key: K) throws -> Date {
        let string = try self.decode(String.self, forKey: key)

        guard let timeIntervalSince1970inMs = Double(string) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected to have a TimeInterval in ms within the string to decode a date."
            )
        }

        return Date(timeIntervalSince1970: timeIntervalSince1970inMs / 1000)
    }

    func decodeAppStoreDateIfPresent(forKey key: K) throws -> Date? {
        guard let string = try self.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        guard let timeIntervalSince1970inMs = Double(string) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected to have a TimeInterval in ms within the string to decode a date."
            )
        }

        return Date(timeIntervalSince1970: timeIntervalSince1970inMs / 1000)
    }
}

