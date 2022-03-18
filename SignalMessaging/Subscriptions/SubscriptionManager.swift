//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import PassKit
import SignalClient
import SignalServiceKit

public enum SubscriptionBadgeIds: String, CaseIterable {
    case low = "R_LOW"
    case med = "R_MED"
    case high = "R_HIGH"

    public static func contains(_ id: String) -> Bool {
        allCases.lazy.map { $0.rawValue }.contains(id)
    }
}

public enum BoostBadgeIds: String, CaseIterable {
    case boost = "BOOST"

    public static func contains(_ id: String) -> Bool {
        allCases.lazy.map { $0.rawValue }.contains(id)
    }
}

public enum SubscriptionRedemptionFailureReason: Int {
    case none = 0
    case localValidationFailed = 1
    case serverValidationFailed = 400
    case paymentFailed = 402
    case paymentNotFound = 404
    case paymentIntentRedeemed = 409
}

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

    public enum StripeSubscriptionStatus: String {
        case unknown
        case trialing = "trialing"
        case active = "active"
        case incomplete = "incomplete"
        case incompleteExpired = "incomplete_expired"
        case pastDue = "past_due"
        case canceled = "canceled"
        case unpaid = "unpaid"
    }

    public let level: UInt
    public let currency: String
    public let amount: NSDecimalNumber
    public let endOfCurrentPeriod: TimeInterval
    public let billingCycleAnchor: TimeInterval
    public let active: Bool
    public let cancelAtEndOfPeriod: Bool
    public let status: StripeSubscriptionStatus

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
        status = StripeSubscriptionStatus(rawValue: try params.required(key: "status")) ?? .unknown
    }
}

@objc
public class SubscriptionManager: NSObject {

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            DispatchQueue.global().async {
                Self.warmCaches()
                Self.performMigrationToStorageServiceIfNecessary()
                Self.performSubscriptionKeepAliveIfNecessary()
            }
        }
    }

    private static func warmCaches() {
        let value = databaseStorage.read { displayBadgesOnProfile(transaction: $0) }
        displayBadgesOnProfileCache.set(value)
    }

    private static func performMigrationToStorageServiceIfNecessary() {
        let hasMigratedToStorageService = databaseStorage.read { transaction in
            subscriptionKVS.getBool(hasMigratedToStorageServiceKey, defaultValue: false, transaction: transaction)
        }

        guard !hasMigratedToStorageService else { return }

        databaseStorage.write { transaction in
            subscriptionKVS.setBool(true, key: hasMigratedToStorageServiceKey, transaction: transaction)

            let localProfile = profileManagerImpl.localUserProfile()
            let allBadges = localProfile.profileBadgeInfo ?? []
            let displayBadgesOnProfile = allBadges.allSatisfy { badge in
                badge.isVisible ?? {
                    owsFailDebug("Local user badges should always have a non-nil visibility flag")
                    return true
                }()
            }

            setDisplayBadgesOnProfile(displayBadgesOnProfile, transaction: transaction)
        }

        storageServiceManager.recordPendingLocalAccountUpdates()
    }

    public static let subscriptionJobQueue = SubscriptionReceiptCredentialJobQueue()
    public static let SubscriptionJobQueueDidFinishJobNotification = NSNotification.Name("SubscriptionJobQueueDidFinishJobNotification")
    public static let SubscriptionJobQueueDidFailJobNotification = NSNotification.Name("SubscriptionJobQueueDidFailJobNotification")
    private static let subscriptionKVS = SDSKeyValueStore(collection: "SubscriptionKeyValueStore")

    fileprivate static let subscriberIDKey = "subscriberID"
    fileprivate static let subscriberCurrencyCodeKey = "subscriberCurrencyCode"
    fileprivate static let lastSubscriptionExpirationKey = "subscriptionExpiration"
    fileprivate static let lastSubscriptionHeartbeatKey = "subscriptionHeartbeat"
    fileprivate static let lastSubscriptionReceiptRedemptionFailedKey = "lastSubscriptionReceiptRedemptionFailedKey"
    fileprivate static let userManuallyCancelledSubscriptionKey = "userManuallyCancelledSubscriptionKey"
    fileprivate static let displayBadgesOnProfileKey = "displayBadgesOnProfileKey"
    fileprivate static let knownUserSubscriptionBadgeIDsKey = "knownUserSubscriptionBadgeIDsKey"
    fileprivate static let knownUserBoostBadgeIDsKey = "knownUserBoostBadgeIDsKey"
    fileprivate static let mostRecentlyExpiredBadgeIDKey = "mostRecentlyExpiredBadgeIDKey"
    fileprivate static let showExpirySheetOnHomeScreenKey = "showExpirySheetOnHomeScreenKey"
    fileprivate static let hasMigratedToStorageServiceKey = "hasMigratedToStorageServiceKey"

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

    // Returns if we have a current subscription or not as calculated via our cached last subscription expiry date and subscriberID.
    // The most accurate way to determine subscription status is via getCurrentSubscriptionStatus()
    public class func hasCurrentSubscriptionWithSneakyTransaction() -> Bool {
        databaseStorage.read { subscriptionManager.hasCurrentSubscription(transaction: $0) }
    }

    public class func currentProfileSubscriptionBadges() -> [OWSUserProfileBadgeInfo] {
        let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: true)
        let profileBadges = snapshot.profileBadgeInfo ?? []
        return profileBadges.compactMap { (badge: OWSUserProfileBadgeInfo) -> OWSUserProfileBadgeInfo? in
            guard SubscriptionBadgeIds.contains(badge.badgeId) else { return nil }
            return badge
        }
    }

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

            databaseStorage.write { transaction in
                self.setUserManuallyCancelledSubscription(false, transaction: transaction)
                self.setSubscriberID(subscriberID, transaction: transaction)
                self.setSubscriberCurrencyCode(currencyCode, transaction: transaction)
                self.setMostRecentlyExpiredBadgeID(badgeID: nil, transaction: transaction)
                self.setShowExpirySheetOnHomeScreenKey(show: false, transaction: transaction)
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

        let failureReason: SubscriptionRedemptionFailureReason = databaseStorage.read { transaction in
            return self.lastReceiptRedemptionFailed(transaction: transaction)
        }

        if failureReason != .none {
            Logger.info("[Subscriptions] Upgrading subscription with a prior known error state, cancelling and re-setting up")
            return firstly {
                try self.cancelSubscription(for: subscriberID)
            }.then(on: .sharedUserInitiated) {
                try self.setupNewSubscription(subscription: subscription, payment: payment, currencyCode: currencyCode)
            }
        }

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

    public class func cancelSubscription(for subscriberID: Data) -> Promise<Void> {
        let request = OWSRequestFactory.deleteSubscriptionIDRequest(subscriberID.asBase64Url)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            } else {
                databaseStorage.write { transaction in
                    self.setSubscriberID(nil, transaction: transaction)
                    self.setSubscriberCurrencyCode(nil, transaction: transaction)
                    self.setLastSubscriptionExpirationDate(nil, transaction: transaction)
                    self.setLastReceiptRedemptionFailed(failureReason: .none, transaction: transaction)
                    self.setUserManuallyCancelledSubscription(true, transaction: transaction)
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

        let subscriberIDURL = subscriberID.asBase64Url
        let key = Cryptography.generateRandomBytes(UInt(32)).asBase64Url
        let level = String(subscription.level)
        let request = OWSRequestFactory.subscriptionSetSubscriptionLevelRequest(subscriberIDURL, level: level, currency: currency, idempotencyKey: key)
        return firstly {
            networkManager.makePromise(request: request)
        }.then(on: .global()) { response -> Promise<Subscription?> in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }

            return self.getCurrentSubscriptionStatus(for: subscriberID)
        }.done(on: .global()) { subscription in
            guard let subscription = subscription else {
                throw OWSAssertionError("Failed to fetch valid subscription object after setSubscription")
            }

            databaseStorage.write { transaction in
                self.setLastSubscriptionExpirationDate(Date(timeIntervalSince1970: subscription.endOfCurrentPeriod), transaction: transaction)
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
        databaseStorage.write { transaction in
            self.setLastReceiptRedemptionFailed(failureReason: .none, transaction: transaction)
        }

        databaseStorage.asyncWrite { transaction in

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
                Logger.info("Got valid receipt response")
            } else if statusCode == 204 {
                Logger.info("User has no active subscriptions when getting receipt presentation, retrying!")
                throw OWSRetryableSubscriptionError()
            } else {
                Logger.info("Got undefined non-4xx error fetching receipt presentation, retrying!")
                throw OWSRetryableSubscriptionError()
            }

            let failValidation = {
                databaseStorage.write { transaction in
                    self.setLastReceiptRedemptionFailed(failureReason: .localValidationFailed, transaction: transaction)
                }
            }

            guard let json = response.responseBodyJson as? [String: Any] else {
                failValidation()
                throw OWSAssertionError("Unable to parse receipt presentation response body.")
            }

            guard let parser = ParamParser(responseObject: json) else {
                failValidation()
                throw OWSAssertionError("Missing or invalid receipt presentation response.")
            }

            let receiptCredentialResponseString: String = try parser.required(key: "receiptCredentialResponse")
            guard let receiptCredentialResponseData = Data(base64Encoded: receiptCredentialResponseString) else {
                failValidation()
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
                failValidation()
                throw OWSAssertionError("Unexpected receipt credential level, validation failed. Got \(level), expected \(targetSubscriptionLevel) or \(priorSubscriptionLevel)")
            }

            // Validate receipt credential expiration % 86400 == 0, per server spec
            let expiration = try receiptCredential.getReceiptExpirationTime()
            guard expiration % 86400 == 0 else {
                failValidation()
                throw OWSAssertionError("Invalid receipt credential expiration, expiration mod != 0, validation failed")
            }

            // Validate expiration is less than 60 days from now
            let maximumValidExpirationDate = Date().timeIntervalSince1970 + (60 * 24 * 60 * 60)
            guard TimeInterval(expiration) < maximumValidExpirationDate else {
                failValidation()
                throw OWSAssertionError("Invalid receipt credential expiration, expiration is more than 60 days from now")
            }

            let receiptCredentialPresentation = try clientOperations.createReceiptCredentialPresentation(receiptCredential: receiptCredential)

            return receiptCredentialPresentation
        }.recover { error -> Promise<ReceiptCredentialPresentation> in
            if let error = error as? OWSHTTPError {
                let statusCode = error.responseStatusCode
                if statusCode == 400 || statusCode == 402 || statusCode == 403 || statusCode == 404 || statusCode ==  409 {
                    let failureReason = SubscriptionRedemptionFailureReason(rawValue: statusCode) ?? .none
                    databaseStorage.write { transaction in
                        self.setLastReceiptRedemptionFailed(failureReason: failureReason, transaction: transaction)
                    }
                    throw OWSAssertionError("Receipt redemption failed with unrecoverable HTTP code \(statusCode)")
                } else {
                    Logger.info("Receipt redemption failed with retryable HTTP code \(statusCode)")
                    throw OWSRetryableSubscriptionError()
                }
            }
            throw error
        }
    }

    public class func redeemReceiptCredentialPresentation(receiptCredentialPresentation: ReceiptCredentialPresentation) throws -> Promise<Void> {
        let receiptCredentialPresentationData = receiptCredentialPresentation.serialize().asData

        let receiptCredentialPresentationString = receiptCredentialPresentationData.base64EncodedString()
        let request = OWSRequestFactory.subscriptionRedeemRecieptCredential(
            receiptCredentialPresentationString
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

        // Kick job queue
        _ = subscriptionJobQueue.runAnyQueuedRetry()

        Logger.info("[Subscriptions] Checking for subscription heartbeat")

        // Fetch subscriberID / subscriber currencyCode
        var lastKeepAliveHeartbeat: Date?
        var lastSubscriptionExpiration: Date?
        var subscriberID: Data?
        var currencyCode: String?
        databaseStorage.read { transaction in
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

        Logger.info("[Subscriptions] Performing subscription heartbeat")

        guard tsAccountManager.isPrimaryDevice else {
            Logger.info("[Subscriptions] Bailing out of remaining heartbeat tasks, this is not the primary device")
            return
        }

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
                let newDate = Date(timeIntervalSince1970: subscription.endOfCurrentPeriod)
                Logger.info("[Subscriptions] Triggering receipt redemption job during heartbeat, last expiration \(lastSubscriptionExpiration), new expiration \(newDate)")
                try self.requestAndRedeemRecieptsIfNecessary(for: subscriberID, subscriptionLevel: subscription.level)

                // Save last expiration
                databaseStorage.write { transaction in
                    self.setLastSubscriptionExpirationDate(Date(timeIntervalSince1970: subscription.endOfCurrentPeriod), transaction: transaction)
                }

            } else {
                Logger.info("[Subscriptions] Not triggering receipt redemption, expiration date is the same")
            }

            // Save heartbeat
            self.updateSubscriptionHeartbeatDate()

        }.catch(on: .sharedBackground) { error in
            owsFailDebug("Failed subscription heartbeat with error \(error)")
        }
    }

    public static func mostRecentlyExpiredBadgeIDWithSneakyTransaction() -> String? {
        databaseStorage.read { mostRecentlyExpiredBadgeID(transaction: $0) }
    }

    private static func updateSubscriptionHeartbeatDate() {
        databaseStorage.write { transaction in
            // Update keepalive
            self.subscriptionKVS.setDate(Date(), key: self.lastSubscriptionHeartbeatKey, transaction: transaction)
        }
    }

    @objc
    public class func performDeviceSubscriptionExpiryUpdate() {
        Logger.info("[Subscriptions] doing subscription expiry update")

        var lastSubscriptionExpiration: Date?
        var subscriberID: Data?
        databaseStorage.read { transaction in
            lastSubscriptionExpiration = self.subscriptionKVS.getDate(self.lastSubscriptionExpirationKey, transaction: transaction)
            subscriberID = self.getSubscriberID(transaction: transaction)
        }

        guard let subscriberID = subscriberID else {
            owsFailDebug("Device missing subscriberID")
            return
        }

        firstly(on: .sharedBackground) {
            // Fetch current subscription
            self.getCurrentSubscriptionStatus(for: subscriberID)
        }.done(on: .sharedBackground) { subscription in
            guard let subscription = subscription else {
                Logger.info("[Subscriptions] No current subscription for this subscriberID")
                return
            }

            if let lastSubscriptionExpiration = lastSubscriptionExpiration, lastSubscriptionExpiration.timeIntervalSince1970 == subscription.endOfCurrentPeriod {
                Logger.info("[Subscriptions] Not updating last subscription expiration, expirations are the same")
            } else {
                Logger.info("[Subscriptions] Updating last subscription expiration")
                // Save last expiration
                databaseStorage.write { transaction in
                    self.setLastSubscriptionExpirationDate(Date(timeIntervalSince1970: subscription.endOfCurrentPeriod), transaction: transaction)
                }
            }

        }.catch(on: .sharedBackground) { error in
            owsFailDebug("Failed last subscription expiration update with error \(error)")
        }
    }
}

extension SubscriptionManager {

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

    public static func setLastReceiptRedemptionFailed(failureReason: SubscriptionRedemptionFailureReason, transaction: SDSAnyWriteTransaction) {
        subscriptionKVS.setInt(failureReason.rawValue, key: lastSubscriptionReceiptRedemptionFailedKey, transaction: transaction)
    }

    public static func lastReceiptRedemptionFailed(transaction: SDSAnyReadTransaction) -> SubscriptionRedemptionFailureReason {
        let intValue = subscriptionKVS.getInt(lastSubscriptionReceiptRedemptionFailedKey, transaction: transaction)
        guard let intValue = intValue else {
            return .none
        }

        if let reason = SubscriptionRedemptionFailureReason(rawValue: intValue) {
            return reason
        } else {
            return .none
        }
    }

    public static func userManuallyCancelledSubscription(transaction: SDSAnyReadTransaction) -> Bool {
        return subscriptionKVS.getBool(userManuallyCancelledSubscriptionKey, transaction: transaction) ?? false
    }

    private static func setUserManuallyCancelledSubscription(_ value: Bool, updateStorageService: Bool = false, transaction: SDSAnyWriteTransaction) {
        guard value != userManuallyCancelledSubscription(transaction: transaction) else { return }
        subscriptionKVS.setBool(value, key: userManuallyCancelledSubscriptionKey, transaction: transaction)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    private static func displayBadgesOnProfile(transaction: SDSAnyReadTransaction) -> Bool {
        return subscriptionKVS.getBool(displayBadgesOnProfileKey, transaction: transaction) ?? false
    }

    private static var displayBadgesOnProfileCache = AtomicBool(false)
    private static func setDisplayBadgesOnProfile(_ value: Bool, updateStorageService: Bool = false, transaction: SDSAnyWriteTransaction) {
        guard value != displayBadgesOnProfile(transaction: transaction) else { return }
        displayBadgesOnProfileCache.set(value)
        subscriptionKVS.setBool(value, key: displayBadgesOnProfileKey, transaction: transaction)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    fileprivate static func lastSubscriptionExpirationDate(transaction: SDSAnyReadTransaction) -> Date? {
        return subscriptionKVS.getDate(lastSubscriptionExpirationKey, transaction: transaction)
    }

    fileprivate static func setLastSubscriptionExpirationDate(_ expirationDate: Date?, transaction: SDSAnyWriteTransaction) {
        guard let expirationDate = expirationDate else {
            subscriptionKVS.removeValue(forKey: lastSubscriptionExpirationKey, transaction: transaction)
            return
        }

        subscriptionKVS.setDate(expirationDate, key: lastSubscriptionExpirationKey, transaction: transaction)
    }

    fileprivate static func setKnownUserSubscriptionBadgeIDs(badgeIDs: [String], transaction: SDSAnyWriteTransaction) {
        subscriptionKVS.setObject(badgeIDs, key: knownUserSubscriptionBadgeIDsKey, transaction: transaction)
    }

    fileprivate static func knownUserSubscriptionBadgeIDs(transaction: SDSAnyReadTransaction) -> [String] {
        let ids = subscriptionKVS.getObject(forKey: knownUserSubscriptionBadgeIDsKey, transaction: transaction) as? [String]
        return ids ?? []
    }

    fileprivate static func setKnownUserBoostBadgeIDs(badgeIDs: [String], transaction: SDSAnyWriteTransaction) {
        subscriptionKVS.setObject(badgeIDs, key: knownUserBoostBadgeIDsKey, transaction: transaction)
    }

    fileprivate static func knownUserBoostBadgeIDs(transaction: SDSAnyReadTransaction) -> [String] {
        guard let ids = subscriptionKVS.getObject(forKey: knownUserBoostBadgeIDsKey, transaction: transaction) as? [String] else {
            return []
        }

        return ids
    }

    fileprivate static func setMostRecentlyExpiredBadgeID(badgeID: String?, transaction: SDSAnyWriteTransaction) {
        guard let badgeID = badgeID else {
            subscriptionKVS.removeValue(forKey: mostRecentlyExpiredBadgeIDKey, transaction: transaction)
            return
        }

        subscriptionKVS.setString(badgeID, key: mostRecentlyExpiredBadgeIDKey, transaction: transaction)

    }

    public static func mostRecentlyExpiredBadgeID(transaction: SDSAnyReadTransaction) -> String? {
        subscriptionKVS.getString(mostRecentlyExpiredBadgeIDKey, transaction: transaction)
    }

    public static func clearMostRecentlyExpiredBadgeIDWithSneakyTransaction() {
        databaseStorage.write { transaction in
            self.setMostRecentlyExpiredBadgeID(badgeID: nil, transaction: transaction)
        }
    }

    public static func setShowExpirySheetOnHomeScreenKey(show: Bool, transaction: SDSAnyWriteTransaction) {
        Logger.info("\(show)")
        subscriptionKVS.setBool(show, key: showExpirySheetOnHomeScreenKey, transaction: transaction)
    }

    public static func showExpirySheetOnHomeScreenKey(transaction: SDSAnyReadTransaction) -> Bool {
        return subscriptionKVS.getBool(showExpirySheetOnHomeScreenKey, transaction: transaction) ?? false
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

        databaseStorage.asyncWrite { transaction in

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
                Logger.debug("No receipt could be found for this boost payment intent")
                throw OWSRetryableSubscriptionError()
            } else {
                Logger.info("Got undefined non-4xx error fetching boost receipt presentation, retrying!")
                throw OWSRetryableSubscriptionError()
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
        }.recover { error -> Promise<ReceiptCredentialPresentation> in
            if let error = error as? OWSHTTPError {
                let statusCode = error.responseStatusCode
                if [400, 402, 409].contains(statusCode) {
                    throw OWSAssertionError("Boost receipt redemption failed with unrecoverable HTTP code \(statusCode)")
                } else {
                    Logger.info("Boost receipt redemption failed with retryable HTTP code \(statusCode)")
                    throw OWSRetryableSubscriptionError()
                }
            }
            throw error
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

@objc
extension SubscriptionManager: SubscriptionManagerProtocol {
    public func reconcileBadgeStates(transaction: SDSAnyWriteTransaction) {
        Logger.info("Reconciling badge state.")

        // Get current badges
        let currentBadges = profileManagerImpl.localUserProfile().profileBadgeInfo ?? []
        let currentSubscriberBadgeIDs = currentBadges.compactMap { (badge: OWSUserProfileBadgeInfo) -> String? in
            guard SubscriptionBadgeIds.contains(badge.badgeId) else { return nil }
            return badge.badgeId
        }

        let currentBoostBadgeIDs = currentBadges.compactMap { (badge: OWSUserProfileBadgeInfo) -> String? in
            guard BoostBadgeIds.contains(badge.badgeId) else { return nil }
            return badge.badgeId
        }

        // Read existing values
        let persistedSubscriberBadgeIDs = Self.knownUserSubscriptionBadgeIDs(transaction: transaction)
        let persistedBoostBadgeIDs = Self.knownUserBoostBadgeIDs(transaction: transaction)
        var expiringBadgeId = Self.mostRecentlyExpiredBadgeID(transaction: transaction)
        var userManuallyCancelled = Self.userManuallyCancelledSubscription(transaction: transaction)
        var showExpiryOnHomeScreen = Self.showExpirySheetOnHomeScreenKey(transaction: transaction)
        var displayBadgesOnProfile = Self.displayBadgesOnProfile(transaction: transaction)

        if !currentBadges.isEmpty {
            let isCurrentlyDisplayingBadgesOnProfile = currentBadges.allSatisfy { badge in
                badge.isVisible ?? {
                    owsFailDebug("Local user badges should always have a non-nil visibility flag")
                    return true
                }()
            }
            if displayBadgesOnProfile != isCurrentlyDisplayingBadgesOnProfile {
                displayBadgesOnProfile = isCurrentlyDisplayingBadgesOnProfile
                Logger.info("Updating displayBadgesOnProfile to reflect state on profile \(displayBadgesOnProfile)")
            }
        }

        let newSubscriberBadgeIds = Set(currentSubscriberBadgeIDs).subtracting(persistedSubscriberBadgeIDs)
        Logger.info("Learned of \(newSubscriberBadgeIds.count) new subscriber badge ids: \(newSubscriberBadgeIds)")

        let expiredSubscriberBadgeIds = Set(persistedSubscriberBadgeIDs).subtracting(currentSubscriberBadgeIDs)
        Logger.info("Learned of \(expiredSubscriberBadgeIds.count) newly expired subscriber badge ids: \(expiredSubscriberBadgeIds)")

        let newBoostBadgeIds = Set(currentBoostBadgeIDs).subtracting(persistedBoostBadgeIDs)
        Logger.info("Learned of \(newBoostBadgeIds.count) new boost badge ids: \(newBoostBadgeIds)")

        let expiredBoostBadgeIds = Set(persistedBoostBadgeIDs).subtracting(currentBoostBadgeIDs)
        Logger.info("Learned of \(expiredBoostBadgeIds.count) newly expired boost badge ids: \(expiredBoostBadgeIds)")

        var newExpiringBadgeId: String?
        if let persistedBadgeId = persistedSubscriberBadgeIDs.first, currentSubscriberBadgeIDs.isEmpty {
            if !userManuallyCancelled {
                Logger.info("Last subscription badge id expired \(persistedBadgeId)")
                newExpiringBadgeId = persistedBadgeId
            } else {
                Logger.info("Last subscription badge id expired \(persistedBadgeId), but ignoring because subscription was manually cancelled")
            }
        }

        if let persistedBadgeId = persistedBoostBadgeIDs.first, currentBoostBadgeIDs.isEmpty {
            if (expiringBadgeId == nil || BoostBadgeIds.contains(expiringBadgeId!)) && newExpiringBadgeId == nil {
                Logger.info("Last boost badge id expired \(persistedBadgeId)")
                newExpiringBadgeId = persistedBadgeId
            } else {
                Logger.info("Last boost badge id expired \(persistedBadgeId), but ignoring because subscription badge also expired")
            }
        }

        if let newExpiringBadgeId = newExpiringBadgeId, newExpiringBadgeId != expiringBadgeId {
            Logger.info("Recording new expired badge id to show on home screen \(newExpiringBadgeId)")
            expiringBadgeId = newExpiringBadgeId
            showExpiryOnHomeScreen = true
        } else if let oldExpiringBadgeId = expiringBadgeId {
            if SubscriptionBadgeIds.contains(oldExpiringBadgeId), !newSubscriberBadgeIds.isEmpty {
                Logger.info("Clearing expired subscription badge id \(oldExpiringBadgeId), new subscription badge found.")
                expiringBadgeId = nil
                showExpiryOnHomeScreen = false
            } else if BoostBadgeIds.contains(oldExpiringBadgeId), !newBoostBadgeIds.isEmpty {
                Logger.info("Clearing expired boost badge id \(oldExpiringBadgeId), new boost badge found.")
                expiringBadgeId = nil
                showExpiryOnHomeScreen = false
            }
        }

        if userManuallyCancelled, !newSubscriberBadgeIds.isEmpty {
            Logger.info("Clearing manual subscription cancellation, new subscription badge found.")
            userManuallyCancelled = false
        }

        Logger.info("""
        Reconciled badge state:
            Subscriber Badge Ids: \(currentSubscriberBadgeIDs)
            Boost Badge Ids: \(currentBoostBadgeIDs)
            Most Recently Expired Badge Id: \(expiringBadgeId ?? "nil")
            Show Expiry On Home Screen: \(showExpiryOnHomeScreen)
            User Manually Cancelled Subscription: \(userManuallyCancelled)
            Display Badges On Profile: \(displayBadgesOnProfile)
        """)

        // Persist new values
        Self.setKnownUserSubscriptionBadgeIDs(badgeIDs: currentSubscriberBadgeIDs, transaction: transaction)
        Self.setKnownUserBoostBadgeIDs(badgeIDs: currentBoostBadgeIDs, transaction: transaction)
        Self.setMostRecentlyExpiredBadgeID(badgeID: expiringBadgeId, transaction: transaction)
        Self.setShowExpirySheetOnHomeScreenKey(show: showExpiryOnHomeScreen, transaction: transaction)
        Self.setUserManuallyCancelledSubscription(userManuallyCancelled, transaction: transaction)
        Self.setDisplayBadgesOnProfile(displayBadgesOnProfile, transaction: transaction)
    }

    public func hasCurrentSubscription(transaction: SDSAnyReadTransaction) -> Bool {
        guard !Self.currentProfileSubscriptionBadges().isEmpty else { return false }

        guard Self.getSubscriberID(transaction: transaction) != nil else { return false }

        guard let lastSubscriptionExpiryDate = Self.lastSubscriptionExpirationDate(transaction: transaction) else {
            return false
        }

        return lastSubscriptionExpiryDate.isAfterNow
    }

    public func timeSinceLastSubscriptionExpiration(transaction: SDSAnyReadTransaction) -> TimeInterval {
        guard let lastSubscriptionExpiryDate = Self.lastSubscriptionExpirationDate(transaction: transaction) else {
            return -Date.distantPast.timeIntervalSinceNow
        }

        guard lastSubscriptionExpiryDate.isBeforeNow else {
            return 0
        }

        return -lastSubscriptionExpiryDate.timeIntervalSinceNow
    }

    public func userManuallyCancelledSubscription(transaction: SDSAnyReadTransaction) -> Bool {
        return Self.userManuallyCancelledSubscription(transaction: transaction)
    }

    public func setUserManuallyCancelledSubscription(_ userCancelled: Bool, updateStorageService: Bool, transaction: SDSAnyWriteTransaction) {
        Self.setUserManuallyCancelledSubscription(userCancelled, updateStorageService: updateStorageService, transaction: transaction)
    }

    public var displayBadgesOnProfile: Bool { Self.displayBadgesOnProfileCache.get() }

    public func displayBadgesOnProfile(transaction: SDSAnyReadTransaction) -> Bool {
        return Self.displayBadgesOnProfile(transaction: transaction)
    }

    public func setDisplayBadgesOnProfile(_ displayBadgesOnProfile: Bool, updateStorageService: Bool, transaction: SDSAnyWriteTransaction) {
        Self.setDisplayBadgesOnProfile(displayBadgesOnProfile, updateStorageService: updateStorageService, transaction: transaction)
    }
}
