//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

private let logger = PrefixedLogger(prefix: "[Backups][Sub]")

/// Responsible for durably redeeming a receipt credential for a Backups
/// subscription.
class BackupReceiptCredentialRedemptionJobQueue {
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<BackupReceiptCredentialRedemptionJobRecord>,
        BackupReceiptCredentialRedemptionJobRunnerFactory
    >
    private let jobRunnerFactory: BackupReceiptCredentialRedemptionJobRunnerFactory

    public init(
        authCredentialStore: AuthCredentialStore,
        backupPlanManager: BackupPlanManager,
        db: any DB,
        networkManager: NetworkManager,
        reachabilityManager: SSKReachabilityManager
    ) {
        self.jobRunnerFactory = BackupReceiptCredentialRedemptionJobRunnerFactory(
            authCredentialStore: authCredentialStore,
            backupPlanManager: backupPlanManager,
            db: db,
            networkManager: networkManager
        )
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: true,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: self.jobRunnerFactory
        )
        self.jobQueueRunner.listenForReachabilityChanges(reachabilityManager: reachabilityManager)
    }

    func start(appContext: AppContext) {
        guard appContext.isMainApp else { return }
        jobQueueRunner.start(shouldRestartExistingJobs: true)
    }

    func saveBackupRedemptionJob(
        subscriberId: Data,
        tx: DBWriteTransaction
    ) -> BackupReceiptCredentialRedemptionJobRecord {
        logger.info("Adding a redemption job.")

        let jobRecord = BackupReceiptCredentialRedemptionJobRecord(subscriberId: subscriberId)
        jobRecord.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
        return jobRecord
    }

    func runBackupRedemptionJob(
        jobRecord: BackupReceiptCredentialRedemptionJobRecord
    ) async throws {
        logger.info("Running redemption job.")

        try await withCheckedThrowingContinuation { continuation in
            self.jobQueueRunner.addPersistedJob(
                jobRecord,
                runner: self.jobRunnerFactory.buildRunner(continuation: continuation)
            )
        }
    }
}

private class BackupReceiptCredentialRedemptionJobRunnerFactory: JobRunnerFactory {
    private let authCredentialStore: AuthCredentialStore
    private let backupPlanManager: BackupPlanManager
    private let db: any DB
    private let networkManager: NetworkManager

    init(
        authCredentialStore: AuthCredentialStore,
        backupPlanManager: BackupPlanManager,
        db: any DB,
        networkManager: NetworkManager
    ) {
        self.authCredentialStore = authCredentialStore
        self.backupPlanManager = backupPlanManager
        self.db = db
        self.networkManager = networkManager
    }

    func buildRunner() -> BackupReceiptCredentialRedemptionJobRunner {
        return BackupReceiptCredentialRedemptionJobRunner(
            authCredentialStore: authCredentialStore,
            backupPlanManager: backupPlanManager,
            db: db,
            networkManager: networkManager,
            continuation: nil
        )
    }

    func buildRunner(continuation: CheckedContinuation<Void, Error>) -> BackupReceiptCredentialRedemptionJobRunner {
        return BackupReceiptCredentialRedemptionJobRunner(
            authCredentialStore: authCredentialStore,
            backupPlanManager: backupPlanManager,
            db: db,
            networkManager: networkManager,
            continuation: continuation
        )
    }
}

private class BackupReceiptCredentialRedemptionJobRunner: JobRunner {
    typealias JobRecordType = BackupReceiptCredentialRedemptionJobRecord

    private typealias RedemptionAttemptState = BackupReceiptCredentialRedemptionJobRecord.RedemptionAttemptState

    private enum Constants {
        static let maxRetries: UInt = 110

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
    private let networkManager: NetworkManager

    private let continuation: CheckedContinuation<Void, Error>?
    private var transientFailureCount: UInt = 0

    init(
        authCredentialStore: AuthCredentialStore,
        backupPlanManager: BackupPlanManager,
        db: any DB,
        networkManager: NetworkManager,
        continuation: CheckedContinuation<Void, Error>?
    ) {
        self.authCredentialStore = authCredentialStore
        self.backupPlanManager = backupPlanManager
        self.db = db
        self.networkManager = networkManager
        self.continuation = continuation
    }

    /// Returns an exponential-backoff retry delay that increases with each
    /// subsequent call to this method.
    private func incrementExponentialRetryDelay() -> TimeInterval {
        transientFailureCount += 1

        return OWSOperation.retryIntervalForExponentialBackoff(
            failureCount: transientFailureCount,
            maxAverageBackoff: .day
        )
    }

    // MARK: -

    func runJobAttempt(_ jobRecord: BackupReceiptCredentialRedemptionJobRecord) async -> JobAttemptResult {
        struct TerminalJobError: Error {}

        switch await _redeemBackupReceiptCredential(jobRecord: jobRecord) {
        case .success:
            do {
                try await db.awaitableWriteWithRollbackIfThrows { tx in
                    jobRecord.anyRemove(transaction: tx)

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
                return .finished(.success(()))
            } catch {
                owsFailDebug("Failed to set BackupPlan! \(error)")

                await db.awaitableWrite { jobRecord.anyRemove(transaction: $0) }
                return .finished(.failure(TerminalJobError()))
            }

        case .networkError, .needsReattempt, .paymentStillProcessing:
            return .retryAfter(incrementExponentialRetryDelay())

        case .redemptionUnsuccessful, .assertion:
            owsFailDebug("Job encountered unexpected terminal error!")

            await db.awaitableWrite { jobRecord.anyRemove(transaction: $0) }
            return .finished(.failure(TerminalJobError()))
        }
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async {
        switch result.ranSuccessfullyOrError {
        case .success:
            logger.info("Redemption job finished successfully.")
            continuation?.resume()
        case .failure(let error):
            logger.error("Redemption job failed! \(error)")
            continuation?.resume(throwing: error)
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
    private func _redeemBackupReceiptCredential(
        jobRecord: BackupReceiptCredentialRedemptionJobRecord
    ) async -> RedeemBackupReceiptCredentialResult {

        switch jobRecord.attemptState {
        case .unattempted:
            logger.info("Generating receipt credential request.")

            let (
                receiptCredentialRequestContext,
                receiptCredentialRequest
            ) = DonationSubscriptionManager.generateReceiptRequest()

            let nextAttemptState: RedemptionAttemptState = .receiptCredentialRequesting(
                request: receiptCredentialRequest,
                context: receiptCredentialRequestContext
            )
            await db.awaitableWrite { tx in
                jobRecord.updateAttemptState(nextAttemptState, tx: tx)
            }
            return await _redeemBackupReceiptCredential(jobRecord: jobRecord)

        case .receiptCredentialRequesting(
            let receiptCredentialRequest,
            let receiptCredentialRequestContext
        ):
            logger.info("Requesting receipt credential.")

            let receiptCredential: ReceiptCredential
            do {
                receiptCredential = try await DonationSubscriptionManager.requestReceiptCredential(
                    subscriberId: jobRecord.subscriberId,
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
                    await db.awaitableWrite { tx in
                        jobRecord.anyRemove(transaction: tx)
                    }
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

            let nextAttemptState: RedemptionAttemptState = .receiptCredentialRedemption(
                receiptCredential
            )
            await db.awaitableWrite { tx in
                jobRecord.updateAttemptState(nextAttemptState, tx: tx)
            }
            return await _redeemBackupReceiptCredential(jobRecord: jobRecord)

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

                let nextAttemptState: RedemptionAttemptState = .unattempted
                await db.awaitableWrite { tx in
                    jobRecord.updateAttemptState(nextAttemptState, tx: tx)
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
