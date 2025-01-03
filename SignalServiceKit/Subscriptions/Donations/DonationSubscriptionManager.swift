//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
public import LibSignalClient

public enum OneTimeBadgeLevel: Hashable {
    case boostBadge
    case giftBadge(OWSGiftBadge.Level)

    public var rawValue: UInt64 {
        switch self {
        case .boostBadge:
            return 1
        case .giftBadge(let level):
            return level.rawLevel
        }
    }
}

public enum SubscriptionBadgeIds: String, CaseIterable {
    case low = "R_LOW"
    case med = "R_MED"
    case high = "R_HIGH"

    public static func contains(_ id: String) -> Bool {
        return Self(rawValue: id) != nil
    }
}

public enum BoostBadgeIds: String {
    case boost = "BOOST"

    public static func contains(_ id: String) -> Bool {
        return Self(rawValue: id) != nil
    }
}

public enum GiftBadgeIds: String {
    case gift = "GIFT"

    public static func contains(_ id: String) -> Bool {
        return Self(rawValue: id) != nil
    }
}

public extension Notification.Name {
    static let hasExpiredGiftBadgeDidChangeNotification = NSNotification.Name("hasExpiredGiftBadgeDidChangeNotification")
}

/// Responsible for one-time and recurring-subscription actions related to
/// donation payments and their resulting profile badges.
///
/// - Note
/// Donation payments are done via external payment processors (Stripe and
/// Braintree) that consequently require custom, in-app payments management; for
/// example, subscriptions are cancelled via in-app UI.
///
/// - Important
/// Not to be confused with ``BackupSubscriptionManager``, which does many
/// similar things but designed around In-App Payments (StoreKit) and paid-tier
/// Backups.
@objc
public class DonationSubscriptionManager: NSObject {

    public static func warmCaches() {
        let value = SSKEnvironment.shared.databaseStorageRef.read { displayBadgesOnProfile(transaction: $0) }
        displayBadgesOnProfileCache.set(value)
    }

    public static func performMigrationToStorageServiceIfNecessary() {
        let hasMigratedToStorageService = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            subscriptionKVS.getBool(hasMigratedToStorageServiceKey, defaultValue: false, transaction: transaction.asV2Read)
        }

        guard !hasMigratedToStorageService else { return }

        Logger.info("[Donations] Migrating to storage service")

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            subscriptionKVS.setBool(true, key: hasMigratedToStorageServiceKey, transaction: transaction.asV2Write)

            let localProfile = SSKEnvironment.shared.profileManagerImplRef.localUserProfile
            let displayBadgesOnProfile = localProfile.badges.allSatisfy { badge in
                badge.isVisible ?? {
                    owsFailDebug("Local user badges should always have a non-nil visibility flag")
                    return true
                }()
            }

            setDisplayBadgesOnProfile(displayBadgesOnProfile, transaction: transaction)
        }

        SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
    }

    // MARK: -

    private static var receiptCredentialRedemptionJobQueue: DonationReceiptCredentialRedemptionJobQueue {
        SSKEnvironment.shared.donationReceiptCredentialRedemptionJobQueue
    }

    /// - Note
    /// This collection name is reused by other subscription-related stores. For
    /// example, see ``DonationReceiptCredentialResultStore``.
    private static let subscriptionKVS = KeyValueStore(collection: "SubscriptionKeyValueStore")

    fileprivate static let subscriberIDKey = "subscriberID"
    fileprivate static let subscriberCurrencyCodeKey = "subscriberCurrencyCode"
    fileprivate static let lastSubscriptionExpirationKey = "subscriptionExpiration"
    fileprivate static let lastSubscriptionHeartbeatKey = "subscriptionHeartbeat"
    fileprivate static let userManuallyCancelledSubscriptionKey = "userManuallyCancelledSubscriptionKey"
    fileprivate static let displayBadgesOnProfileKey = "displayBadgesOnProfileKey"
    fileprivate static let knownUserSubscriptionBadgeIDsKey = "knownUserSubscriptionBadgeIDsKey"
    fileprivate static let knownUserBoostBadgeIDsKey = "knownUserBoostBadgeIDsKey"
    fileprivate static let knownUserGiftBadgeIDsKey = "knownUserGiftBageIDsKey"
    fileprivate static let mostRecentlyExpiredBadgeIDKey = "mostRecentlyExpiredBadgeIDKey"
    fileprivate static let mostRecentlyExpiredGiftBadgeIDKey = "mostRecentlyExpiredGiftBadgeIDKey"
    fileprivate static let showExpirySheetOnHomeScreenKey = "showExpirySheetOnHomeScreenKey"
    fileprivate static let mostRecentSubscriptionPaymentMethodKey = "mostRecentSubscriptionPaymentMethod"
    fileprivate static let hasMigratedToStorageServiceKey = "hasMigratedToStorageServiceKey"

    // MARK: Current subscription status

    public class func currentProfileSubscriptionBadges() -> [OWSUserProfileBadgeInfo] {
        let snapshot = SSKEnvironment.shared.profileManagerImplRef.localProfileSnapshot(shouldIncludeAvatar: false)
        let profileBadges = snapshot.profileBadgeInfo ?? []
        return profileBadges.compactMap { (badge: OWSUserProfileBadgeInfo) -> OWSUserProfileBadgeInfo? in
            guard SubscriptionBadgeIds.contains(badge.badgeId) else { return nil }
            return badge
        }
    }

    /// A low-overhead, synchronous check for whether we *probably* have a
    /// current donation subscription. Callers who need to know precise details
    /// about our subscription should use `getCurrentSubscriptionStatus`.
    public class func probablyHasCurrentSubscription() -> Bool {
        return !currentProfileSubscriptionBadges().isEmpty
    }

    public class func getCurrentSubscriptionStatus(
        for subscriberID: Data,
        networkManager: NetworkManager = SSKEnvironment.shared.networkManagerRef
    ) -> Promise<Subscription?> {
        let request = OWSRequestFactory.subscriptionGetCurrentSubscriptionLevelRequest(subscriberID: subscriberID)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
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
                let chargeFailureDict: [String: Any]? = try? parser.optional(key: "chargeFailure")

                return try Subscription(subscriptionDict: subscriptionDict,
                                        chargeFailureDict: chargeFailureDict)
            } else {
                return nil
            }
        }
    }

    // MARK: Subscription management

    /// Perform processor-agnostic steps to set up a new subscription, before
    /// payment has been authorized.
    ///
    /// - Returns: The new subscriber ID.
    public class func prepareNewSubscription(currencyCode: Currency.Code) -> Promise<Data> {
        firstly {
            Logger.info("[Donations] Setting up new subscription")

            return setupNewSubscriberID()
        }.map(on: DispatchQueue.sharedUserInitiated) { subscriberID -> Data in
            Logger.info("[Donations] Caching params after setting up new subscription")

            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                self.setUserManuallyCancelledSubscription(false, transaction: transaction)
                self.setSubscriberID(subscriberID, transaction: transaction)
                self.setSubscriberCurrencyCode(currencyCode, transaction: transaction)
                self.setMostRecentlyExpiredBadgeID(badgeID: nil, transaction: transaction)
                self.setShowExpirySheetOnHomeScreenKey(show: false, transaction: transaction)
            }

            SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()

            return subscriberID
        }
    }

    /// Finalize a new subscription, after payment has been authorized with the
    /// given processor.
    public class func finalizeNewSubscription(
        forSubscriberId subscriberId: Data,
        paymentType: RecurringSubscriptionPaymentType,
        subscription: DonationSubscriptionLevel,
        currencyCode: Currency.Code
    ) -> Promise<Subscription> {
        firstly { () -> Promise<Void> in
            Logger.info("[Donations] Setting default payment method on service")

            switch paymentType {
            case let .ideal(setupIntentId):
                return setDefaultIDEALPaymentMethod(
                    for: subscriberId,
                    setupIntentId: setupIntentId
                )
            case
                    .applePay(let paymentMethodId),
                    .creditOrDebitCard(let paymentMethodId),
                    .paypal(let paymentMethodId),
                    .sepa(let paymentMethodId):
                return setDefaultPaymentMethod(
                    for: subscriberId,
                    using: paymentType.paymentProcessor,
                    paymentMethodId: paymentMethodId
                )
            }
        }.then(on: DispatchQueue.sharedUserInitiated) { _ -> Promise<Subscription> in
            Logger.info("[Donations] Selecting subscription level on service")

            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                Self.setMostRecentSubscriptionPaymentMethod(
                    paymentMethod: paymentType.paymentMethod,
                    transaction: transaction
                )
            }

            return setSubscription(
                for: subscriberId,
                subscription: subscription,
                currencyCode: currencyCode
            )
        }
    }

    /// Update the subscription level for the given subscriber ID.
    public class func updateSubscriptionLevel(
        for subscriberID: Data,
        to subscription: DonationSubscriptionLevel,
        currencyCode: Currency.Code
    ) -> Promise<Subscription> {
        Logger.info("[Donations] Updating subscription level")

        return setSubscription(
            for: subscriberID,
            subscription: subscription,
            currencyCode: currencyCode
        )
    }

    /// Cancel a subscription for the given subscriber ID.
    public class func cancelSubscription(for subscriberID: Data) -> Promise<Void> {
        Logger.info("[Donations] Cancelling subscription")

        return firstly(on: DispatchQueue.global())  {
            // Fetch the latest subscription state
            self.getCurrentSubscriptionStatus(for: subscriberID)
        }.then(on: DispatchQueue.global()) { subscription in
            guard let subscription else {
                return Promise.value(())
            }

            // Check the subscription is in a state that can be cancelled
            // If the state isn't in active or pastDue, skip deleting the
            // subscription on the backend, and continue to clearing out the
            // local subscription information.
            switch subscription.status {
            case .active, .pastDue:
                break
            case .canceled, .incomplete, .unpaid, .unknown:
                return Promise.value(())
            }

            let request = OWSRequestFactory.deleteSubscriberID(subscriberID)
            return firstly(on: DispatchQueue.global()) {
                SSKEnvironment.shared.networkManagerRef.makePromise(request: request)
            }.map(on: DispatchQueue.global()) { response in
                switch response.responseStatusCode {
                case 200, 404:
                    break
                default:
                    throw OWSAssertionError("Got bad response code \(response.responseStatusCode).")
                }
            }.done(on: DispatchQueue.global()) {
                Logger.info("[Donations] Deleted remote subscription.")
            }
        }.done(on: DispatchQueue.global()) {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                self.setSubscriberID(nil, transaction: transaction)
                self.setSubscriberCurrencyCode(nil, transaction: transaction)
                self.setMostRecentSubscriptionPaymentMethod(paymentMethod: nil, transaction: transaction)
                self.setUserManuallyCancelledSubscription(true, transaction: transaction)

                DependenciesBridge.shared.donationReceiptCredentialResultStore
                    .clearRedemptionSuccessForAnyRecurringSubscription(tx: transaction.asV2Write)
                DependenciesBridge.shared.donationReceiptCredentialResultStore
                    .clearRequestErrorForAnyRecurringSubscription(tx: transaction.asV2Write)
            }

            SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
            Logger.info("[Donations] Deleted local subscription.")
        }
    }

    /// Generate and register an ID for a new subscriber.
    ///
    /// - Returns the new subscriber ID.
    private class func setupNewSubscriberID() -> Promise<Data> {
        Logger.info("[Donations] Setting up new subscriber ID")

        let newSubscriberID = Randomness.generateRandomBytes(UInt(32))
        return firstly {
            self.postSubscriberID(subscriberID: newSubscriberID)
        }.map(on: DispatchQueue.global()) { _ in
            return newSubscriberID
        }
    }

    private class func postSubscriberID(subscriberID: Data) -> Promise<Void> {
        let request = OWSRequestFactory.setSubscriberID(subscriberID)
        return firstly {
            SSKEnvironment.shared.networkManagerRef.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            let statusCode = response.responseStatusCode

            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
        }
    }

    private class func setDefaultPaymentMethod(
        for subscriberId: Data,
        using processor: DonationPaymentProcessor,
        paymentMethodId: String
    ) -> Promise<Void> {
        let request = OWSRequestFactory.subscriptionSetDefaultPaymentMethod(
            subscriberId: subscriberId,
            processor: processor.rawValue,
            paymentMethodId: paymentMethodId
        )

        return firstly {
            SSKEnvironment.shared.networkManagerRef.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
        }
    }

    private class func setDefaultIDEALPaymentMethod(
        for subscriberId: Data,
        setupIntentId: String
    ) -> Promise<Void> {
        let request = OWSRequestFactory.subscriptionSetDefaultIDEALPaymentMethod(
            subscriberId: subscriberId,
            setupIntentId: setupIntentId
        )

        return firstly {
            SSKEnvironment.shared.networkManagerRef.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
        }
    }

    /// Set the current subscription to the given level and currency.
    ///
    /// - Returns
    /// The updated subscription.
    private class func setSubscription(
        for subscriberID: Data,
        subscription: DonationSubscriptionLevel,
        currencyCode: Currency.Code
    ) -> Promise<Subscription> {
        let key = Randomness.generateRandomBytes(UInt(32)).asBase64Url
        let request = OWSRequestFactory.subscriptionSetSubscriptionLevelRequest(
            subscriberID: subscriberID,
            level: subscription.level,
            currency: currencyCode,
            idempotencyKey: key
        )
        return firstly {
            SSKEnvironment.shared.networkManagerRef.makePromise(request: request)
        }.then(on: DispatchQueue.global()) { response -> Promise<Subscription?> in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }

            return self.getCurrentSubscriptionStatus(for: subscriberID)
        }.map(on: DispatchQueue.global()) { subscription in
            guard let subscription = subscription else {
                throw OWSAssertionError("Failed to fetch valid subscription object after setSubscription")
            }

            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                self.setSubscriberCurrencyCode(currencyCode, transaction: transaction)
            }

            SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()

            return subscription
        }
    }

    public class func requestAndRedeemReceipt(
        subscriberId: Data,
        subscriptionLevel: UInt,
        priorSubscriptionLevel: UInt?,
        paymentProcessor: DonationPaymentProcessor,
        paymentMethod: DonationPaymentMethod?,
        isNewSubscription: Bool,
        shouldSuppressPaymentAlreadyRedeemed: Bool
    ) async throws {
        let db = DependenciesBridge.shared.db

        let (
            receiptCredentialRequestContext,
            receiptCredentialRequest
        ) = generateReceiptRequest()

        let redemptionJobRecord = await db.awaitableWrite { tx in
            return receiptCredentialRedemptionJobQueue.saveSubscriptionRedemptionJob(
                paymentProcessor: paymentProcessor,
                paymentMethod: paymentMethod,
                receiptCredentialRequestContext: receiptCredentialRequestContext,
                receiptCredentialRequest: receiptCredentialRequest,
                subscriberID: subscriberId,
                targetSubscriptionLevel: subscriptionLevel,
                priorSubscriptionLevel: priorSubscriptionLevel,
                isNewSubscription: isNewSubscription,
                shouldSuppressPaymentAlreadyRedeemed: shouldSuppressPaymentAlreadyRedeemed,
                tx: tx
            )
        }

        try await receiptCredentialRedemptionJobQueue.runRedemptionJob(
            jobRecord: redemptionJobRecord
        )
    }

    public class func requestAndRedeemReceipt(
        boostPaymentIntentId: String,
        amount: FiatMoney,
        paymentProcessor: DonationPaymentProcessor,
        paymentMethod: DonationPaymentMethod
    ) async throws {
        let db = DependenciesBridge.shared.db

        let (
            receiptCredentialRequestContext,
            receiptCredentialRequest
        ) = generateReceiptRequest()

        let redemptionJobRecord = await db.awaitableWrite { tx in
            return receiptCredentialRedemptionJobQueue.saveBoostRedemptionJob(
                amount: amount,
                paymentProcessor: paymentProcessor,
                paymentMethod: paymentMethod,
                receiptCredentialRequestContext: receiptCredentialRequestContext,
                receiptCredentialRequest: receiptCredentialRequest,
                boostPaymentIntentID: boostPaymentIntentId,
                tx: tx
            )
        }

        try await receiptCredentialRedemptionJobQueue.runRedemptionJob(
            jobRecord: redemptionJobRecord
        )
    }

    public class func generateReceiptRequest() -> (context: ReceiptCredentialRequestContext, request: ReceiptCredentialRequest) {
        do {
            let clientOperations = clientZKReceiptOperations()
            let receiptSerial = try generateReceiptSerial()

            let receiptCredentialRequestContext = try clientOperations.createReceiptCredentialRequestContext(receiptSerial: receiptSerial)
            let receiptCredentialRequest = try receiptCredentialRequestContext.getRequest()
            return (receiptCredentialRequestContext, receiptCredentialRequest)
        } catch {
            // This operation happens entirely on-device and is unlikely to fail.
            // If it does, a full crash is probably desirable.
            owsFail("Could not generate receipt request: \(error)")
        }
    }

    /// Represents a known error received during a receipt credential request.
    ///
    /// Not to be confused with ``DonationReceiptCredentialRequestError``.
    public struct KnownReceiptCredentialRequestError: Error {
        /// A code describing this error.
        public let errorCode: DonationReceiptCredentialRequestError.ErrorCode

        /// If this error represents a payment failure, contains a string from
        /// the payment processor describing the payment failure.
        public let chargeFailureCodeIfPaymentFailed: String?

        fileprivate init(
            errorCode: DonationReceiptCredentialRequestError.ErrorCode,
            chargeFailureCodeIfPaymentFailed: String? = nil
        ) {
            owsPrecondition(
                chargeFailureCodeIfPaymentFailed == nil || errorCode == .paymentFailed,
                "Must only provide a charge failure if payment failed!"
            )

            self.errorCode = errorCode
            self.chargeFailureCodeIfPaymentFailed = chargeFailureCodeIfPaymentFailed
        }
    }

    public class func requestReceiptCredential(
        subscriberId: Data,
        isValidReceiptLevelPredicate: @escaping (UInt64) -> Bool,
        context: ReceiptCredentialRequestContext,
        request: ReceiptCredentialRequest,
        networkManager: NetworkManager = SSKEnvironment.shared.networkManagerRef,
        logger: PrefixedLogger
    ) throws -> Promise<ReceiptCredential> {
        return firstly {
            let networkRequest = OWSRequestFactory.subscriptionReceiptCredentialsRequest(
                subscriberID: subscriberId,
                request: request.serialize().asData
            )

            return networkManager.makePromise(request: networkRequest)
        }.map(on: DispatchQueue.global()) { response throws -> ReceiptCredential in
            return try self.parseReceiptCredentialResponse(
                httpResponse: response,
                receiptCredentialRequestContext: context,
                isValidReceiptLevelPredicate: isValidReceiptLevelPredicate,
                logger: logger
            )
        }.recover(on: DispatchQueue.global()) { error throws -> Promise<ReceiptCredential> in
            throw parseReceiptCredentialPresentationError(error: error)
        }
    }

    public static func requestReceiptCredential(
        boostPaymentIntentId: String,
        expectedBadgeLevel: OneTimeBadgeLevel,
        paymentProcessor: DonationPaymentProcessor,
        context: ReceiptCredentialRequestContext,
        request: ReceiptCredentialRequest,
        logger: PrefixedLogger
    ) throws -> Promise<ReceiptCredential> {
        return firstly {
            let networkRequest = OWSRequestFactory.boostReceiptCredentials(
                with: boostPaymentIntentId,
                for: paymentProcessor.rawValue,
                request: request.serialize().asData
            )

            return SSKEnvironment.shared.networkManagerRef.makePromise(request: networkRequest)
        }.map(on: DispatchQueue.global()) { response throws -> ReceiptCredential in
            return try self.parseReceiptCredentialResponse(
                httpResponse: response,
                receiptCredentialRequestContext: context,
                isValidReceiptLevelPredicate: { receiptLevel in
                    return receiptLevel == expectedBadgeLevel.rawValue
                },
                logger: logger
            )
        }.recover(on: DispatchQueue.global()) { error throws -> Promise<ReceiptCredential> in
            throw parseReceiptCredentialPresentationError(error: error)
        }
    }

    public static func generateReceiptCredentialPresentation(
        receiptCredential: ReceiptCredential
    ) throws -> ReceiptCredentialPresentation {
        return try clientZKReceiptOperations().createReceiptCredentialPresentation(
            receiptCredential: receiptCredential
        )
    }

    private class func parseReceiptCredentialResponse(
        httpResponse: HTTPResponse,
        receiptCredentialRequestContext: ReceiptCredentialRequestContext,
        isValidReceiptLevelPredicate: (UInt64) -> Bool,
        logger: PrefixedLogger
    ) throws -> ReceiptCredential {
        let clientOperations = clientZKReceiptOperations()

        let httpStatusCode = httpResponse.responseStatusCode
        switch httpStatusCode {
        case 200:
            logger.info("Got valid receipt response.")
        case 204:
            logger.info("No receipt yet, payment processing.")
            throw KnownReceiptCredentialRequestError(
                errorCode: .paymentStillProcessing
            )
        default:
            throw OWSAssertionError(
                "Unexpected success status code: \(httpStatusCode)",
                logger: logger
            )
        }

        func failValidation(_ message: String) -> Error {
            owsFailDebug(message, logger: logger)
            return KnownReceiptCredentialRequestError(errorCode: .localValidationFailed)
        }

        guard
            let json = httpResponse.responseBodyJson,
            let parser = ParamParser(responseObject: json),
            let receiptCredentialResponseData = Data(
                base64Encoded: (try parser.required(key: "receiptCredentialResponse") as String)
            )
        else {
            throw failValidation("Failed to parse receipt credential response into data!")
        }

        let receiptCredentialResponse = try ReceiptCredentialResponse(
            contents: [UInt8](receiptCredentialResponseData)
        )
        let receiptCredential = try clientOperations.receiveReceiptCredential(
            receiptCredentialRequestContext: receiptCredentialRequestContext,
            receiptCredentialResponse: receiptCredentialResponse
        )

        let receiptLevel = try receiptCredential.getReceiptLevel()
        guard isValidReceiptLevelPredicate(receiptLevel) else {
            throw failValidation("Unexpected receipt credential level! \(receiptLevel)")
        }

        // Validate receipt credential expiration % 86400 == 0, per server spec
        let expiration = try receiptCredential.getReceiptExpirationTime()
        guard expiration % 86400 == 0 else {
            throw failValidation("Invalid receipt credential expiration! \(expiration)")
        }

        // Validate expiration is less than 90 days from now
        let maximumValidExpirationDate = Date().timeIntervalSince1970 + (90 * 24 * 60 * 60)
        guard TimeInterval(expiration) < maximumValidExpirationDate else {
            throw failValidation("Invalid receipt credential expiration!")
        }

        return receiptCredential
    }

    private class func parseReceiptCredentialPresentationError(
        error: Error
    ) -> Error {
        guard
            let httpStatusCode = error.httpStatusCode,
            let errorCode = DonationReceiptCredentialRequestError.ErrorCode(rawValue: httpStatusCode)
        else { return error }

        if
            case .paymentFailed = errorCode,
            let parser = ParamParser(responseObject: error.httpResponseJson),
            let chargeFailureDict: [String: Any] = try? parser.optional(key: "chargeFailure"),
            let chargeFailureCode = chargeFailureDict["code"] as? String
        {
            return KnownReceiptCredentialRequestError(
                errorCode: errorCode,
                chargeFailureCodeIfPaymentFailed: chargeFailureCode
            )
        }

        return KnownReceiptCredentialRequestError(errorCode: errorCode)
    }

    public class func redeemReceiptCredentialPresentation(
        receiptCredentialPresentation: ReceiptCredentialPresentation
    ) -> Promise<Void> {
        let expiresAtForLogging: String = {
            guard let result = try? receiptCredentialPresentation.getReceiptExpirationTime() else { return "UNKNOWN" }
            return String(result)
        }()
        Logger.info("[Donations] Redeeming receipt credential presentation. Expires at \(expiresAtForLogging)")

        let receiptCredentialPresentationData = receiptCredentialPresentation.serialize().asData

        let request = OWSRequestFactory.subscriptionRedeemReceiptCredential(
            receiptCredentialPresentation: receiptCredentialPresentationData
        )
        return firstly(on: DispatchQueue.global()) {
            SSKEnvironment.shared.networkManagerRef.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                Logger.warn("[Donations] Receipt credential presentation request failed with status code \(statusCode)")
                throw OWSRetryableSubscriptionError()
            }
        }.then(on: DispatchQueue.global()) {
            SSKEnvironment.shared.profileManagerImplRef.fetchLocalUsersProfile(authedAccount: .implicit()).asVoid()
        }
    }

    private class func generateReceiptSerial() throws -> ReceiptSerial {
        let count = ReceiptSerial.SIZE
        let bytes = Randomness.generateRandomBytes(UInt(count))
        return try ReceiptSerial(contents: [UInt8](bytes))
    }

    private class func clientZKReceiptOperations() -> ClientZkReceiptOperations {
        let params = GroupsV2Protos.serverPublicParams()
        return ClientZkReceiptOperations(serverPublicParams: params)
    }

    // 3 day heartbeat interval
    private static let heartbeatInterval: TimeInterval = 3 * kDayInterval

    // MARK: Heartbeat

    public class func redeemSubscriptionIfNecessary() async throws {
        struct CheckerStore: SubscriptionRedemptionNecessityCheckerStore {
            let donationSubscriptionManager: DonationSubscriptionManager.Type

            func subscriberId(tx: any DBReadTransaction) -> Data? {
                return donationSubscriptionManager.getSubscriberID(transaction: SDSDB.shimOnlyBridge(tx))
            }

            func getLastRedemptionNecessaryCheck(tx: any DBReadTransaction) -> Date? {
                return donationSubscriptionManager.subscriptionKVS.getDate(donationSubscriptionManager.lastSubscriptionHeartbeatKey, transaction: tx)
            }

            func setLastRedemptionNecessaryCheck(_ now: Date, tx: any DBWriteTransaction) {
                donationSubscriptionManager.subscriptionKVS.setDate(now, key: donationSubscriptionManager.lastSubscriptionHeartbeatKey, transaction: tx)
            }
        }

        let subscriptionRedemptionNecessaryChecker = SubscriptionRedemptionNecessityChecker<
            DonationReceiptCredentialRedemptionJobRecord
        >(
            checkerStore: CheckerStore(donationSubscriptionManager: self),
            dateProvider: { Date() },
            db: DependenciesBridge.shared.db,
            logger: PrefixedLogger(prefix: "[Donations]"),
            networkManager: SSKEnvironment.shared.networkManagerRef,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager
        )

        try await subscriptionRedemptionNecessaryChecker.redeemSubscriptionIfNecessary(
            parseEntitlementExpirationBlock: { accountEntitlements, subscription -> TimeInterval? in
                // TODO: If the entitlement contains something we can correlate
                // with the subscription, like the "subscription level" int
                // value, then we can more simply extract the entitlement that
                // matches the given subscription.

                // Grab only the subscription badge entitlements...
                let subscriptionBadgeEntitlements = accountEntitlements.badges.filter { entitlement in
                    return SubscriptionBadgeIds.contains(entitlement.badgeId)
                }

                // ...and return the last-expiring one. We can infer that's the
                // "current" one.
                return subscriptionBadgeEntitlements.map(\.expirationSeconds).max()
            },
            enqueueRedemptionJobBlock: { subscriberId, subscription, tx -> DonationReceiptCredentialRedemptionJobRecord in
                guard let donationPaymentProcessor = subscription.donationPaymentProcessor else {
                    throw OWSAssertionError("Unexpectedly missing donation payment processor while redeeming donation subscription!")
                }

                let (
                    receiptCredentialRequestContext,
                    receiptCredentialRequest
                ) = generateReceiptRequest()

                /// It's possible that we won't know which subscription period we
                /// last renewed for, potentially due to reinstalling. If that
                /// happens, we may or may not have already redeemed for the period
                /// we're in now.
                ///
                /// The consequence of attempting to redeem, if we'd already done so
                /// in a previous install, is that we'll get a "payment already
                /// redeemed" error from our servers. That's fine – we've clearly
                /// already done the thing we want to do, so we can always treat
                /// this like a success.
                let shouldSuppressPaymentAlreadyRedeemed = true

                return receiptCredentialRedemptionJobQueue.saveSubscriptionRedemptionJob(
                    paymentProcessor: donationPaymentProcessor,
                    paymentMethod: subscription.donationPaymentMethod,
                    receiptCredentialRequestContext: receiptCredentialRequestContext,
                    receiptCredentialRequest: receiptCredentialRequest,
                    subscriberID: subscriberId,
                    targetSubscriptionLevel: subscription.level,
                    priorSubscriptionLevel: nil,
                    isNewSubscription: false,
                    shouldSuppressPaymentAlreadyRedeemed: shouldSuppressPaymentAlreadyRedeemed,
                    tx: tx
                )
            },
            startRedemptionJobBlock: { jobRecord async throws in
                try await receiptCredentialRedemptionJobQueue.runRedemptionJob(jobRecord: jobRecord)
            }
        )
    }
}

// MARK: - State management

extension DonationSubscriptionManager {

    public static func getSubscriberID(transaction: SDSAnyReadTransaction) -> Data? {
        guard let subscriberID = subscriptionKVS.getObject(
            subscriberIDKey,
            ofClass: NSData.self,
            transaction: transaction.asV2Read
        ) as Data? else {
            return nil
        }
        return subscriberID
    }

    public static func setSubscriberID(_ subscriberID: Data?, transaction: SDSAnyWriteTransaction) {
        subscriptionKVS.setObject(subscriberID,
                                  key: subscriberIDKey,
                                  transaction: transaction.asV2Write)
    }

    public static func getSubscriberCurrencyCode(transaction: SDSAnyReadTransaction) -> String? {
        guard let subscriberCurrencyCode = subscriptionKVS.getString(
            subscriberCurrencyCodeKey,
            transaction: transaction.asV2Read
        ) else {
            return nil
        }
        return subscriberCurrencyCode
    }

    public static func setSubscriberCurrencyCode(
        _ currencyCode: Currency.Code?,
        transaction: SDSAnyWriteTransaction
    ) {
        subscriptionKVS.setObject(currencyCode,
                                  key: subscriberCurrencyCodeKey,
                                  transaction: transaction.asV2Write)
    }

    public static func userManuallyCancelledSubscription(transaction: SDSAnyReadTransaction) -> Bool {
        return subscriptionKVS.getBool(userManuallyCancelledSubscriptionKey, transaction: transaction.asV2Read) ?? false
    }

    public static func setUserManuallyCancelledSubscription(_ value: Bool, updateStorageService: Bool = false, transaction: SDSAnyWriteTransaction) {
        guard value != userManuallyCancelledSubscription(transaction: transaction) else { return }
        subscriptionKVS.setBool(value, key: userManuallyCancelledSubscriptionKey, transaction: transaction.asV2Write)
        if updateStorageService {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
        }
    }

    // MARK: -

    private static var displayBadgesOnProfileCache = AtomicBool(false, lock: .sharedGlobal)

    public static var displayBadgesOnProfile: Bool {
        displayBadgesOnProfileCache.get()
    }

    public static func displayBadgesOnProfile(transaction: SDSAnyReadTransaction) -> Bool {
        return subscriptionKVS.getBool(displayBadgesOnProfileKey, transaction: transaction.asV2Read) ?? false
    }

    public static func setDisplayBadgesOnProfile(_ value: Bool, updateStorageService: Bool = false, transaction: SDSAnyWriteTransaction) {
        guard value != displayBadgesOnProfile(transaction: transaction) else { return }
        displayBadgesOnProfileCache.set(value)
        subscriptionKVS.setBool(value, key: displayBadgesOnProfileKey, transaction: transaction.asV2Write)
        if updateStorageService {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
        }
    }

    // MARK: -

    fileprivate static func setKnownUserSubscriptionBadgeIDs(badgeIDs: [String], transaction: SDSAnyWriteTransaction) {
        subscriptionKVS.setObject(badgeIDs, key: knownUserSubscriptionBadgeIDsKey, transaction: transaction.asV2Write)
    }

    fileprivate static func knownUserSubscriptionBadgeIDs(transaction: SDSAnyReadTransaction) -> [String] {
        return subscriptionKVS.getStringArray(knownUserSubscriptionBadgeIDsKey, transaction: transaction.asV2Read) ?? []
    }

    fileprivate static func setKnownUserBoostBadgeIDs(badgeIDs: [String], transaction: SDSAnyWriteTransaction) {
        subscriptionKVS.setObject(badgeIDs, key: knownUserBoostBadgeIDsKey, transaction: transaction.asV2Write)
    }

    fileprivate static func knownUserBoostBadgeIDs(transaction: SDSAnyReadTransaction) -> [String] {
        return subscriptionKVS.getStringArray(knownUserBoostBadgeIDsKey, transaction: transaction.asV2Read) ?? []
    }

    fileprivate static func setKnownUserGiftBadgeIDs(badgeIDs: [String], transaction: SDSAnyWriteTransaction) {
        subscriptionKVS.setObject(badgeIDs, key: knownUserGiftBadgeIDsKey, transaction: transaction.asV2Write)
    }

    fileprivate static func knownUserGiftBadgeIDs(transaction: SDSAnyReadTransaction) -> [String] {
        return subscriptionKVS.getStringArray(knownUserGiftBadgeIDsKey, transaction: transaction.asV2Read) ?? []
    }

    fileprivate static func setMostRecentlyExpiredBadgeID(badgeID: String?, transaction: SDSAnyWriteTransaction) {
        guard let badgeID = badgeID else {
            subscriptionKVS.removeValue(forKey: mostRecentlyExpiredBadgeIDKey, transaction: transaction.asV2Write)
            return
        }

        subscriptionKVS.setString(badgeID, key: mostRecentlyExpiredBadgeIDKey, transaction: transaction.asV2Write)

    }

    public static func mostRecentlyExpiredBadgeID(transaction: SDSAnyReadTransaction) -> String? {
        subscriptionKVS.getString(mostRecentlyExpiredBadgeIDKey, transaction: transaction.asV2Read)
    }

    public static func clearMostRecentlyExpiredBadgeIDWithSneakyTransaction() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.setMostRecentlyExpiredBadgeID(badgeID: nil, transaction: transaction)
        }
    }

    fileprivate static func setMostRecentlyExpiredGiftBadgeID(badgeID: String?, transaction: SDSAnyWriteTransaction) {
        if let badgeID = badgeID {
            subscriptionKVS.setString(badgeID, key: mostRecentlyExpiredGiftBadgeIDKey, transaction: transaction.asV2Write)
        } else {
            subscriptionKVS.removeValue(forKey: mostRecentlyExpiredGiftBadgeIDKey, transaction: transaction.asV2Write)
        }
        transaction.addAsyncCompletionOnMain {
            NotificationCenter.default.post(name: .hasExpiredGiftBadgeDidChangeNotification, object: nil)
        }
    }

    public static func mostRecentlyExpiredGiftBadgeID(transaction: SDSAnyReadTransaction) -> String? {
        subscriptionKVS.getString(mostRecentlyExpiredGiftBadgeIDKey, transaction: transaction.asV2Read)
    }

    public static func clearMostRecentlyExpiredGiftBadgeIDWithSneakyTransaction() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.setMostRecentlyExpiredGiftBadgeID(badgeID: nil, transaction: transaction)
        }
    }

    public static func setShowExpirySheetOnHomeScreenKey(show: Bool, transaction: SDSAnyWriteTransaction) {
        Logger.info("\(show)")
        subscriptionKVS.setBool(show, key: showExpirySheetOnHomeScreenKey, transaction: transaction.asV2Write)
    }

    public static func showExpirySheetOnHomeScreenKey(transaction: SDSAnyReadTransaction) -> Bool {
        return subscriptionKVS.getBool(showExpirySheetOnHomeScreenKey, transaction: transaction.asV2Read) ?? false
    }

    public static func setMostRecentSubscriptionPaymentMethod(
        paymentMethod: DonationPaymentMethod?,
        transaction: SDSAnyWriteTransaction
    ) {
        subscriptionKVS.setString(paymentMethod?.rawValue, key: mostRecentSubscriptionPaymentMethodKey, transaction: transaction.asV2Write)
    }

    public static func getMostRecentSubscriptionPaymentMethod(transaction: SDSAnyReadTransaction) -> DonationPaymentMethod? {
        guard let paymentMethodString = subscriptionKVS.getString(mostRecentSubscriptionPaymentMethodKey, transaction: transaction.asV2Read) else {
            return nil
        }

        guard let paymentMethod = DonationPaymentMethod(rawValue: paymentMethodString) else {
            owsFailBeta("Unexpected payment method string: \(paymentMethodString)")
            return nil
        }

        return paymentMethod
    }
}

// MARK: -

public class OWSRetryableSubscriptionError: NSObject, CustomNSError, IsRetryableProvider {
    @objc
    public static var asNSError: NSError {
        OWSRetryableSubscriptionError() as Error as NSError
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { true }
}

extension DonationSubscriptionManager {

    private static var cachedBadges = [OneTimeBadgeLevel: CachedBadge]()

    public class func getCachedBadge(level: OneTimeBadgeLevel) -> CachedBadge {
        if let cachedBadge = self.cachedBadges[level] {
            return cachedBadge
        }
        let cachedBadge = CachedBadge(level: level)
        self.cachedBadges[level] = cachedBadge
        return cachedBadge
    }

    public class func getBoostBadge() -> Promise<ProfileBadge> {
        firstly {
            getOneTimeBadge(level: .boostBadge)
        }.map { profileBadge in
            guard let profileBadge = profileBadge else {
                owsFail("No badge for this level was found")
            }
            return profileBadge
        }
    }

    public class func getOneTimeBadge(level: OneTimeBadgeLevel) -> Promise<ProfileBadge?> {
        firstly { () -> Promise<DonationConfiguration> in
            fetchDonationConfiguration()
        }.map { donationConfiguration -> ProfileBadge? in
            switch level {
            case .boostBadge:
                return donationConfiguration.boost.badge
            case .giftBadge(let level):
                guard donationConfiguration.gift.level == level.rawLevel else {
                    Logger.warn("Requested gift badge with level \(level), which did not match known gift badge with level \(donationConfiguration.gift.level)")
                    return nil
                }

                return donationConfiguration.gift.badge
            }
        }
    }

    public class func getSubscriptionBadge(subscriptionLevel levelRawValue: UInt) -> Promise<ProfileBadge> {
        firstly { () -> Promise<DonationConfiguration> in
            fetchDonationConfiguration()
        }.map { donationConfiguration throws -> ProfileBadge in
            guard let matchingLevel = donationConfiguration.subscription.levels.first(where: {
                $0.level == levelRawValue
            }) else {
                throw OWSAssertionError("Missing requested subscription level!")
            }

            return matchingLevel.badge
        }
    }
}

// MARK: -

extension DonationSubscriptionManager {
    public static func reconcileBadgeStates(transaction: SDSAnyWriteTransaction) {
        let currentBadges = SSKEnvironment.shared.profileManagerImplRef.localUserProfile.badges

        let currentSubscriberBadgeIDs = currentBadges.compactMap { (badge: OWSUserProfileBadgeInfo) -> String? in
            guard SubscriptionBadgeIds.contains(badge.badgeId) else { return nil }
            return badge.badgeId
        }

        let currentBoostBadgeIDs = currentBadges.compactMap { (badge: OWSUserProfileBadgeInfo) -> String? in
            guard BoostBadgeIds.contains(badge.badgeId) else { return nil }
            return badge.badgeId
        }

        let currentGiftBadgeIDs = currentBadges.compactMap { (badge: OWSUserProfileBadgeInfo) -> String? in
            guard GiftBadgeIds.contains(badge.badgeId) else { return nil }
            return badge.badgeId
        }

        // Read existing values
        let persistedSubscriberBadgeIDs = Self.knownUserSubscriptionBadgeIDs(transaction: transaction)
        let persistedBoostBadgeIDs = Self.knownUserBoostBadgeIDs(transaction: transaction)
        let persistedGiftBadgeIDs = Self.knownUserGiftBadgeIDs(transaction: transaction)
        let oldExpiredGiftBadgeID = Self.mostRecentlyExpiredGiftBadgeID(transaction: transaction)
        var expiringBadgeId = Self.mostRecentlyExpiredBadgeID(transaction: transaction)
        var userManuallyCancelled = Self.userManuallyCancelledSubscription(transaction: transaction)
        var showExpiryOnHomeScreen = Self.showExpirySheetOnHomeScreenKey(transaction: transaction)
        var displayBadgesOnProfile = Self.displayBadgesOnProfile(transaction: transaction)

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

        let newSubscriberBadgeIds = Set(currentSubscriberBadgeIDs).subtracting(persistedSubscriberBadgeIDs)
        if !newSubscriberBadgeIds.isEmpty {
            Logger.info("Learned of \(newSubscriberBadgeIds.count) new subscriber badge ids: \(newSubscriberBadgeIds)")
        }

        let expiredSubscriberBadgeIds = Set(persistedSubscriberBadgeIDs).subtracting(currentSubscriberBadgeIDs)
        if !expiredSubscriberBadgeIds.isEmpty {
            Logger.info("Learned of \(expiredSubscriberBadgeIds.count) newly expired subscriber badge ids: \(expiredSubscriberBadgeIds)")
        }

        let newBoostBadgeIds = Set(currentBoostBadgeIDs).subtracting(persistedBoostBadgeIDs)
        if !newBoostBadgeIds.isEmpty {
            Logger.info("Learned of \(newBoostBadgeIds.count) new boost badge ids: \(newBoostBadgeIds)")
        }

        let expiredBoostBadgeIds = Set(persistedBoostBadgeIDs).subtracting(currentBoostBadgeIDs)
        if !expiredBoostBadgeIds.isEmpty {
            Logger.info("Learned of \(expiredBoostBadgeIds.count) newly expired boost badge ids: \(expiredBoostBadgeIds)")
        }

        let newGiftBadgeIds = Set(currentGiftBadgeIDs).subtracting(persistedGiftBadgeIDs)
        if !newGiftBadgeIds.isEmpty {
            Logger.info("Learned of \(newGiftBadgeIds.count) new gift badge ids: \(newGiftBadgeIds)")
        }

        let expiredGiftBadgeIds = Set(persistedGiftBadgeIDs).subtracting(currentGiftBadgeIDs)
        if !expiredGiftBadgeIds.isEmpty {
            Logger.info("Learned of \(expiredGiftBadgeIds.count) newly expired gift badge ids: \(expiredGiftBadgeIds)")
        }

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

        let newExpiredGiftBadgeID: String?
        if currentGiftBadgeIDs.isEmpty {
            // If you don't have any remaining gift badges, show (a) the badge that
            // *just* expired, (b) a gift that expired during a previous call to
            // reconcile badge states, or (c) nothing. Most users will fall into (c).
            newExpiredGiftBadgeID = expiredGiftBadgeIds.first ?? oldExpiredGiftBadgeID ?? nil
        } else {
            // If you have a gift badge, don't show any expiration about gift badges.
            // Perhaps you redeemed another gift before we displayed the sheet.
            newExpiredGiftBadgeID = nil
        }

        Logger.info("""
        Reconciled badge state:
            Subscriber Badge Ids: \(currentSubscriberBadgeIDs)
            Boost Badge Ids: \(currentBoostBadgeIDs)
            Gift Badge Ids: \(currentGiftBadgeIDs)
            Most Recently Expired Badge Id: \(expiringBadgeId ?? "nil")
            Expired Gift Badge Id: \(newExpiredGiftBadgeID ?? "nil")
            Show Expiry On Home Screen: \(showExpiryOnHomeScreen)
            User Manually Cancelled Subscription: \(userManuallyCancelled)
            Display Badges On Profile: \(displayBadgesOnProfile)
        """)

        // Persist new values
        Self.setKnownUserSubscriptionBadgeIDs(badgeIDs: currentSubscriberBadgeIDs, transaction: transaction)
        Self.setKnownUserBoostBadgeIDs(badgeIDs: currentBoostBadgeIDs, transaction: transaction)
        Self.setKnownUserGiftBadgeIDs(badgeIDs: currentGiftBadgeIDs, transaction: transaction)
        Self.setMostRecentlyExpiredGiftBadgeID(badgeID: newExpiredGiftBadgeID, transaction: transaction)
        Self.setMostRecentlyExpiredBadgeID(badgeID: expiringBadgeId, transaction: transaction)
        Self.setShowExpirySheetOnHomeScreenKey(show: showExpiryOnHomeScreen, transaction: transaction)
        Self.setUserManuallyCancelledSubscription(userManuallyCancelled, transaction: transaction)
        Self.setDisplayBadgesOnProfile(displayBadgesOnProfile, transaction: transaction)
    }
}

// MARK: -

extension DonationSubscriptionManager {

    public enum RecurringSubscriptionPaymentType {
        case applePay(paymentMethodId: String)
        case creditOrDebitCard(paymentMethodId: String)
        case paypal(paymentMethodId: String)
        case sepa(paymentMethodId: String)
        case ideal(setupIntentId: String)

        public var paymentProcessor: DonationPaymentProcessor {
            switch self {
            case .applePay, .ideal, .sepa, .creditOrDebitCard:
                return .stripe
            case .paypal:
                return .braintree
            }
        }

        public var paymentMethod: DonationPaymentMethod {
            switch self {
            case .applePay: return .applePay
            case .creditOrDebitCard: return .creditOrDebitCard
            case .paypal: return .paypal
            case .sepa: return .sepa
            case .ideal: return .ideal
            }
        }
    }
}
