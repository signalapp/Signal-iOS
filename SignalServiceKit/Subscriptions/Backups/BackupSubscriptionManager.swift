//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import StoreKit
import LibSignalClient

/// Responsible for In-App Purchases (IAP) via StoreKit that grant access to
/// paid-tier Backups.
///
/// - Note
/// Backup payments are done via IAP using Apple as the payment processor, and
/// consequently payments management is done via Apple ID management in the iOS
/// Settings app rather than in-app UI.
///
/// - Important
/// Not to be confused with ``DonationSubscriptionManager``, which does many similar
/// things but designed around donations and profile badges.
public protocol BackupSubscriptionManager {
    typealias PurchaseResult = BackupSubscription.PurchaseResult
    typealias RedemptionResult = BackupSubscription.RedemptionResult

    /// Attempts to purchase and redeem a Backups subscription for the first
    /// time, via StoreKit IAP.
    ///
    /// - Note
    /// While this should be called only for users who do not currently have a
    /// Backups subscription, StoreKit handles already-subscribed users
    /// gracefully by showing explanatory UI.
    ///
    /// - Note
    /// This method will finish successfully
    func purchaseNewSubscription() async throws -> PurchaseResult

    /// Redeems a StoreKit Backups subscription with Signal servers for access
    /// to paid-tier Backup credentials, if there exists a StoreKit transaction
    /// we have not yet redeemed.
    ///
    /// - Note
    /// This method serializes callers, is safe to call repeatedly, and returns
    /// quickly if there is not a transaction we have yet to redeem.
    func redeemSubscriptionIfNecessary() async throws -> RedemptionResult

    /// Returns the current Backup subscriber ID, if one exists.
    func getBackupSubscriberId(tx: DBReadTransaction) -> Data?

    /// Sets the current Backup subscriber ID.
    ///
    /// - Important
    /// Generally, this type generates and manages the `backupSubscriberId`
    /// internally. This  API should only be invoked by callers who are
    /// confident their `backupSubscriberId` is the most-current, such as when
    /// restoring from Storage Service or a Backup.
    func setBackupSubscriberId(_ backupSubscriberId: Data, tx: DBWriteTransaction)
}

public enum BackupSubscription {

    /// Describes the result of initiating a StoreKit purchase.
    public enum PurchaseResult {
        /// Purchase was successful. Contains the result of the purchase's
        /// redemption with Signal servers.
        ///
        /// - Note
        /// Success also covers if the user attempted to purchase this
        /// subscription, but was already subscribed.
        case success(RedemptionResult)

        /// Purchase is pending external action, such as approval when "Ask to
        /// Buy" is enabled.
        case pending

        /// The user cancelled the purchase.
        case userCancelled
    }

    /// Describes the result of redeeming a StoreKit purchase with Signal
    /// servers.
    public enum RedemptionResult {
        /// Redemption was successful.
        case success

        /// No action was necessary. For example, we may have already redeemed
        /// the subscription for the current period, or may not have an active
        /// subscription to redeem.
        case noActionNeeded
    }
}

// MARK: -

final class BackupSubscriptionManagerImpl: BackupSubscriptionManager {
    private enum Constants {
        /// This value corresponds to our IAP config set up in App Store
        /// Connect, and must not change!
        static let paidTierBackupsProductId = "backups.mediatier"

        /// A "receipt level" baked by the server into the receipt credentials
        /// used for Backups, representing the free (messages) tier.
        static let freeTierBackupsReceiptLevel = 200
        /// A "receipt level" baked by the server into the receipt credentials
        /// used for Backups, representing the paid (media) tier.
        static let paidTierBackupsReceiptLevel = 201
    }

    private let logger = PrefixedLogger(prefix: "[BkpSubMgr]")

    private let dateProvider: DateProvider
    private let db: any DB
    private let kvStore: KeyValueStore
    private let networkManager: NetworkManager

    init(
        dateProvider: @escaping DateProvider,
        db: any DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        networkManager: NetworkManager
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = keyValueStoreFactory.keyValueStore(collection: "BackupSubscriptionManager")
        self.networkManager = networkManager

        listenForTransactionUpdates()
    }

    /// Returns the `Transaction` that most recently entitled us to the StoreKit
    /// "paid tier" subscription, or `nil` if we are not entitled to it.
    ///
    /// For example, if we originally purchased a subscription in transaction T,
    /// then renewed it twice in transactions T+1 (now expired) and T+2
    /// (currently valid), this method will return transaction T+2.
    private func latestEntitlingTransaction() async -> Transaction? {
        guard let latestEntitlingTransactionResult = await Transaction.currentEntitlement(
            for: Constants.paidTierBackupsProductId
        ) else {
            return nil
        }

        guard let latestEntitlingTransaction = try? latestEntitlingTransactionResult.payloadValue else {
            owsFailDebug(
                "Latest entitlement transaction was unverified!",
                logger: logger
            )
            return nil
        }

        return latestEntitlingTransaction
    }

    /// Listens to `Transaction.updates`, and handles any transaction updates as
    /// appropriate.
    ///
    /// `Transaction.updates` is how the app is informed by StoreKit about
    /// transactions other than ones we completed inline via `.purchase()`. The
    /// big case this covers is renewals: when the subscription renews, we learn
    /// about it next time we launch via this listener. If, for example, a user
    /// went offline for two months (i.e., two renewal periods) this listener
    /// will receive two transactions: one for the now-expired period, and one
    /// for the current period.
    ///
    /// The other case this covers is "Ask to Buy", where the user's purchase is
    /// "pending" until approved/denied by someone else (e.g., a parent); when
    /// that happens, we get a callback here.
    private func listenForTransactionUpdates() {
        // TODO: [BSub] Ensure this is only kicked off once, during app launch.
        Task.detached { [weak self] in
            for await transactionResult in Transaction.updates {
                /// Guard on `self` in here, since we're in an async stream.
                guard let self else { return }

                guard let transaction = try? transactionResult.payloadValue else {
                    owsFailDebug(
                        "Transaction from update was unverified!",
                        logger: logger
                    )
                    continue
                }

                logger.info("Got transaction update.")

                if
                    let latestEntitlingTransaction = await latestEntitlingTransaction(),
                    latestEntitlingTransaction.id == transaction.id
                {
                    logger.info("Transaction update is for latest entitling transaction; attempting subscription redemption.")

                    do {
                        /// This transaction entitles us to redeem a subscription,
                        /// so let's attempt to do so. We could get here, for
                        /// example, if someone who purchased a subscription had
                        /// "Ask to Buy" on; when the purchase is approved we'll get
                        /// a callback here, and should try and redeem.
                        ///
                        /// Note that `redeemSubscriptionIfNecessary` will fetch the
                        /// latest entitling transaction itself, and finish it when
                        /// redemption succeeds.
                        _ = try await redeemSubscriptionIfNecessary()
                    } catch {
                        owsFailDebug(
                            "Failed to redeem subscription: \(error)",
                            logger: logger
                        )
                    }
                } else {
                    logger.info("Transaction update is not for latest entitling subscription; finishing it.")

                    /// This transaction doesn't entitle us to a subscription,
                    /// maybe because it's expired or revoked. Regardless, all
                    /// transactions should be finished evenutally, so let's lay
                    /// this one to rest.
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Purchase new subscription

    func purchaseNewSubscription() async throws -> PurchaseResult {
        guard let paidTierProduct = try await Product.products(for: [Constants.paidTierBackupsProductId]).first else {
            throw OWSAssertionError(
                "Failed to get paid tier subscription product from StoreKit!",
                logger: logger
            )
        }

        switch try await paidTierProduct.purchase() {
        case .success(let purchaseResult):
            switch purchaseResult {
            case .verified:
                return .success(try await redeemSubscriptionIfNecessary())
            case .unverified:
                throw OWSAssertionError(
                    "Unverified successful purchase result!",
                    logger: logger
                )
            }
        case .userCancelled:
            logger.info("User cancelled subscription purchase.")
            return .userCancelled
        case .pending:
            logger.warn("Subscription purchase is pending; expect redemption if it is approved.")
            return .pending
        @unknown default:
            throw OWSAssertionError(
                "Unknown purchase result!",
                logger: logger
            )
        }
    }

    // MARK: - Redeem subscription

    /// Serializes multiple attempts to redeem a subscription, so they don't
    /// race. Specifically, if a caller attempts to redeem a subscription while
    /// a previous caller's attempt is in progress, the latter caller will wait
    /// on the previous caller.
    ///
    /// `_redeemSubscriptionIfNecessary()` uses persisted state, so latter
    /// callers may be able to short-circuit based on state persisted by an
    /// earlier caller.
    private let redemptionAttemptSerializer = SerialTaskQueue()

    func redeemSubscriptionIfNecessary() async throws -> RedemptionResult {
        return try await redemptionAttemptSerializer.enqueue {
            try await self._redeemSubscriptionIfNecessary()
        }.value
    }

    private func _redeemSubscriptionIfNecessary() async throws -> RedemptionResult {
        // TODO: [BSub] We need to wait on Storage Service restore, since we keep the subscriber ID in there.

        guard let latestEntitlingTransaction = await latestEntitlingTransaction() else {
            return .noActionNeeded
        }

        let (
            latestRedeemedTransactionId,
            persistedBackupSubscriberId,
            inProgressRedemptionState
        ): (
            UInt64?,
            Data?,
            RedemptionAttemptState
        ) = try db.read { tx in
            return (
                getLatestRedeemedTransactionId(tx: tx),
                getBackupSubscriberId(tx: tx),
                try getInProgressRedemptionState(tx: tx)
            )
        }

        guard latestRedeemedTransactionId != latestEntitlingTransaction.id else {
            /// This means that we've already done a redemption for this
            /// transaction. The transaction should already be finished, so
            /// we've got nothing left to do.
            ///
            /// It's possible that we'd get here with an unfinished transaction
            /// if we persisted relevant data, but crashed before finishing the
            /// transaction. That's not ideal but should be okay; when we get a
            /// new latest-entitling transaction (in the next subscription
            /// period) that unfinished transaction will be handled as expired.
            return .noActionNeeded
        }

        let subscriberId: Data
        if let persistedBackupSubscriberId {
            subscriberId = persistedBackupSubscriberId
        } else {
            subscriberId = try await registerNewSubscriberId(
                originalTransactionId: latestEntitlingTransaction.originalID
            )
        }

        if
            let subscriptionStatus = await latestEntitlingTransaction.subscriptionStatus,
            let renewalInfo = try? subscriptionStatus.renewalInfo.payloadValue,
            let renewalDate = renewalInfo.renewalDate
        {
            logger.info("Attempting to redeem subscription for renewal period ending at \(renewalDate).")
        } else {
            logger.warn("Attempting to redeem subscription, but with unverified or missing renewal date!")
        }

        /// Redeem a subscription for this transaction, and subsequently mark it
        /// as finished.
        return try await redeemSubscription(
            subscriberId: subscriberId,
            latestTransaction: latestEntitlingTransaction,
            inProgressRedemptionState: inProgressRedemptionState
        )
    }

    /// Generate a new subscriber ID, and register it with the server to be
    /// associated with the given StoreKit "original transaction ID" for a
    /// subscription. Persists and returns the new subscriber ID.
    private func registerNewSubscriberId(
        originalTransactionId: UInt64
    ) async throws -> Data {
        logger.info("Generating and registering new Backups subscriber ID!")

        let newSubscriberId = Randomness.generateRandomBytes(32)

        /// First, we tell the server (unauthenticated) that a new subscriber ID
        /// exists. At this point, it won't be associated with anything.
        let registerSubscriberIdResponse = try await networkManager.makePromise(
            request: .registerSubscriberId(subscriberId: newSubscriberId)
        ).awaitable()

        guard registerSubscriberIdResponse.responseStatusCode == 200 else {
            throw OWSAssertionError(
                "Unexpected status code registering new Backup subscriber ID! \(registerSubscriberIdResponse.responseStatusCode)",
                logger: logger
            )
        }

        /// Next, we tell the server (unauthenticated) to associate the
        /// subscriber ID with the "original transaction ID" of an IAP.
        ///
        /// Importantly, this request is safe to make repeatedly, with any
        /// combination of `subscriberId` and `originalTransactionId`.
        let associateIdsResponse = try await networkManager.makePromise(
            request: .associateSubscriberId(
                newSubscriberId,
                withOriginalTransactionId: originalTransactionId
            )
        ).awaitable()

        guard associateIdsResponse.responseStatusCode == 200 else {
            throw OWSAssertionError(
                "Unexpected status code associating new Backup subscriber ID with originalTransactionId! \(associateIdsResponse.responseStatusCode)",
                logger: logger
            )
        }

        /// Our subscriber ID is now set up on the service, and we should record
        /// it locally!
        await db.awaitableWrite { tx in
            self.setBackupSubscriberId(newSubscriberId, tx: tx)
        }

        // TODO: [BSub] Record the new subscriber ID in Storage Service

        return newSubscriberId
    }

    /// Performs the steps required to redeem a Backup subscription for the
    /// period covered by the given `Transaction`.
    ///
    /// Specifically, performs the following steps:
    /// 1. Generates a "receipt credential request".
    /// 2. Sends the receipt credential request to the service, receiving in
    ///    return a receipt credential presentation.
    /// 3. Redeems the receipt credential presentation with the service, which
    ///    enables or extends the server-side flag enabling paid-tier Backups
    ///    for our account.
    ///
    /// - Note
    /// This method functions as a state machine, starting with the given
    /// redemption state. As we move through each step we persist updated state,
    /// then recursively call this method with the new state.
    ///
    /// It's important that we persist the intermediate states so that we can
    /// resume if interrupted, since we may be mutating remote state in such a
    /// way that's only safe to retry with the same inputs.
    private func redeemSubscription(
        subscriberId: Data,
        latestTransaction: Transaction,
        inProgressRedemptionState: RedemptionAttemptState
    ) async throws -> RedemptionResult {
        func markTransactionAsRedeemed() async {
            await db.awaitableWrite { tx in
                /// This also clears the in-progress redemption state.
                self.setLatestRedeemedTransactionId(latestTransaction.id, tx: tx)
            }
            await latestTransaction.finish()
        }

        switch inProgressRedemptionState {
        case .unattempted:
            logger.info("Generating receipt credential request.")

            // TODO: [BSub] Move this code out of DonationSubscriptionManager
            let (
                receiptCredentialRequestContext,
                receiptCredentialRequest
            ) = DonationSubscriptionManager.generateReceiptRequest()

            let nextRedemptionState: RedemptionAttemptState = .receiptCredentialRequesting(
                request: receiptCredentialRequest,
                context: receiptCredentialRequestContext
            )

            try await db.awaitableWrite { tx throws in
                try self.setInProgressRedemptionState(nextRedemptionState, tx: tx)
            }

            return try await redeemSubscription(
                subscriberId: subscriberId,
                latestTransaction: latestTransaction,
                inProgressRedemptionState: nextRedemptionState
            )
        case .receiptCredentialRequesting(
            let receiptCredentialRequest,
            let receiptCredentialRequestContext
        ):
            logger.info("Requesting receipt credential.")

            let receiptCredential: ReceiptCredential
            do {
                // TODO: [BSub] Move this code out of DonationSubscriptionManager
                receiptCredential = try await DonationSubscriptionManager.requestReceiptCredential(
                    subscriberId: subscriberId,
                    isValidReceiptLevelPredicate: { receiptLevel -> Bool in
                        /// We'll accept either receipt level here to handle
                        /// things like clock skew, although we're generally
                        /// expecting a paid-tier receipt credential.
                        return (
                            receiptLevel == Constants.paidTierBackupsReceiptLevel
                            || receiptLevel == Constants.freeTierBackupsReceiptLevel
                        )
                    },
                    context: receiptCredentialRequestContext,
                    request: receiptCredentialRequest,
                    logger: logger
                ).awaitable()
            } catch let error as DonationSubscriptionManager.KnownReceiptCredentialRequestError {
                switch error.errorCode {
                case .paymentIntentRedeemed:
                    logger.warn("Subscription had already been redeemed for this period!")

                    /// This error (a 409) indicates that we've already redeemed
                    /// a receipt credential for the current "invoice", or
                    /// subscription period.
                    ///
                    /// We end up here if for whatever reason we don't know that
                    /// we've already redeemed for this subscription period. For
                    /// example, we may have redeemed on a previous install and
                    /// are missing the latest-redeemed transaction ID on this
                    /// install.
                    ///
                    /// Regardless, we now know that we've redeemed for this
                    /// subscription period, so there's nothing left to do and
                    /// we can treat this as a success.
                    await markTransactionAsRedeemed()
                    return .success
                case
                        .paymentStillProcessing,
                        .paymentFailed,
                        .localValidationFailed,
                        .serverValidationFailed,
                        .paymentNotFound:
                    throw error
                }
            }

            let nextRedemptionState: RedemptionAttemptState = .receiptCredentialRedemption(
                receiptCredential
            )

            try await db.awaitableWrite { tx in
                try self.setInProgressRedemptionState(nextRedemptionState, tx: tx)
            }

            return try await redeemSubscription(
                subscriberId: subscriberId,
                latestTransaction: latestTransaction,
                inProgressRedemptionState: nextRedemptionState
            )
        case .receiptCredentialRedemption(let receiptCredential):
            logger.info("Redeeming receipt credential.")

            let presentation = try DonationSubscriptionManager.generateReceiptCredentialPresentation(
                receiptCredential: receiptCredential
            )

            let response = try await networkManager.makePromise(
                request: .backupRedeemReceiptCredential(
                    receiptCredentialPresentation: presentation
                )
            ).awaitable()

            switch response.responseStatusCode {
            case 400:
                /// This indicates that our receipt credential presentation has
                /// expired. This is a weird scenario, because it indicates that
                /// so much time has elapsed since we got the receipt credential
                /// presentation and attempted to redeem it that it expired.
                /// Weird, but not impossible!
                ///
                /// We can handle this by throwing away the expired receipt
                /// credential and starting over.
                logger.warn("Receipt credential was expired!")

                let nextRedemptionState: RedemptionAttemptState = .unattempted

                try await db.awaitableWrite { tx in
                    try self.setInProgressRedemptionState(nextRedemptionState, tx: tx)
                }

                return try await redeemSubscription(
                    subscriberId: subscriberId,
                    latestTransaction: latestTransaction,
                    inProgressRedemptionState: nextRedemptionState
                )
            case 204:
                logger.info("Receipt credential redeemed successfully.")

                await markTransactionAsRedeemed()
                return .success
            default:
                /// We don't expect to recover from any of these unexpected
                /// statuses, so we'll mark the transaction as redeemed so we
                /// don't try again indefinitely before throwing.
                let error = OWSAssertionError(
                    "Unexpected response status code: \(response.responseStatusCode)",
                    logger: logger
                )

                await markTransactionAsRedeemed()
                throw error
            }
        }
    }

    // MARK: - Persistence

    private enum StoreKeys {
        /// Our "subscriber ID" for Backups, which we give to the server to
        /// associate with an identifier for our IAP. Like the donations
        /// subscriber ID, this value is not associated with our account, and
        /// thereby creates a separation between our account and any IAP
        /// identifiers.
        static let backupSubscriberId = "backupSubscriberId"

        /// The StoreKit ID of the latest `Transaction` we've successfully
        /// redeemed. Stored such that we can avoid attempting to redeem the
        /// same transaction multiple times.
        static let latestRedeemedTransactionId = "latestRedeemedTransactionId"

        /// The latest state of any in-progress attempts at redeeming a StoreKit
        /// subscription with Signal servers.
        ///
        /// See ``RedemptionAttemptState`` for more details.
        static let inProgressRedemptionAttemptState = "redemptionAttemptState"
    }

    func getBackupSubscriberId(tx: DBReadTransaction) -> Data? {
        return kvStore.getData(StoreKeys.backupSubscriberId, transaction: tx)
    }

    func setBackupSubscriberId(_ backupSubscriberId: Data, tx: DBWriteTransaction) {
        kvStore.setData(backupSubscriberId, key: StoreKeys.backupSubscriberId, transaction: tx)
    }

    private func getLatestRedeemedTransactionId(tx: DBReadTransaction) -> UInt64? {
        return kvStore.getUInt64(StoreKeys.latestRedeemedTransactionId, transaction: tx)
    }

    private func setLatestRedeemedTransactionId(_ transactionId: UInt64, tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: StoreKeys.inProgressRedemptionAttemptState, transaction: tx)
        kvStore.setUInt64(transactionId, key: StoreKeys.latestRedeemedTransactionId, transaction: tx)
    }

    private func getInProgressRedemptionState(tx: DBReadTransaction) throws -> RedemptionAttemptState {
        guard let persistedValue: RedemptionAttemptState = try? kvStore.getCodableValue(
            forKey: StoreKeys.inProgressRedemptionAttemptState,
            transaction: tx
        ) else {
            return .unattempted
        }

        return persistedValue
    }

    private func setInProgressRedemptionState(_ state: RedemptionAttemptState, tx: DBWriteTransaction) throws {
        try kvStore.setCodable(
            state,
            key: StoreKeys.inProgressRedemptionAttemptState,
            transaction: tx
        )
    }

    // MARK: -

    /// Represents the state of an in-progress attempt at redeeming a StoreKit
    /// subscription.
    ///
    /// It's important that we store this, because (generally) once we've made a
    /// receipt-credential-related request to the server, remote state has been
    /// set corresponding to the state we put in the request. If the app exits
    /// between making two requests, we need to have stored the data we sent in
    /// the first request so we can retry the second.
    ///
    /// Broadly, there are two network requests required to redeem a receipt
    /// credential for a StoreKit subscription.
    ///
    /// The first is to "request a receipt credential", which takes a
    /// locally-generated "receipt credential request" and returns us data we
    /// can use to construct a "receipt credential presentation". Once we have
    /// the receipt credential presentation, we can discard the receipt
    /// credential request.
    ///
    /// The second is to "redeem the receipt credential", which sends the
    /// receipt credential presentation from the first request to the service,
    /// which validates it and subsequently records that our account is now
    /// eligible (or has extended its eligibility) for paid-tier Backups. When
    /// this completes, the attempt is complete.
    private enum RedemptionAttemptState: Codable {
        /// This attempt is at a clean slate.
        case unattempted

        /// We need to request a receipt credential, using the associated
        /// request and context objects.
        ///
        /// Note that it is safe to request a receipt credential multiple times,
        /// as long as the request/context are the same across retries. Receipt
        /// credential requests do not expire, and the returned receipt
        /// credential will always correspond to the latest entitling
        /// transaction.
        case receiptCredentialRequesting(
            request: ReceiptCredentialRequest,
            context: ReceiptCredentialRequestContext
        )

        /// We have a receipt credential, and need to redeem it.
        ///
        /// Note that it is safe to attempt to redeem a receipt credential
        /// multiple times for the same subscription period.
        case receiptCredentialRedemption(ReceiptCredential)

        // MARK: Codable

        private enum CodingKeys: String, CodingKey {
            case receiptCredentialRequest
            case receiptCredentialRequestContext
            case receiptCredential
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if
                let requestData = try container.decodeIfPresent(Data.self, forKey: .receiptCredentialRequest),
                let contextData = try container.decodeIfPresent(Data.self, forKey: .receiptCredentialRequestContext)
            {
                self = .receiptCredentialRequesting(
                    request: try ReceiptCredentialRequest(contents: [UInt8](requestData)),
                    context: try ReceiptCredentialRequestContext(contents: [UInt8](contextData))
                )
            } else
                if let credentialData = try container.decodeIfPresent(Data.self, forKey: .receiptCredential)
            {
                self = .receiptCredentialRedemption(
                    try ReceiptCredential(contents: [UInt8](credentialData))
                )
            } else {
                self = .unattempted
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .receiptCredentialRequesting(let request, let context):
                try container.encode(request.serialize().asData, forKey: .receiptCredentialRequest)
                try container.encode(context.serialize().asData, forKey: .receiptCredentialRequestContext)
            case .receiptCredentialRedemption(let credential):
                try container.encode(credential.serialize().asData, forKey: .receiptCredential)
            case .unattempted:
                break
            }
        }
    }
}

// MARK: -

private extension TSRequest {
    static func registerSubscriberId(subscriberId: Data) -> TSRequest {
        return OWSRequestFactory.setSubscriberID(subscriberId)
    }

    static func associateSubscriberId(
        _ subscriberId: Data,
        withOriginalTransactionId originalTransactionId: UInt64
    ) -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/subscription/\(subscriberId.asBase64Url)/appstore/\(originalTransactionId)")!,
            method: "POST",
            parameters: nil
        )
        request.shouldHaveAuthorizationHeaders = false
        request.applyRedactionStrategy(.redactURLForSuccessResponses())
        return request
    }

    static func backupRedeemReceiptCredential(
        receiptCredentialPresentation: ReceiptCredentialPresentation
    ) -> TSRequest {
        return TSRequest(
            url: URL(string: "v1/archives/redeem-receipt")!,
            method: "POST",
            parameters: [
                "receiptCredentialPresentation": receiptCredentialPresentation
                    .serialize().asData.base64EncodedString(),
            ]
        )
    }
}
