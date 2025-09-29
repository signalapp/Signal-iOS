//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// Responsible for redeeming receipt credentials for Backups subscriptions.
final class BackupSubscriptionRedeemer {
    private enum Constants {
        /// A "receipt level" baked by the server into the receipt credentials
        /// used for Backups, representing the free (messages) tier.
        static let freeTierBackupReceiptLevel = 200
        /// A "receipt level" baked by the server into the receipt credentials
        /// used for Backups, representing the paid (media) tier.
        static let paidTierBackupReceiptLevel = 201
    }

    private let authCredentialStore: AuthCredentialStore
    private let backupPlanManager: BackupPlanManager
    private let db: any DB
    private let logger: PrefixedLogger
    private let reachabilityManager: SSKReachabilityManager
    private let networkManager: NetworkManager

    private var networkRetryWaitingTask: AtomicValue<Task<Void, Never>?>
    private var notificationObservers: [NotificationCenter.Observer]
    private var transientFailureCount: UInt

    init(
        authCredentialStore: AuthCredentialStore,
        backupPlanManager: BackupPlanManager,
        db: any DB,
        reachabilityManager: SSKReachabilityManager,
        networkManager: NetworkManager,
    ) {
        self.authCredentialStore = authCredentialStore
        self.backupPlanManager = backupPlanManager
        self.db = db
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.reachabilityManager = reachabilityManager
        self.networkManager = networkManager

        self.networkRetryWaitingTask = AtomicValue(nil, lock: .init())
        self.notificationObservers = []
        self.transientFailureCount = 0

        notificationObservers.append(NotificationCenter.default.addObserver(
            name: SSKReachability.owsReachabilityDidChange,
            block: { [weak self] _ in
                guard let self else { return }

                networkRetryWaitingTask.update { task in
                    if let task, reachabilityManager.isReachable {
                        task.cancel()
                    }
                }
            }
        ))
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: -

    /// Returns an exponential-backoff retry delay that increases with each
    /// subsequent call to this method.
    private func waitForIncrementedExponentialRetry() async {
        transientFailureCount += 1

        let retryDelay: TimeInterval = OWSOperation.retryIntervalForExponentialBackoff(
            failureCount: transientFailureCount,
            maxAverageBackoff: .day
        )

        do {
            try await Task.sleep(nanoseconds: retryDelay.clampedNanoseconds)
        } catch {
            owsPrecondition(error is CancellationError)
        }
    }

    // MARK: -

    func redeem(context: BackupSubscriptionRedemptionContext) async throws {
        struct TerminalRedemptionError: Error {}

        switch await _redeemBackupReceiptCredential(context: context) {
        case .success:
            do {
                try await db.awaitableWriteWithRollbackIfThrows { tx in
                    context.delete(tx: tx)

                    /// We're now a paid-tier Backups user according to the server.
                    /// If our local thinks we're free-tier, upgrade it.
                    switch backupPlanManager.backupPlan(tx: tx) {
                    case .free:
                        // "Optimize Media" is off by default when you first upgrade.
                        try backupPlanManager.setBackupPlan(
                            .paid(optimizeLocalStorage: false),
                            tx: tx
                        )
                    case .disabled, .disabling:
                        // Don't sneakily enable Backups!
                        break
                    case .paid, .paidExpiringSoon, .paidAsTester:
                        break
                    }

                    /// Clear out any cached Backup auth credentials, since we
                    /// may now be able to fetch credentials with a higher level
                    /// of access than we had cached.
                    authCredentialStore.removeAllBackupAuthCredentials(tx: tx)
                }

                logger.info("Redemption successful!")
            } catch {
                owsFailDebug("Failed to set BackupPlan! \(error)")

                await db.awaitableWrite { context.delete(tx: $0) }
                throw TerminalRedemptionError()
            }

        case .needsReattempt:
            // Try again, without a delay.
            try await redeem(context: context)

        case .paymentStillProcessing:
            // Try again, with a delay.
            await waitForIncrementedExponentialRetry()
            try await redeem(context: context)

        case .networkError:
            // Try again, with an interruptable delay.
            let waitingTask = networkRetryWaitingTask.update {
                let task = Task {
                    await waitForIncrementedExponentialRetry()
                    networkRetryWaitingTask.set(nil)
                }
                $0 = task
                return task
            }
            await waitingTask.value
            try await redeem(context: context)

        case .redemptionUnsuccessful, .assertion:
            owsFailDebug("Job encountered unexpected terminal error!")

            await db.awaitableWrite { context.delete(tx: $0) }
            throw TerminalRedemptionError()
        }
    }

    // MARK: -

    private enum RedeemBackupReceiptCredentialResult {
        case success
        case networkError
        case needsReattempt
        case paymentStillProcessing
        case redemptionUnsuccessful
        case assertion
    }

    /// Performs the steps required to redeem a Backup subscription.
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
    private func _redeemBackupReceiptCredential(
        context: BackupSubscriptionRedemptionContext,
    ) async -> RedeemBackupReceiptCredentialResult {

        switch context.attemptState {
        case .unattempted:
            logger.info("Generating receipt credential request.")

            let (
                receiptCredentialRequestContext,
                receiptCredentialRequest
            ) = DonationSubscriptionManager.generateReceiptRequest()

            await db.awaitableWrite { tx in
                context.attemptState = .receiptCredentialRequesting(
                    request: receiptCredentialRequest,
                    context: receiptCredentialRequestContext
                )
                context.upsert(tx: tx)
            }
            return await _redeemBackupReceiptCredential(context: context)

        case .receiptCredentialRequesting(
            let receiptCredentialRequest,
            let receiptCredentialRequestContext
        ):
            logger.info("Requesting receipt credential.")

            let receiptCredential: ReceiptCredential
            do {
                receiptCredential = try await DonationSubscriptionManager.requestReceiptCredential(
                    subscriberId: context.subscriberId,
                    isValidReceiptLevelPredicate: { receiptLevel -> Bool in
                        /// We'll accept either receipt level here to handle
                        /// things like clock skew, although we're generally
                        /// expecting a paid-tier receipt credential.
                        return (
                            receiptLevel == Constants.paidTierBackupReceiptLevel
                            || receiptLevel == Constants.freeTierBackupReceiptLevel
                        )
                    },
                    context: receiptCredentialRequestContext,
                    request: receiptCredentialRequest,
                    networkManager: networkManager,
                    logger: logger
                )
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
                    return .success
                case .paymentStillProcessing:
                    return .paymentStillProcessing
                case
                        .paymentFailed,
                        .localValidationFailed,
                        .serverValidationFailed,
                        .paymentNotFound:
                    return .redemptionUnsuccessful
                }
            } catch where error.isNetworkFailureOrTimeout || error.is5xxServiceResponse {
                return .networkError
            } catch let error {
                owsFailDebug(
                    "Unexpected error requesting receipt credential: \(error)",
                    logger: logger
                )
                return .assertion
            }

            await db.awaitableWrite { tx in
                context.attemptState = .receiptCredentialRedemption(receiptCredential)
                context.upsert(tx: tx)
            }
            return await _redeemBackupReceiptCredential(context: context)

        case .receiptCredentialRedemption(let receiptCredential):
            logger.info("Redeeming receipt credential.")

            let presentation: ReceiptCredentialPresentation
            do {
                presentation = try DonationSubscriptionManager.generateReceiptCredentialPresentation(
                    receiptCredential: receiptCredential
                )
            } catch let error {
                owsFailDebug(
                    "Failed to generate receipt credential presentation: \(error)",
                    logger: logger
                )
                return .assertion
            }

            let response: HTTPResponse
            do {
                response = try await networkManager.asyncRequest(
                    .backupRedeemReceiptCredential(
                        receiptCredentialPresentation: presentation
                    ),
                    retryPolicy: .hopefullyRecoverable
                )
            } catch where error.isNetworkFailureOrTimeout || error.is5xxServiceResponse {
                return .networkError
            } catch where error.httpStatusCode == 400 {
                /// This indicates that our receipt credential presentation has
                /// expired. This is a weird scenario, because it indicates that
                /// so much time has elapsed since we got the receipt credential
                /// presentation and attempted to redeem it that it expired.
                /// Weird, but not impossible!
                ///
                /// We can handle this by throwing away the expired receipt
                /// credential and retrying the job.
                logger.warn("Receipt credential was expired!")

                await db.awaitableWrite { tx in
                    context.attemptState = .unattempted
                    context.upsert(tx: tx)
                }

                return .needsReattempt
            } catch {
                owsFailDebug(
                    "Unexpected error: \(error)",
                    logger: logger
                )
                return .assertion
            }

            switch response.responseStatusCode {
            case 204:
                logger.info("Receipt credential redeemed successfully.")
                return .success

            default:
                owsFailDebug(
                    "Unexpected response status code: \(response.responseStatusCode)",
                    logger: logger
                )
                return .assertion
            }
        }
    }
}

// MARK: -

private extension TSRequest {
    static func backupRedeemReceiptCredential(
        receiptCredentialPresentation: ReceiptCredentialPresentation
    ) -> TSRequest {
        return TSRequest(
            url: URL(string: "v1/archives/redeem-receipt")!,
            method: "POST",
            parameters: [
                "receiptCredentialPresentation": receiptCredentialPresentation
                    .serialize().base64EncodedString(),
            ]
        )
    }
}
