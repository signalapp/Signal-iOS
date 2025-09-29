//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public extension Notification.Name {
    static let incomingContactSyncDidComplete = Notification.Name("IncomingContactSyncDidComplete")
}

final public class IncomingContactSyncJobQueue {
    public enum Constants {
        public static let insertedThreads = "insertedThreads"
    }

    private let jobQueueRunner: JobQueueRunner<
        JobRecordFinderImpl<IncomingContactSyncJobRecord>,
        IncomingContactSyncJobRunnerFactory
    >
    private var jobSerializer = CompletionSerializer()

    public init(appReadiness: AppReadiness, db: any DB, reachabilityManager: SSKReachabilityManager) {
        self.jobQueueRunner = JobQueueRunner(
            canExecuteJobsConcurrently: false,
            db: db,
            jobFinder: JobRecordFinderImpl(db: db),
            jobRunnerFactory: IncomingContactSyncJobRunnerFactory(appReadiness: appReadiness)
        )
        self.jobQueueRunner.listenForReachabilityChanges(reachabilityManager: reachabilityManager)
    }

    public func start(appContext: AppContext) {
        jobQueueRunner.start(shouldRestartExistingJobs: appContext.isMainApp)
    }

    public func add(
        cdnNumber: UInt32,
        cdnKey: String,
        encryptionKey: Data,
        digest: Data,
        plaintextLength: UInt32?,
        isComplete: Bool,
        tx: DBWriteTransaction
    ) {
        let jobRecord = IncomingContactSyncJobRecord(
            cdnNumber: cdnNumber,
            cdnKey: cdnKey,
            encryptionKey: encryptionKey,
            digest: digest,
            plaintextLength: plaintextLength,
            isCompleteContactSync: isComplete
        )
        jobRecord.anyInsert(transaction: tx)
        jobSerializer.addOrderedSyncCompletion(tx: tx) {
            self.jobQueueRunner.addPersistedJob(jobRecord)
        }
    }
}

final private class IncomingContactSyncJobRunnerFactory: JobRunnerFactory {

    private let appReadiness: AppReadiness

    init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
    }

    func buildRunner() -> IncomingContactSyncJobRunner {
        return IncomingContactSyncJobRunner(appReadiness: appReadiness)
    }
}

final private class IncomingContactSyncJobRunner: JobRunner {
    private enum Constants {
        static let maxRetries: UInt = 4
    }

    private let appReadiness: AppReadiness

    init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
    }

    func runJobAttempt(_ jobRecord: IncomingContactSyncJobRecord) async -> JobAttemptResult {
        return await JobAttemptResult.executeBlockWithDefaultErrorHandler(
            jobRecord: jobRecord,
            retryLimit: Constants.maxRetries,
            db: DependenciesBridge.shared.db,
            block: { try await _runJob(jobRecord) }
        )
    }

    func didFinishJob(_ jobRecordId: JobRecord.RowId, result: JobResult) async {}

    private func _runJob(_ jobRecord: IncomingContactSyncJobRecord) async throws {
        let fileUrl: URL
        switch jobRecord.downloadInfo {
        case .invalid:
            owsFailDebug("Invalid contact sync job!")
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                jobRecord.anyRemove(transaction: tx)
            }
            return
        case .transient(let downloadMetadata):
            fileUrl = try await DependenciesBridge.shared.attachmentDownloadManager.downloadTransientAttachment(
                metadata: downloadMetadata
            ).awaitable()
        }

        let insertedThreads = try await processContactSync(
            decryptedFileUrl: fileUrl,
            isComplete: jobRecord.isCompleteContactSync
        )
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            jobRecord.anyRemove(transaction: tx)
        }
        NotificationCenter.default.post(name: .incomingContactSyncDidComplete, object: self, userInfo: [
            IncomingContactSyncJobQueue.Constants.insertedThreads: insertedThreads
        ])
    }

    // MARK: - Private

    private func processContactSync(
        decryptedFileUrl fileUrl: URL,
        isComplete: Bool
    ) async throws -> [(threadUniqueId: String, sortOrder: UInt32)] {
        var insertedThreads = [(threadUniqueId: String, sortOrder: UInt32)]()
        let fileData = try Data(contentsOf: fileUrl, options: .mappedIfSafe)
        let inputStream = ChunkedInputStream(forReadingFrom: fileData)
        let contactStream = ContactsInputStream(inputStream: inputStream)

        // We use batching to avoid long-running write transactions
        // and to place an upper bound on memory usage.
        var allPhoneNumbers = [E164]()
        while try await processBatch(
            contactStream: contactStream,
            insertedThreads: &insertedThreads,
            processedPhoneNumbers: &allPhoneNumbers
        ) {}

        if isComplete {
            try await pruneContacts(exceptThoseReceivedFromCompleteSync: allPhoneNumbers)
        }

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            // Always fire just one identity change notification, rather than potentially
            // once per contact. It's possible that *no* identities actually changed,
            // but we have no convenient way to track that.
            let identityManager = DependenciesBridge.shared.identityManager
            identityManager.fireIdentityStateChangeNotification(after: transaction)
        }

        return insertedThreads
    }

    // Returns false when there are no more contacts to process.
    private func processBatch(
        contactStream: ContactsInputStream,
        insertedThreads: inout [(threadUniqueId: String, sortOrder: UInt32)],
        processedPhoneNumbers: inout [E164]
    ) async throws -> Bool {
        // We use batching to avoid long-running write transactions.
        guard let contactBatch = try Self.buildBatch(contactStream: contactStream) else {
            return false
        }
        guard !contactBatch.isEmpty else {
            owsFailDebug("Empty batch.")
            return false
        }
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            for contact in contactBatch {
                if let phoneNumber = try processContactDetails(contact, insertedThreads: &insertedThreads, tx: tx) {
                    processedPhoneNumbers.append(phoneNumber)
                }
            }
        }
        return true
    }

    private static func buildBatch(contactStream: ContactsInputStream) throws -> [ContactDetails]? {
        let batchSize = 8
        var contacts = [ContactDetails]()
        while contacts.count < batchSize, let contact = try contactStream.decodeContact() {
            contacts.append(contact)
        }
        guard !contacts.isEmpty else {
            return nil
        }
        return contacts
    }

    private func processContactDetails(
        _ contactDetails: ContactDetails,
        insertedThreads: inout [(threadUniqueId: String, sortOrder: UInt32)],
        tx: DBWriteTransaction
    ) throws -> E164? {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            throw OWSGenericError("Not registered.")
        }

        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let recipientManager = DependenciesBridge.shared.recipientManager
        let recipientMerger = DependenciesBridge.shared.recipientMerger

        let recipient: SignalRecipient
        if let aci = contactDetails.aci {
            recipient = recipientMerger.applyMergeFromContactSync(
                localIdentifiers: localIdentifiers,
                aci: aci,
                phoneNumber: contactDetails.phoneNumber,
                tx: tx
            )
            // Mark as registered only if we have a UUID (we always do in this branch).
            // If we don't have a UUID, contacts can't be registered.
            recipientManager.markAsRegisteredAndSave(recipient, shouldUpdateStorageService: false, tx: tx)
        } else if let phoneNumber = contactDetails.phoneNumber {
            recipient = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: tx)
        } else {
            throw OWSAssertionError("No identifier in ContactDetails.")
        }

        let address = recipient.address

        let contactThread: TSContactThread
        let isNewThread: Bool
        if let existingThread = TSContactThread.getWithContactAddress(address, transaction: tx) {
            contactThread = existingThread
            isNewThread = false
        } else {
            let newThread = TSContactThread(contactAddress: address)
            newThread.shouldThreadBeVisible = true

            contactThread = newThread
            isNewThread = true
        }

        if isNewThread {
            contactThread.anyInsert(transaction: tx)
            let inboxSortOrder = contactDetails.inboxSortOrder ?? UInt32.max
            insertedThreads.append((threadUniqueId: contactThread.uniqueId, sortOrder: inboxSortOrder))
        }

        let disappearingMessageToken = VersionedDisappearingMessageToken.token(
            forProtoExpireTimerSeconds: contactDetails.expireTimer,
            version: contactDetails.expireTimerVersion
        )
        GroupManager.remoteUpdateDisappearingMessages(
            contactThread: contactThread,
            disappearingMessageToken: disappearingMessageToken,
            changeAuthor: nil,
            localIdentifiers: localIdentifiers,
            transaction: tx
        )

        return contactDetails.phoneNumber
    }

    /// Clear ``SignalAccount``s that weren't part of a complete sync.
    ///
    /// Although "system contact" details (represented by a ``SignalAccount``)
    /// are synced via StorageService rather than contact sync messages, any
    /// contacts not included in a complete contact sync are not present on the
    /// primary device and should there be removed from this linked device.
    ///
    /// In theory, StorageService updates should handle removing these contacts.
    /// However, there's no periodic sync check our state against
    /// StorageService, so this job continues to fulfill that role. In the
    /// future, if you're removing this method, you should first ensure that
    /// periodic full syncs of contact details happen with StorageService.
    private func pruneContacts(exceptThoseReceivedFromCompleteSync phoneNumbers: [E164]) async throws {
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            // Every contact sync includes your own address. However, we shouldn't
            // create a SignalAccount for your own address. (If you're a primary, this
            // is handled by FetchedSystemContacts.phoneNumbers(…).)
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: transaction) else {
                throw OWSGenericError("Not registered.")
            }
            let setOfPhoneNumbers = Set(phoneNumbers.lazy.filter { !localIdentifiers.contains(phoneNumber: $0) })

            // Rather than collecting SignalAccount objects, collect their unique IDs.
            // This operation can run in the memory-constrainted NSE, so trade off a
            // bit of speed to save memory.
            var uniqueIdsToRemove = [String]()
            SignalAccount.anyEnumerate(transaction: transaction, batchingPreference: .batched(8)) { signalAccount, _ in
                if let phoneNumber = E164(signalAccount.recipientPhoneNumber), setOfPhoneNumbers.contains(phoneNumber) {
                    // This contact was received in this batch, so don't remove it.
                    return
                }
                uniqueIdsToRemove.append(signalAccount.uniqueId)
            }
            Logger.info("Removing \(uniqueIdsToRemove.count) contacts during contact sync")
            for uniqueId in uniqueIdsToRemove {
                autoreleasepool {
                    guard let signalAccount = SignalAccount.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
                        return
                    }
                    signalAccount.anyRemove(transaction: transaction)
                }
            }
            if !uniqueIdsToRemove.isEmpty {
                SSKEnvironment.shared.contactManagerImplRef.didUpdateSignalAccounts(transaction: transaction)
            }
        }
    }
}
