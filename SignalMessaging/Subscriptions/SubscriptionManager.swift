//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import PassKit
import ZKGroup

public class SubscriptionLevel: Comparable {
    public let level: UInt
    public let name: String
    public let badge: ProfileBadge
    public let currency: [String: NSDecimalNumber]

    public init(level: UInt, jsonDictionary: [String: Any]) throws {
        self.level = level
        let params = ParamParser(dictionary: jsonDictionary)
        name = try params.required(key: "name")
        let badgeDict: [String: Any] = try params.required(key: "badge")
        badge = try ProfileBadge(jsonDictionary: badgeDict)
        let currencyDict: [String: Any] = try params.required(key: "currencies")
        currency = currencyDict.compactMapValues {
            guard let int64Currency = $0 as? Int64 else {
                owsFailDebug("Failed to convert currency value")
                return nil
            }
            return NSDecimalNumber(value: int64Currency)
        }
    }

    // MARK: Comparable

    public static func < (lhs: SubscriptionLevel, rhs: SubscriptionLevel) -> Bool {
        return lhs.level < rhs.level
    }

    public static func == (lhs: SubscriptionLevel, rhs: SubscriptionLevel) -> Bool {
        return lhs.level == rhs.level
    }
}

public struct Subscription {
    public let level: UInt
    public let currency: String
    public let amount: NSDecimalNumber
    public let endOfCurrentPeriod: TimeInterval
    public let billingCycleAnchor: TimeInterval
    public let active: Bool
    public let cancelAtEndOfPeriod: Bool

    public init(jsonDictionary: [String: Any]) throws {
        let params = ParamParser(dictionary: jsonDictionary)
        level = try params.required(key: "level")
        currency = try params.required(key: "currency")
        let amountValue: Int64 = try params.required(key: "amount")
        amount = NSDecimalNumber(value: amountValue)
        endOfCurrentPeriod = try params.required(key: "endOfCurrentPeriod")
        billingCycleAnchor = try params.required(key: "billingCycleAnchor")
        active = try params.required(key: "active")
        cancelAtEndOfPeriod = try params.required(key: "cancelAtPeriodEnd")

    }
}

@objc
public class SubscriptionManager: NSObject {

    public static let subscriptionJobQueue = SubscriptionReceiptCredentialJobQueue()
    public static let SubscriptionJobQueueDidFinishJobNotification = NSNotification.Name("SubscriptionJobQueueDidFinishJobNotification")
    public static let SubscriptionJobQueueDidFailJobNotification = NSNotification.Name("SubscriptionJobQueueDidFailJobNotification")
    private static let subscriptionKVS = SDSKeyValueStore(collection: "SubscriptionKeyValueStore")
    private static let subscriberIDKey = "subscriberID"
    private static let subscriberCurrencyCodeKey = "subscriberCurrencyCode"
    private static let lastSubscriptionExpirationKey = "subscriptionExpiration"
    private static let lastSubscriptionHeartbeatKey = "subscriptionHeartbeat"
    private static let lastSubscriptionReceiptRedemptionFailedKey = "lastSubscriptionReceiptRedemptionFailedKey"

    public static var terminateTransactionIfPossible = false

    // MARK: Subscription levels

    public class func getSubscriptions() -> Promise<[SubscriptionLevel]> {
        let request = OWSRequestFactory.subscriptionLevelsRequest()

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in

            guard let json = response.responseBodyJson as? [String: Any] else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }

            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            do {
                let subscriptionDicts: [String: Any] = try parser.required(key: "levels")
                let subscriptions: [SubscriptionLevel] = try subscriptionDicts.compactMap { (subscriptionKey: String, value: Any) in
                    guard let subscriptionDict = value as? [String: Any] else {
                        return nil
                    }

                    guard let level = UInt(subscriptionKey) else {
                        throw OWSAssertionError("Unable to determine subscription level")
                    }

                    return try SubscriptionLevel(level: level, jsonDictionary: subscriptionDict)
                }
                return subscriptions.sorted()
            } catch {
                owsFailDebug("Unable to parse subscription levels, \(error)")
            }

            return []
        }
    }

    // MARK: Current subscription status

    public class func getCurrentSubscriptionStatus(for subscriberID: Data) -> Promise<Subscription?> {
        let subscriberIDString = subscriberID.asBase64Url
        let request = OWSRequestFactory.subscriptionGetCurrentSubscriptionLevelRequest(subscriberIDString)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode

            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }

            if let json = response.responseBodyJson as? [String: Any] {
                guard let parser = ParamParser(responseObject: json) else {
                    throw OWSAssertionError("Missing or invalid response.")
                }

                guard let subscriptionDict: [String: Any] = try parser.optional(key: "subscription") else {
                    return nil
                }

                return try Subscription(jsonDictionary: subscriptionDict)
            } else {
                return nil
            }
        }
    }

    // MARK: Subscription management

    public static func getSubscriberID(transaction: SDSAnyReadTransaction) -> Data? {
        guard let subscriberID = subscriptionKVS.getObject(
            forKey: subscriberIDKey,
            transaction: transaction
        ) as? Data else {
            return nil
        }
        return subscriberID
    }

    public static func setSubscriberID(_ subscriberID: Data?, transaction: SDSAnyWriteTransaction) {
        subscriptionKVS.setObject(subscriberID,
                                  key: subscriberIDKey,
                                  transaction: transaction)
    }

    public static func getSubscriberCurrencyCode(transaction: SDSAnyReadTransaction) -> String? {
        guard let subscriberCurrencyCode = subscriptionKVS.getObject(
            forKey: subscriberCurrencyCodeKey,
            transaction: transaction
        ) as? String else {
            return nil
        }
        return subscriberCurrencyCode
    }

    public static func setSubscriberCurrencyCode(_ currencyCode: String?, transaction: SDSAnyWriteTransaction) {
        subscriptionKVS.setObject(currencyCode,
                                  key: subscriberCurrencyCodeKey,
                                  transaction: transaction)
    }

    public static func setLastReceiptRedemptionFailed(failed: Bool, transaction: SDSAnyWriteTransaction) {
        subscriptionKVS.setBool(failed, key: lastSubscriptionReceiptRedemptionFailedKey, transaction: transaction)
    }

    public static func lastReceiptRedemptionFailed(transaction: SDSAnyReadTransaction) -> Bool {
        return subscriptionKVS.getBool(lastSubscriptionReceiptRedemptionFailedKey, transaction: transaction) ?? false
    }

    private class func setupNewSubscriberID() throws -> Promise<Data> {
        Logger.info("[Subscriptions] Setting up new subscriber ID")
        let newSubscriberID = generateSubscriberID()
        return firstly {
            try self.postSubscriberID(subscriberID: newSubscriberID)
        }.map(on: .global()) { _ in
            return newSubscriberID
        }
    }

    private class func postSubscriberID(subscriberID: Data) throws -> Promise<Void> {
        let request = OWSRequestFactory.setSubscriptionIDRequest(subscriberID.asBase64Url)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode

            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
        }
    }

    private class func generateSubscriberID() -> Data {
        return Cryptography.generateRandomBytes(UInt(32))
    }

    public class func setupNewSubscription(subscription: SubscriptionLevel, payment: PKPayment, currencyCode: String) throws -> Promise<Void> {
        Logger.info("[Subscriptions] Setting up new subscription")

        var generatedSubscriberID = Data()
        var generatedClientSecret = ""
        var generatedPaymentID = ""

        return firstly {
            return try setupNewSubscriberID()

        // Create Stripe SetupIntent against new subscriberID
        }.then(on: .sharedUserInitiated) { subscriberID -> Promise<String> in
            guard !self.terminateTransactionIfPossible else {
                throw OWSGenericError("Transaction chain cancelled")
            }

            generatedSubscriberID = subscriberID

            SDSDatabaseStorage.shared.write { transaction in
                self.setSubscriberID(subscriberID, transaction: transaction)
                self.setSubscriberCurrencyCode(currencyCode, transaction: transaction)
                self.storageServiceManager.recordPendingLocalAccountUpdates()
            }

            return try createPaymentMethod(for: subscriberID)

        // Create new payment method
        }.then(on: .sharedUserInitiated) { clientSecret -> Promise<String> in
            guard !self.terminateTransactionIfPossible else {
                throw OWSGenericError("Transaction chain cancelled")
            }

            generatedClientSecret = clientSecret
            return Stripe.createPaymentMethod(with: payment)

        // Bind payment method to SetupIntent, confirm SetupIntent
        }.then(on: .sharedUserInitiated) { paymentID -> Promise<HTTPResponse> in
            guard !self.terminateTransactionIfPossible else {
                throw OWSGenericError("Transaction chain cancelled")
            }

            generatedPaymentID = paymentID
            return try Stripe.confirmSetupIntent(for: generatedPaymentID, clientSecret: generatedClientSecret, payment: payment)

        // Update payment on server
        }.then(on: .sharedUserInitiated) { _ -> Promise<Void> in
            guard !self.terminateTransactionIfPossible else {
                throw OWSGenericError("Transaction chain cancelled")
            }

            return try setDefaultPaymentMethod(for: generatedSubscriberID, paymentID: generatedPaymentID)

        // Select subscription level
        }.then(on: .sharedUserInitiated) { _ -> Promise<Void> in
            guard !self.terminateTransactionIfPossible else {
                throw OWSGenericError("Transaction chain cancelled")
            }

            return setSubscription(for: generatedSubscriberID, subscription: subscription, currency: currencyCode)

        // Report success and dismiss sheet
        }
    }

    public class func updateSubscriptionLevel(for subscriberID: Data,
                                              from priorSubscription: SubscriptionLevel,
                                              to subscription: SubscriptionLevel,
                                              payment: PKPayment,
                                              currencyCode: String) throws -> Promise<Void> {
        Logger.info("[Subscriptions] Updating subscription level")

        var generatedClientSecret = ""
        var generatedPaymentID = ""
        return firstly {
            try createPaymentMethod(for: subscriberID)
            // Create new payment method
        }.then(on: .sharedUserInitiated) { clientSecret -> Promise<String> in
            guard !self.terminateTransactionIfPossible else {
                throw OWSGenericError("Transaction chain cancelled")
            }

            generatedClientSecret = clientSecret
            return Stripe.createPaymentMethod(with: payment)

            // Bind payment method to SetupIntent, confirm SetupIntent
        }.then(on: .sharedUserInitiated) { paymentID -> Promise<HTTPResponse> in
            guard !self.terminateTransactionIfPossible else {
                throw OWSGenericError("Transaction chain cancelled")
            }

            generatedPaymentID = paymentID
            return try Stripe.confirmSetupIntent(for: generatedPaymentID, clientSecret: generatedClientSecret, payment: payment)

            // Update payment on server
        }.then(on: .sharedUserInitiated) { _ -> Promise<Void> in
            guard !self.terminateTransactionIfPossible else {
                throw OWSGenericError("Transaction chain cancelled")
            }

            return try setDefaultPaymentMethod(for: subscriberID, paymentID: generatedPaymentID)

            // Select subscription level
        }.then(on: .sharedUserInitiated) { _ -> Promise<Void> in
            guard !self.terminateTransactionIfPossible else {
                throw OWSGenericError("Transaction chain cancelled")
            }

            return setSubscription(for: subscriberID, subscription: subscription, currency: currencyCode)
            // Report success and dismiss sheet
        }

    }

    public class func cancelSubscription(for subscriberID: Data) throws -> Promise<Void> {

        let request = OWSRequestFactory.deleteSubscriptionIDRequest(subscriberID.asBase64Url)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            } else {
                SDSDatabaseStorage.shared.write { transaction in
                    self.setSubscriberID(nil, transaction: transaction)
                    self.setSubscriberCurrencyCode(nil, transaction: transaction)
                    self.storageServiceManager.recordPendingLocalAccountUpdates()
                }
            }
        }
    }

    private class func createPaymentMethod(for subscriberID: Data) throws -> Promise<String> {
        let request = OWSRequestFactory.subscriptionCreatePaymentMethodRequest(subscriberID.asBase64Url)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode

            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }

            guard let json = response.responseBodyJson as? [String: Any] else {
                throw OWSAssertionError("Unable to parse response body.")
            }

            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            do {
                let clientSecret: String = try parser.required(key: "clientSecret")
                return clientSecret
            } catch {
                throw OWSAssertionError("Missing clientID key")
            }
        }
    }

    private class func setDefaultPaymentMethod(for subscriberID: Data, paymentID: String) throws -> Promise<Void> {
        let request = OWSRequestFactory.subscriptionSetDefaultPaymentMethodRequest(subscriberID.asBase64Url, paymentID: paymentID)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
        }
    }

    private class func setSubscription(for subscriberID: Data,
                                       subscription: SubscriptionLevel,
                                       currency: String) -> Promise<Void> {

        let subscriberID = subscriberID.asBase64Url
        let key = Cryptography.generateRandomBytes(UInt(32)).asBase64Url
        let level = String(subscription.level)
        let request = OWSRequestFactory.subscriptionSetSubscriptionLevelRequest(subscriberID, level: level, currency: currency, idempotencyKey: key)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
        }
    }

    public class func requestAndRedeemRecieptsIfNecessary(for subscriberID: Data,
                                                          subscriptionLevel: UInt,
                                                          priorSubscriptionLevel: UInt = 0) throws {
        let request = try generateRecieptRequest()

        // Remove prior operations if one exists (allow prior job to complete)
        for redemptionJob in subscriptionJobQueue.runningOperations.get() {
            if !redemptionJob.isBoost {
                redemptionJob.reportError(OWSAssertionError("Job did not complete before next subscription run"))
            }
        }

        // Reset failure state
        SDSDatabaseStorage.shared.write { transaction in
            self.setLastReceiptRedemptionFailed(failed: false, transaction: transaction)
        }

        SDSDatabaseStorage.shared.asyncWrite { transaction in

            self.subscriptionJobQueue.add(isBoost: false,
                                          receiptCredentialRequestContext: request.context.serialize().asData,
                                          receiptCredentailRequest: request.request.serialize().asData,
                                          subscriberID: subscriberID,
                                          targetSubscriptionLevel: subscriptionLevel,
                                          priorSubscriptionLevel: priorSubscriptionLevel,
                                          boostPaymentIntentID: String(),
                                          transaction: transaction)
        }
    }

    public class func generateRecieptRequest() throws -> (context: ReceiptCredentialRequestContext, request: ReceiptCredentialRequest) {
        let clientOperations = try clientZKReceiptOperations()
        let receiptSerial = try generateReceiptSerial()

        let receiptCredentialRequestContext = try clientOperations.createReceiptCredentialRequestContext(receiptSerial: receiptSerial)
        let receiptCredentialRequest = try receiptCredentialRequestContext.getRequest()
        return (receiptCredentialRequestContext, receiptCredentialRequest)
    }

    public class func requestReceiptCredentialPresentation(for subscriberID: Data,
                                                           context: ReceiptCredentialRequestContext,
                                                           request: ReceiptCredentialRequest,
                                                           targetSubscriptionLevel: UInt,
                                                           priorSubscriptionLevel: UInt = 0) throws -> Promise<ReceiptCredentialPresentation> {
        let clientOperations = try clientZKReceiptOperations()
        let encodedReceiptCredentialRequest = request.serialize().asData.base64EncodedString()
        let request = OWSRequestFactory.subscriptionRecieptCredentialsRequest(subscriberID.asBase64Url, request: encodedReceiptCredentialRequest)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode

            if statusCode == 200 {
                Logger.debug("Got valid receipt response")
            } else if statusCode == 204 {
                Logger.debug("User has no active subscriptions")
            } else if statusCode == 400 || statusCode == 403 || statusCode == 404 || statusCode ==  409 {
                throw OWSAssertionError("Receipt redemption failed with unrecoverable code")
            } else {
                throw OWSRetryableSubscriptionError()
            }

            guard let json = response.responseBodyJson as? [String: Any] else {
                throw OWSAssertionError("Unable to parse response body.")
            }

            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            let receiptCredentialResponseString: String = try parser.required(key: "receiptCredentialResponse")
            guard let receiptCredentialResponseData = Data(base64Encoded: receiptCredentialResponseString) else {
                throw OWSAssertionError("Unable to parse receiptCredentialResponse into data.")
            }

            let receiptCredentialResponse = try ReceiptCredentialResponse(contents: [UInt8](receiptCredentialResponseData))
            let receiptCredential = try clientOperations.receiveReceiptCredential(receiptCredentialRequestContext: context, receiptCredentialResponse: receiptCredentialResponse)

            // Validate that receipt credential level matches requested level, or prior subscription level
            let level = try receiptCredential.getReceiptLevel()
            var receiptCredentialHasValidLevel = (level == targetSubscriptionLevel)

            if !receiptCredentialHasValidLevel && priorSubscriptionLevel != 0 {
                receiptCredentialHasValidLevel = (level == priorSubscriptionLevel)
            }

            guard receiptCredentialHasValidLevel else {
                throw OWSAssertionError("Unexpected receipt credential level")
            }

            // Validate receipt credential expiration % 86400 == 0, per server spec
            let expiration = try receiptCredential.getReceiptExpirationTime()
            guard expiration % 86400 == 0 else {
                throw OWSAssertionError("Invalid receipt credential expiration, expiration mod != 0")
            }

            // Validate expiration is less than 60 days from now
            let maximumValidExpirationDate = Date().timeIntervalSince1970 + (60 * 24 * 60 * 60)
            guard TimeInterval(expiration) < maximumValidExpirationDate else {
                throw OWSAssertionError("Invalid receipt credential expiration, expiration is more than 60 days from now")
            }

            let receiptCredentialPresentation = try clientOperations.createReceiptCredentialPresentation(receiptCredential: receiptCredential)

            return receiptCredentialPresentation
        }
    }

    public class func redeemReceiptCredentialPresentation(receiptCredentialPresentation: ReceiptCredentialPresentation, makePrimary: Bool = false) throws -> Promise<Void> {
        let receiptCredentialPresentationData = receiptCredentialPresentation.serialize().asData

        let receiptCredentialPresentationString = receiptCredentialPresentationData.base64EncodedString()
        let request = OWSRequestFactory.subscriptionRedeemRecieptCredential(
            receiptCredentialPresentationString,
            makePrimary: makePrimary
        )
        return firstly(on: .global()) {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSRetryableSubscriptionError()
            }
        }.then(on: .global()) {
            self.profileManagerImpl.fetchLocalUsersProfilePromise().asVoid()
        }
    }

    private class func generateReceiptSerial() throws -> ReceiptSerial {
        let count = ReceiptSerial.SIZE
        let bytes = Cryptography.generateRandomBytes(UInt(count))
        return try ReceiptSerial(contents: [UInt8](bytes))
    }

    private class func clientZKReceiptOperations() throws -> ClientZkReceiptOperations {
        let params = try GroupsV2Protos.serverPublicParams()
        return ClientZkReceiptOperations(serverPublicParams: params)
    }

    // 3 day heartbeat interval
    private static let heartbeatInterval: TimeInterval = 3 * 24 * 60 * 60

    // MARK: Heartbeat
    @objc
    public class func performSubscriptionKeepAliveIfNecessary() {

        guard tsAccountManager.isPrimaryDevice else {
            Logger.info("[Subscriptions] Bailing out of heartbeat, this is not the primary device")
            return
        }

        // Kick job queue
        subscriptionJobQueue.runAnyQueuedRetry()

        Logger.info("[Subscriptions] Checking for subscription heartbeat")

        // Fetch subscriberID / subscriber currencyCode
        var lastKeepAliveHeartbeat: Date?
        var lastSubscriptionExpiration: Date?
        var subscriberID: Data?
        var currencyCode: String?
        SDSDatabaseStorage.shared.read { transaction in
            lastKeepAliveHeartbeat = self.subscriptionKVS.getDate(self.lastSubscriptionHeartbeatKey, transaction: transaction)
            lastSubscriptionExpiration = self.subscriptionKVS.getDate(self.lastSubscriptionExpirationKey, transaction: transaction)
            subscriberID = self.getSubscriberID(transaction: transaction)
            currencyCode = self.getSubscriberCurrencyCode(transaction: transaction)
        }

        var performHeartbeat: Bool = true
        if let lastKeepAliveHeartbeat = lastKeepAliveHeartbeat, Date().timeIntervalSince(lastKeepAliveHeartbeat) < heartbeatInterval {
            performHeartbeat = false
        }

        guard performHeartbeat else {
            Logger.info("[Subscriptions] Not performing subscription heartbeat, last heartbeat within allowed interval")
            return
        }

        Logger.debug("Performing subscription heartbeat")

        guard let subscriberID = subscriberID, currencyCode != nil else {
            Logger.info("[Subscriptions] No subscription + currency code found")
            self.updateSubscriptionHeartbeatDate()
            return
        }

        firstly(on: .sharedBackground) {
            // Post subscriberID, if it exists
            try self.postSubscriberID(subscriberID: subscriberID)
        }.then(on: .sharedBackground) {
            // Fetch current subscription
            self.getCurrentSubscriptionStatus(for: subscriberID)
        }.done(on: .sharedBackground) { subscription in
            guard let subscription = subscription else {
                Logger.info("[Subscriptions] No current subscription for this subscriberID")
                self.updateSubscriptionHeartbeatDate()
                return
            }

            if let lastSubscriptionExpiration = lastSubscriptionExpiration, lastSubscriptionExpiration.timeIntervalSince1970 < subscription.endOfCurrentPeriod {
                // Re-kick
                Logger.info("[Subscriptions] Triggering receipt redemption job during heartbeat")
                try self.requestAndRedeemRecieptsIfNecessary(for: subscriberID, subscriptionLevel: subscription.level)
            }

            // Save last expiration
            SDSDatabaseStorage.shared.write { transaction in
                self.subscriptionKVS.setDate(Date(timeIntervalSince1970: subscription.endOfCurrentPeriod),
                                                                          key: self.lastSubscriptionExpirationKey,
                                                                          transaction: transaction)
            }

            // Save heartbeat
            self.updateSubscriptionHeartbeatDate()

        }.catch(on: .sharedBackground) { error in
            owsFailDebug("Failed subscription heartbeat with error \(error)")
        }
    }

    private static func updateSubscriptionHeartbeatDate() {
        SDSDatabaseStorage.shared.write { transaction in
            // Update keepalive
            self.subscriptionKVS.setDate(Date(), key: self.lastSubscriptionHeartbeatKey, transaction: transaction)
        }
    }
}

@objc
public class OWSRetryableSubscriptionError: NSObject, CustomNSError, IsRetryableProvider {
    @objc
    public static var asNSError: NSError {
        OWSRetryableSubscriptionError() as Error as NSError
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { true }
}

extension SubscriptionManager {
    public class func createAndRedeemBoostReceipt(for intentId: String) throws {
        let request = try generateRecieptRequest()

        // Remove prior operations if one exists (allow prior job to complete)
        for redemptionJob in subscriptionJobQueue.runningOperations.get() {
            if redemptionJob.isBoost {
                redemptionJob.reportError(OWSAssertionError("Job did not complete before next subscription run"))
            }
        }

        SDSDatabaseStorage.shared.asyncWrite { transaction in

            self.subscriptionJobQueue.add(isBoost: true,
                                          receiptCredentialRequestContext: request.context.serialize().asData,
                                          receiptCredentailRequest: request.request.serialize().asData,
                                          subscriberID: Data(),
                                          targetSubscriptionLevel: 0,
                                          priorSubscriptionLevel: 0,
                                          boostPaymentIntentID: intentId,
                                          transaction: transaction)
        }
    }

    public class func getSuggestedBoostAmounts() -> Promise<[Currency.Code: DonationUtilities.Presets.Preset]> {
        firstly {
            networkManager.makePromise(request: OWSRequestFactory.boostSuggestedAmountsRequest())
        }.map { response in
            guard response.responseStatusCode == 200 else {
                throw OWSAssertionError("Got bad response code \(response.responseStatusCode).")
            }

            guard let amounts = response.responseBodyJson as? [String: [UInt]] else {
                throw OWSAssertionError("Got unexpected response JSON for boost amounts")
            }

            var presets = [Currency.Code: DonationUtilities.Presets.Preset]()
            for (key, values) in amounts {
                presets[key] = .init(
                    symbol: DonationUtilities.Presets.presets[key]?.symbol ?? .currencyCode,
                    amounts: values
                )
            }
            return presets
        }
    }

    public static func requestBoostReceiptCredentialPresentation(for intentId: String, context: ReceiptCredentialRequestContext, request: ReceiptCredentialRequest) throws -> Promise<ReceiptCredentialPresentation> {

        let clientOperations = try clientZKReceiptOperations()
        let receiptCredentialRequest = request.serialize().asData.base64EncodedString()

        let request = OWSRequestFactory.boostRecieptCredentials(withPaymentIntentId: intentId, andRequest: receiptCredentialRequest)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode == 200 {
                Logger.debug("Got valid receipt response")
            } else if statusCode == 204 {
                Logger.debug("No receipt could be found for this payment intent")
            } else {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }

            guard let json = response.responseBodyJson as? [String: Any] else {
                throw OWSAssertionError("Unable to parse response body.")
            }

            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            do {
                let receiptCredentialResponseString: String = try parser.required(key: "receiptCredentialResponse")
                guard let receiptCredentialResponseData = Data(base64Encoded: receiptCredentialResponseString) else {
                    throw OWSAssertionError("Unable to parse receiptCredentialResponse into data.")
                }

                let receiptCredentialResponse = try ReceiptCredentialResponse(contents: [UInt8](receiptCredentialResponseData))
                let receiptCredential = try clientOperations.receiveReceiptCredential(receiptCredentialRequestContext: context, receiptCredentialResponse: receiptCredentialResponse)

                // Validate that receipt credential level matches boost level
                let level = try receiptCredential.getReceiptLevel()
                guard level == 1 else {
                    throw OWSAssertionError("Unexpected receipt credential level")
                }

                // Validate receipt credential expiration % 86400 == 0, per server spec
                let expiration = try receiptCredential.getReceiptExpirationTime()
                guard expiration % 86400 == 0 else {
                    throw OWSAssertionError("Invalid receipt credential expiration, expiration mod != 0")
                }

                // Validate expiration is less than 60 days from now
                let maximumValidExpirationDate = Date().timeIntervalSince1970 + (60 * 24 * 60 * 60)
                guard TimeInterval(expiration) < maximumValidExpirationDate else {
                    throw OWSAssertionError("Invalid receipt credential expiration, expiration is more than 60 days from now")
                }

                let receiptCredentialPresentation = try clientOperations.createReceiptCredentialPresentation(receiptCredential: receiptCredential)

                return receiptCredentialPresentation
            } catch {
                throw OWSAssertionError("Missing clientID key")
            }
        }
    }

    public class func getBoostBadge() -> Promise<ProfileBadge> {
        let request = OWSRequestFactory.boostBadgesRequest()

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in

            guard let json = response.responseBodyJson as? [String: Any] else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }

            guard let rootParser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            let levels: [String: Any] = try rootParser.required(key: "levels")

            guard let levelsParser = ParamParser(responseObject: levels) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            let boostLevel: [String: Any] = try levelsParser.required(key: "1")

            guard let levelParser = ParamParser(responseObject: boostLevel) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            let badgeJson: [String: Any] = try levelParser.required(key: "badge")

            return try ProfileBadge(jsonDictionary: badgeJson)
        }
    }
}
