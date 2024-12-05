//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

private let logger = PrefixedLogger(prefix: "[MessageBackup][Sub]")

/// Responsible for durably redeeming a receipt credential for a Backups
/// subscription.
class BackupReceiptCredentialRedemptionJobQueue {
    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<BackupReceiptCredentialRedemptionJobRecord>,
        BackupReceiptCredentialRedemptionJobRunnerFactory
    >
    private let jobRunnerFactory: BackupReceiptCredentialRedemptionJobRunnerFactory

    public init(
        db: any DB,
        networkManager: NetworkManager,
        reachabilityManager: SSKReachabilityManager
    ) {
        self.jobRunnerFactory = BackupReceiptCredentialRedemptionJobRunnerFactory(
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
    private let db: any DB
    private let networkManager: NetworkManager

    init(db: any DB, networkManager: NetworkManager) {
        self.db = db
        self.networkManager = networkManager
    }

    func buildRunner() -> BackupReceiptCredentialRedemptionJobRunner {
        return BackupReceiptCredentialRedemptionJobRunner(
            db: db,
            networkManager: networkManager,
            continuation: nil
        )
    }

    func buildRunner(continuation: CheckedContinuation<Void, Error>) -> BackupReceiptCredentialRedemptionJobRunner {
        return BackupReceiptCredentialRedemptionJobRunner(
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

    private let db: any DB
    private let networkManager: NetworkManager

    private let continuation: CheckedContinuation<Void, Error>?

    init(
        db: any DB,
        networkManager: NetworkManager,
        continuation: CheckedContinuation<Void, Error>?
    ) {
        self.db = db
        self.networkManager = networkManager
        self.continuation = continuation
    }

    // MARK: -

    func runJobAttempt(_ jobRecord: BackupReceiptCredentialRedemptionJobRecord) async -> JobAttemptResult {
        return await .executeBlockWithDefaultErrorHandler(
            jobRecord: jobRecord,
            retryLimit: Constants.maxRetries,
            db: db
        ) {
            try await _redeemBackupReceiptCredential(jobRecord: jobRecord)
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

    /// An explicitly `isRetryable` error for receipt credential redemption.
    ///
    /// Necessary since the `JobAttemptResult` retry machinery relies on
    /// `isRetryable`, which defaults to `true` if not explicit, which could
    /// result in us doing a lot of meaningless retries if we throw an
    /// unexpected error.
    private enum RedeemBackupReceiptCredentialError: Error, IsRetryableProvider {
        case networkError
        case redemptionUnsuccessful
        case assertion

        var isRetryableProvider: Bool {
            switch self {
            case .networkError: return true
            case .redemptionUnsuccessful: return false
            case .assertion: return false
            }
        }
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
    ) async throws(RedeemBackupReceiptCredentialError) {

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
            return try await _redeemBackupReceiptCredential(jobRecord: jobRecord)

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
                    await db.awaitableWrite { tx in
                        jobRecord.delete(tx: tx)
                    }
                    return
                case
                        .paymentStillProcessing,
                        .paymentFailed,
                        .localValidationFailed,
                        .serverValidationFailed,
                        .paymentNotFound:
                    throw .redemptionUnsuccessful
                }
            } catch let error where error.isNetworkFailureOrTimeout {
                throw .networkError
            } catch let error {
                owsFailDebug("Unexpected error requesting receipt credential: \(error)")
                throw .assertion
            }

            let nextAttemptState: RedemptionAttemptState = .receiptCredentialRedemption(
                receiptCredential
            )
            await db.awaitableWrite { tx in
                jobRecord.updateAttemptState(nextAttemptState, tx: tx)
            }
            return try await _redeemBackupReceiptCredential(jobRecord: jobRecord)

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
                throw .assertion
            }

            let response: HTTPResponse
            do {
                response = try await networkManager.makePromise(
                    request: .backupRedeemReceiptCredential(
                        receiptCredentialPresentation: presentation
                    )
                ).awaitable()
            } catch {
                throw .networkError
            }

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

                let nextAttemptState: RedemptionAttemptState = .unattempted
                await db.awaitableWrite { tx in
                    jobRecord.updateAttemptState(nextAttemptState, tx: tx)
                }
                return try await _redeemBackupReceiptCredential(jobRecord: jobRecord)

            case 204:
                logger.info("Receipt credential redeemed successfully.")

                await db.awaitableWrite { tx in
                    jobRecord.delete(tx: tx)
                }
                return

            default:
                owsFailDebug(
                    "Unexpected response status code: \(response.responseStatusCode)",
                    logger: logger
                )
                throw .assertion
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
                    .serialize().asData.base64EncodedString(),
            ]
        )
    }
}
