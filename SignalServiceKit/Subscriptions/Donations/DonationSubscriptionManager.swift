//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient
import PassKit

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

// MARK: -

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
public class DonationSubscriptionManager {

    /// - Note
    /// This collection name is reused by other subscription-related stores. For
    /// example, see ``DonationReceiptCredentialResultStore``.
    private let subscriptionKVS = KeyValueStore(collection: "SubscriptionKeyValueStore")

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

    private let db: any DB
    private let donationPermitFetcher: DonationPermitFetcher
    private let donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore
    private let networkManager: NetworkManager
    private let profileManager: ProfileManager
    private let storageServiceManager: StorageServiceManager
    private let subscriptionConfigManager: SubscriptionConfigManager
    private let tsAccountManager: TSAccountManager

    /// Lazily accessed to avoid dealing with a circular dependency.
    private var receiptCredentialRedemptionJobQueue: DonationReceiptCredentialRedemptionJobQueue {
        SSKEnvironment.shared.donationReceiptCredentialRedemptionJobQueue
    }

    init(
        db: any DB,
        donationPermitFetcher: DonationPermitFetcher,
        donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore,
        networkManager: NetworkManager,
        profileManager: ProfileManager,
        storageServiceManager: StorageServiceManager,
        subscriptionConfigManager: SubscriptionConfigManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.db = db
        self.donationPermitFetcher = donationPermitFetcher
        self.donationReceiptCredentialResultStore = donationReceiptCredentialResultStore
        self.networkManager = networkManager
        self.profileManager = profileManager
        self.storageServiceManager = storageServiceManager
        self.subscriptionConfigManager = subscriptionConfigManager
        self.tsAccountManager = tsAccountManager
    }

    // MARK: -

    public func currentProfileSubscriptionBadges(tx: DBReadTransaction) -> [OWSUserProfileBadgeInfo] {
        let localProfile = profileManager.localUserProfile(tx: tx)
        return (localProfile?.badges ?? []).filter { SubscriptionBadgeIds.contains($0.badgeId) }
    }

    /// A low-overhead, synchronous check for whether we *probably* have a
    /// current donation subscription. Callers who need to know precise details
    /// about our subscription should use ``SubscriptionFetcher``.
    public func probablyHasCurrentSubscription(tx: DBReadTransaction) -> Bool {
        return !currentProfileSubscriptionBadges(tx: tx).isEmpty
    }

    // MARK: -

    /// Perform processor-agnostic steps to set up a new subscription, before
    /// payment has been authorized.
    ///
    /// - Returns: The new subscriber ID.
    public func prepareNewSubscription(currencyCode: Currency.Code) async throws -> Data {
        Logger.info("[Donations] Setting up new subscription")
        let subscriberID = try await setupNewSubscriberID()
        Logger.info("[Donations] Caching params after setting up new subscription")

        await db.awaitableWrite { tx in
            self.setUserManuallyCancelledSubscription(false, tx: tx)
            self.setSubscriberID(subscriberID, tx: tx)
            self.setSubscriberCurrencyCode(currencyCode, tx: tx)
            self.setMostRecentlyExpiredBadgeID(badgeID: nil, tx: tx)
            self.setShowExpirySheetOnHomeScreenKey(show: false, tx: tx)
        }

        storageServiceManager.recordPendingLocalAccountUpdates()

        return subscriberID
    }

    /// Finalize a new subscription, after payment has been authorized with the
    /// given processor.
    public func finalizeNewSubscription(
        forSubscriberId subscriberId: Data,
        paymentType: RecurringSubscriptionPaymentType,
        subscription: DonationSubscriptionLevel,
        currencyCode: Currency.Code,
    ) async throws -> Subscription {
        Logger.info("[Donations] Setting default payment method on service")

        switch paymentType {
        case let .ideal(setupIntentId):
            try await setDefaultIDEALPaymentMethod(
                for: subscriberId,
                setupIntentId: setupIntentId,
            )
        case
            .applePay(let paymentMethodId),
            .creditOrDebitCard(let paymentMethodId),
            .paypal(let paymentMethodId),
            .sepa(let paymentMethodId):
            try await setDefaultPaymentMethod(
                for: subscriberId,
                using: paymentType.paymentProcessor,
                paymentMethodId: paymentMethodId,
            )
        }

        Logger.info("[Donations] Selecting subscription level on service")

        await db.awaitableWrite { tx in
            self.setMostRecentSubscriptionPaymentMethod(
                paymentMethod: paymentType.paymentMethod,
                tx: tx,
            )
        }

        return try await setSubscription(for: subscriberId, subscription: subscription, currencyCode: currencyCode)
    }

    /// Update the subscription level for the given subscriber ID.
    public func updateSubscriptionLevel(
        for subscriberID: Data,
        to subscription: DonationSubscriptionLevel,
        currencyCode: Currency.Code,
    ) async throws -> Subscription {
        Logger.info("[Donations] Updating subscription level")

        return try await setSubscription(
            for: subscriberID,
            subscription: subscription,
            currencyCode: currencyCode,
        )
    }

    /// Cancel a subscription for the given subscriber ID.
    public func cancelSubscription(for subscriberID: Data) async throws {
        Logger.info("[Donations] Cancelling subscription")

        let request = OWSRequestFactory.deleteSubscriberID(subscriberID)
        let response = try await networkManager.asyncRequest(request, retryPolicy: .hopefullyRecoverable)
        if response.responseStatusCode != 200, response.responseStatusCode != 404 {
            throw OWSAssertionError("Got bad response code \(response.responseStatusCode).")
        }
        Logger.info("[Donations] Deleted remote subscription.")

        await db.awaitableWrite { tx in
            self.setSubscriberID(nil, tx: tx)
            self.setSubscriberCurrencyCode(nil, tx: tx)
            self.setMostRecentSubscriptionPaymentMethod(paymentMethod: nil, tx: tx)
            self.setUserManuallyCancelledSubscription(true, tx: tx)

            self.donationReceiptCredentialResultStore.clearRedemptionSuccessForAnyRecurringSubscription(tx: tx)
            self.donationReceiptCredentialResultStore.clearRequestErrorForAnyRecurringSubscription(tx: tx)
        }

        storageServiceManager.recordPendingLocalAccountUpdates()
        Logger.info("[Donations] Deleted local subscription.")
    }

    /// Generate and register an ID for a new subscriber.
    ///
    /// - Returns the new subscriber ID.
    private func setupNewSubscriberID() async throws -> Data {
        Logger.info("[Donations] Setting up new subscriber ID")

        let newSubscriberID = Randomness.generateRandomBytes(UInt(32))

        let donationPermit = try await donationPermitFetcher.fetchDonationPermit()
        let request = OWSRequestFactory.setSubscriberID(
            newSubscriberID,
            donationPermit: donationPermit,
        )

        let response = try await networkManager
            .asyncRequest(request, retryPolicy: .hopefullyRecoverable)

        let statusCode = response.responseStatusCode
        if statusCode != 200 {
            throw OWSAssertionError("Got bad response code \(statusCode).")
        }

        return newSubscriberID
    }

    private func setDefaultPaymentMethod(
        for subscriberId: Data,
        using processor: DonationPaymentProcessor,
        paymentMethodId: String,
    ) async throws {
        let request = OWSRequestFactory.subscriptionSetDefaultPaymentMethod(
            subscriberId: subscriberId,
            processor: processor.rawValue,
            paymentMethodId: paymentMethodId,
        )
        let response = try await networkManager
            .asyncRequest(request, retryPolicy: .hopefullyRecoverable)
        let statusCode = response.responseStatusCode
        if statusCode != 200 {
            throw OWSAssertionError("Got bad response code \(statusCode).")
        }
    }

    private func setDefaultIDEALPaymentMethod(
        for subscriberId: Data,
        setupIntentId: String,
    ) async throws {
        let request = OWSRequestFactory.subscriptionSetDefaultIDEALPaymentMethod(
            subscriberId: subscriberId,
            setupIntentId: setupIntentId,
        )

        let response = try await networkManager
            .asyncRequest(request, retryPolicy: .hopefullyRecoverable)
        let statusCode = response.responseStatusCode
        if statusCode != 200 {
            throw OWSAssertionError("Got bad response code \(statusCode).")
        }
    }

    /// Set the current subscription to the given level and currency.
    ///
    /// - Returns
    /// The updated subscription.
    private func setSubscription(
        for subscriberID: Data,
        subscription: DonationSubscriptionLevel,
        currencyCode: Currency.Code,
    ) async throws -> Subscription {
        let key = Randomness.generateRandomBytes(UInt(32)).asBase64Url
        let request = OWSRequestFactory.subscriptionSetSubscriptionLevelRequest(
            subscriberID: subscriberID,
            level: subscription.level,
            currency: currencyCode,
            idempotencyKey: key,
        )
        let response = try await networkManager.asyncRequest(request, retryPolicy: .hopefullyRecoverable)
        let statusCode = response.responseStatusCode
        if statusCode != 200 {
            throw OWSAssertionError("Got bad response code \(statusCode).")
        }

        guard
            let subscription = try await SubscriptionFetcher(
                networkManager: networkManager,
                retryPolicy: .hopefullyRecoverable,
            )
            .fetch(subscriberID: subscriberID)
        else {
            throw OWSAssertionError("Failed to fetch valid subscription object after setSubscription")
        }

        await db.awaitableWrite { tx in
            self.setSubscriberCurrencyCode(currencyCode, tx: tx)
        }

        storageServiceManager.recordPendingLocalAccountUpdates()

        return subscription
    }

    // MARK: -

    public func requestAndRedeemReceipt(
        subscriberId: Data,
        subscriptionLevel: UInt,
        priorSubscriptionLevel: UInt?,
        paymentProcessor: DonationPaymentProcessor,
        paymentMethod: DonationPaymentMethod?,
        isNewSubscription: Bool,
    ) async throws {
        let (
            receiptCredentialRequestContext,
            receiptCredentialRequest,
        ) = ReceiptCredentialManager.generateReceiptRequest()

        let redemptionJobRecord = await db.awaitableWrite { tx in
            return self.receiptCredentialRedemptionJobQueue.saveSubscriptionRedemptionJob(
                paymentProcessor: paymentProcessor,
                paymentMethod: paymentMethod,
                receiptCredentialRequestContext: receiptCredentialRequestContext,
                receiptCredentialRequest: receiptCredentialRequest,
                subscriberID: subscriberId,
                targetSubscriptionLevel: subscriptionLevel,
                priorSubscriptionLevel: priorSubscriptionLevel,
                isNewSubscription: isNewSubscription,
                tx: tx,
            )
        }

        try await receiptCredentialRedemptionJobQueue.runRedemptionJob(
            jobRecord: redemptionJobRecord,
        )
    }

    public func requestAndRedeemReceipt(
        boostPaymentIntentId: String,
        amount: FiatMoney,
        paymentProcessor: DonationPaymentProcessor,
        paymentMethod: DonationPaymentMethod,
    ) async throws {
        let (
            receiptCredentialRequestContext,
            receiptCredentialRequest,
        ) = ReceiptCredentialManager.generateReceiptRequest()

        let redemptionJobRecord = await db.awaitableWrite { tx in
            return self.receiptCredentialRedemptionJobQueue.saveBoostRedemptionJob(
                amount: amount,
                paymentProcessor: paymentProcessor,
                paymentMethod: paymentMethod,
                receiptCredentialRequestContext: receiptCredentialRequestContext,
                receiptCredentialRequest: receiptCredentialRequest,
                boostPaymentIntentID: boostPaymentIntentId,
                tx: tx,
            )
        }

        try await receiptCredentialRedemptionJobQueue.runRedemptionJob(
            jobRecord: redemptionJobRecord,
        )
    }

    public func redeemReceiptCredentialPresentation(
        receiptCredentialPresentation: ReceiptCredentialPresentation,
    ) async throws {
        let expiresAtForLogging: String = {
            guard let result = try? receiptCredentialPresentation.getReceiptExpirationTime() else { return "UNKNOWN" }
            return String(result)
        }()
        Logger.info("[Donations] Redeeming receipt credential presentation. Expires at \(expiresAtForLogging)")

        let receiptCredentialPresentationData = receiptCredentialPresentation.serialize()
        let request = OWSRequestFactory.subscriptionRedeemReceiptCredential(
            receiptCredentialPresentation: receiptCredentialPresentationData,
            displayBadgesOnProfile: db.read { tx in displayBadgesOnProfile(tx: tx) },
        )
        let response = try await networkManager.asyncRequest(request)
        let statusCode = response.responseStatusCode
        if statusCode != 200 {
            throw OWSAssertionError("[Donations] Receipt credential presentation request failed with status code \(statusCode)")
        }
        _ = try await profileManager.fetchLocalUsersProfile(authedAccount: .implicit())
    }

    // MARK: Heartbeat

    public func redeemSubscriptionIfNecessary() async throws {
        struct CheckerStore: SubscriptionRedemptionNecessityCheckerStore {
            let donationSubscriptionManager: DonationSubscriptionManager

            func subscriberId(tx: DBReadTransaction) -> Data? {
                return donationSubscriptionManager.getSubscriberID(tx: tx)
            }

            func getLastRedemptionNecessaryCheck(tx: DBReadTransaction) -> Date? {
                return donationSubscriptionManager.subscriptionKVS.getDate(DonationSubscriptionManager.lastSubscriptionHeartbeatKey, transaction: tx)
            }

            func setLastRedemptionNecessaryCheck(_ now: Date, tx: DBWriteTransaction) {
                donationSubscriptionManager.subscriptionKVS.setDate(now, key: DonationSubscriptionManager.lastSubscriptionHeartbeatKey, transaction: tx)
            }
        }

        let logger = PrefixedLogger(prefix: "[Donations]")

        let subscriptionRedemptionNecessityChecker = SubscriptionRedemptionNecessityChecker<
            DonationReceiptCredentialRedemptionJobRecord,
        >(
            checkerStore: CheckerStore(donationSubscriptionManager: self),
            dateProvider: { Date() },
            db: db,
            donationPermitFetcher: donationPermitFetcher,
            logger: logger,
            networkManager: networkManager,
            tsAccountManager: tsAccountManager,
        )

        _ = try await subscriptionRedemptionNecessityChecker.redeemSubscriptionIfNecessary(
            fetchSubscriptionBlock: { db, subscriptionFetcher -> (subscriberID: Data, subscription: Subscription)? in
                if
                    let subscriberID = db.read(block: { self.getSubscriberID(tx: $0) }),
                    let subscription = try await subscriptionFetcher.fetch(subscriberID: subscriberID)
                {
                    return (subscriberID, subscription)
                }

                return nil
            },
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
            saveRedemptionJobBlock: { subscriberId, subscription, tx -> DonationReceiptCredentialRedemptionJobRecord? in
                if
                    self.receiptCredentialRedemptionJobQueue.subscriptionJobExists(
                        subscriberID: subscriberId,
                        tx: tx,
                    )
                {
                    // A redemption job is already enqueued for this subscription!
                    // This can happen if a previously-enqueued job hasn't
                    // finished but the NecessityChecker decided it should run,
                    // maybe because it's been >3d.
                    //
                    // That's not implausible, for example for SEPA donations in
                    // which a payment could be "processing" for days (and an
                    // enqueued redemption job stalled during that time).
                    //
                    // Since the jobs persist state (such as "redemption success
                    // or error"), avoid enqueuing multiple that might step on
                    // each other.
                    logger.warn("Not enqueuing new subscription redemption job: one already exists for this subscriber ID!")
                    return nil
                }

                guard let donationPaymentProcessor = subscription.donationPaymentProcessor else {
                    throw OWSAssertionError(
                        "Unexpectedly missing donation payment processor while redeeming donation subscription!",
                        logger: logger,
                    )
                }

                let (
                    receiptCredentialRequestContext,
                    receiptCredentialRequest,
                ) = ReceiptCredentialManager.generateReceiptRequest()

                return self.receiptCredentialRedemptionJobQueue.saveSubscriptionRedemptionJob(
                    paymentProcessor: donationPaymentProcessor,
                    paymentMethod: subscription.donationPaymentMethod,
                    receiptCredentialRequestContext: receiptCredentialRequestContext,
                    receiptCredentialRequest: receiptCredentialRequest,
                    subscriberID: subscriberId,
                    targetSubscriptionLevel: subscription.level,
                    priorSubscriptionLevel: nil,
                    isNewSubscription: false,
                    tx: tx,
                )
            },
            startRedemptionJobBlock: { jobRecord async throws in
                try await self.receiptCredentialRedemptionJobQueue.runRedemptionJob(jobRecord: jobRecord)
            },
        )
    }

    // MARK: - State management

    public func getSubscriberID(tx: DBReadTransaction) -> Data? {
        guard
            let subscriberID = subscriptionKVS.getObject(
                Self.subscriberIDKey,
                ofClass: NSData.self,
                transaction: tx,
            ) as Data?
        else {
            return nil
        }
        return subscriberID
    }

    public func setSubscriberID(_ subscriberID: Data?, tx: DBWriteTransaction) {
        subscriptionKVS.setObject(
            subscriberID as NSData?,
            key: Self.subscriberIDKey,
            transaction: tx,
        )
    }

    public func getSubscriberCurrencyCode(tx: DBReadTransaction) -> String? {
        guard
            let subscriberCurrencyCode = subscriptionKVS.getString(
                Self.subscriberCurrencyCodeKey,
                transaction: tx,
            )
        else {
            return nil
        }
        return subscriberCurrencyCode
    }

    public func setSubscriberCurrencyCode(
        _ currencyCode: Currency.Code?,
        tx: DBWriteTransaction,
    ) {
        subscriptionKVS.setString(
            currencyCode,
            key: Self.subscriberCurrencyCodeKey,
            transaction: tx,
        )
    }

    public func userManuallyCancelledSubscription(tx: DBReadTransaction) -> Bool {
        return subscriptionKVS.getBool(Self.userManuallyCancelledSubscriptionKey, transaction: tx) ?? false
    }

    public func setUserManuallyCancelledSubscription(_ value: Bool, updateStorageService: Bool = false, tx: DBWriteTransaction) {
        guard value != userManuallyCancelledSubscription(tx: tx) else { return }
        subscriptionKVS.setBool(value, key: Self.userManuallyCancelledSubscriptionKey, transaction: tx)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    // MARK: -

    public func displayBadgesOnProfile(tx: DBReadTransaction) -> Bool {
        return subscriptionKVS.getBool(Self.displayBadgesOnProfileKey, transaction: tx) ?? false
    }

    public func setDisplayBadgesOnProfile(_ value: Bool, updateStorageService: Bool = false, tx: DBWriteTransaction) {
        guard value != displayBadgesOnProfile(tx: tx) else { return }
        subscriptionKVS.setBool(value, key: Self.displayBadgesOnProfileKey, transaction: tx)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    // MARK: -

    private func setKnownUserSubscriptionBadgeIDs(badgeIDs: [String], tx: DBWriteTransaction) {
        subscriptionKVS.setStringArray(badgeIDs, key: Self.knownUserSubscriptionBadgeIDsKey, transaction: tx)
    }

    private func knownUserSubscriptionBadgeIDs(tx: DBReadTransaction) -> [String] {
        return subscriptionKVS.getStringArray(Self.knownUserSubscriptionBadgeIDsKey, transaction: tx) ?? []
    }

    private func setKnownUserBoostBadgeIDs(badgeIDs: [String], tx: DBWriteTransaction) {
        subscriptionKVS.setStringArray(badgeIDs, key: Self.knownUserBoostBadgeIDsKey, transaction: tx)
    }

    private func knownUserBoostBadgeIDs(tx: DBReadTransaction) -> [String] {
        return subscriptionKVS.getStringArray(Self.knownUserBoostBadgeIDsKey, transaction: tx) ?? []
    }

    private func setKnownUserGiftBadgeIDs(badgeIDs: [String], tx: DBWriteTransaction) {
        subscriptionKVS.setStringArray(badgeIDs, key: Self.knownUserGiftBadgeIDsKey, transaction: tx)
    }

    private func knownUserGiftBadgeIDs(tx: DBReadTransaction) -> [String] {
        return subscriptionKVS.getStringArray(Self.knownUserGiftBadgeIDsKey, transaction: tx) ?? []
    }

    private func setMostRecentlyExpiredBadgeID(badgeID: String?, tx: DBWriteTransaction) {
        guard let badgeID else {
            subscriptionKVS.removeValue(forKey: Self.mostRecentlyExpiredBadgeIDKey, transaction: tx)
            return
        }

        subscriptionKVS.setString(badgeID, key: Self.mostRecentlyExpiredBadgeIDKey, transaction: tx)

    }

    public func mostRecentlyExpiredBadgeID(tx: DBReadTransaction) -> String? {
        subscriptionKVS.getString(Self.mostRecentlyExpiredBadgeIDKey, transaction: tx)
    }

    public func clearMostRecentlyExpiredBadgeIDWithSneakyTransaction() {
        db.write { tx in
            self.setMostRecentlyExpiredBadgeID(badgeID: nil, tx: tx)
        }
    }

    private func setMostRecentlyExpiredGiftBadgeID(badgeID: String?, tx: DBWriteTransaction) {
        if let badgeID {
            subscriptionKVS.setString(badgeID, key: Self.mostRecentlyExpiredGiftBadgeIDKey, transaction: tx)
        } else {
            subscriptionKVS.removeValue(forKey: Self.mostRecentlyExpiredGiftBadgeIDKey, transaction: tx)
        }
        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: .hasExpiredGiftBadgeDidChangeNotification, object: nil)
        }
    }

    public func mostRecentlyExpiredGiftBadgeID(tx: DBReadTransaction) -> String? {
        subscriptionKVS.getString(Self.mostRecentlyExpiredGiftBadgeIDKey, transaction: tx)
    }

    public func clearMostRecentlyExpiredGiftBadgeIDWithSneakyTransaction() {
        db.write { tx in
            self.setMostRecentlyExpiredGiftBadgeID(badgeID: nil, tx: tx)
        }
    }

    public func setShowExpirySheetOnHomeScreenKey(show: Bool, tx: DBWriteTransaction) {
        subscriptionKVS.setBool(show, key: Self.showExpirySheetOnHomeScreenKey, transaction: tx)
    }

    public func showExpirySheetOnHomeScreenKey(tx: DBReadTransaction) -> Bool {
        return subscriptionKVS.getBool(Self.showExpirySheetOnHomeScreenKey, transaction: tx) ?? false
    }

    public func setMostRecentSubscriptionPaymentMethod(
        paymentMethod: DonationPaymentMethod?,
        tx: DBWriteTransaction,
    ) {
        subscriptionKVS.setString(paymentMethod?.rawValue, key: Self.mostRecentSubscriptionPaymentMethodKey, transaction: tx)
    }

    public func getMostRecentSubscriptionPaymentMethod(tx: DBReadTransaction) -> DonationPaymentMethod? {
        guard let paymentMethodString = subscriptionKVS.getString(Self.mostRecentSubscriptionPaymentMethodKey, transaction: tx) else {
            return nil
        }

        guard let paymentMethod = DonationPaymentMethod(rawValue: paymentMethodString) else {
            owsFailBeta("Unexpected payment method string: \(paymentMethodString)")
            return nil
        }

        return paymentMethod
    }

    // MARK: -

    private static let cachedBadges = AtomicValue<[OneTimeBadgeLevel: CachedBadge]>([:], lock: .init())

    public func getCachedBadge(level: OneTimeBadgeLevel) -> CachedBadge {
        return Self.cachedBadges.update {
            if let cachedBadge = $0[level] {
                return cachedBadge
            }
            let cachedBadge = CachedBadge(level: level)
            $0[level] = cachedBadge
            return cachedBadge
        }
    }

    public func getBoostBadge() async throws -> ProfileBadge {
        let profileBadge = try await getOneTimeBadge(level: .boostBadge)
        guard let profileBadge else {
            owsFail("No badge for this level was found")
        }
        return profileBadge
    }

    public func getOneTimeBadge(level: OneTimeBadgeLevel) async throws -> ProfileBadge? {
        let donationConfiguration = try await fetchDonationConfiguration()
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

    public func getSubscriptionBadge(subscriptionLevel levelRawValue: UInt) async throws -> ProfileBadge {
        let donationConfiguration = try await fetchDonationConfiguration()
        guard
            let matchingLevel = donationConfiguration.subscription.levels.first(where: {
                $0.level == levelRawValue
            })
        else {
            throw OWSAssertionError("Missing requested subscription level!")
        }

        return matchingLevel.badge
    }

    public func fetchDonationConfiguration() async throws -> DonationSubscriptionConfiguration {
        return try await subscriptionConfigManager.donationConfiguration()
    }

    // MARK: -

    public func reconcileBadgeStates(
        currentLocalUserProfile: OWSUserProfile,
        tx: DBWriteTransaction,
    ) {
        let currentBadges = currentLocalUserProfile.badges

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
        let persistedSubscriberBadgeIDs = self.knownUserSubscriptionBadgeIDs(tx: tx)
        let persistedBoostBadgeIDs = self.knownUserBoostBadgeIDs(tx: tx)
        let persistedGiftBadgeIDs = self.knownUserGiftBadgeIDs(tx: tx)
        let oldExpiredGiftBadgeID = self.mostRecentlyExpiredGiftBadgeID(tx: tx)
        var expiringBadgeId = self.mostRecentlyExpiredBadgeID(tx: tx)
        var userManuallyCancelled = self.userManuallyCancelledSubscription(tx: tx)
        var showExpiryOnHomeScreen = self.showExpirySheetOnHomeScreenKey(tx: tx)
        var displayBadgesOnProfile = self.displayBadgesOnProfile(tx: tx)

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
            if expiringBadgeId == nil || BoostBadgeIds.contains(expiringBadgeId!), newExpiringBadgeId == nil {
                Logger.info("Last boost badge id expired \(persistedBadgeId)")
                newExpiringBadgeId = persistedBadgeId
            } else {
                Logger.info("Last boost badge id expired \(persistedBadgeId), but ignoring because subscription badge also expired")
            }
        }

        if let newExpiringBadgeId, newExpiringBadgeId != expiringBadgeId {
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
        self.setKnownUserSubscriptionBadgeIDs(badgeIDs: currentSubscriberBadgeIDs, tx: tx)
        self.setKnownUserBoostBadgeIDs(badgeIDs: currentBoostBadgeIDs, tx: tx)
        self.setKnownUserGiftBadgeIDs(badgeIDs: currentGiftBadgeIDs, tx: tx)
        self.setMostRecentlyExpiredGiftBadgeID(badgeID: newExpiredGiftBadgeID, tx: tx)
        self.setMostRecentlyExpiredBadgeID(badgeID: expiringBadgeId, tx: tx)
        self.setShowExpirySheetOnHomeScreenKey(show: showExpiryOnHomeScreen, tx: tx)
        self.setUserManuallyCancelledSubscription(userManuallyCancelled, tx: tx)
        self.setDisplayBadgesOnProfile(displayBadgesOnProfile, tx: tx)
    }

    // MARK: -

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
