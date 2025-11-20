//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

public struct NeedsListMediaError: Error {}

public struct ListMediaIntegrityCheckResult: Codable {
    public struct Result: Codable {
        /// Count of attachments we expected to see on CDN and did see on CDN.
        /// This count is "good".
        public fileprivate(set) var uploadedCount: Int
        /// Count of attachments we did not expect to see on CDN (because they are ineligible
        /// for backups, e.g. have a DM timer) and did not see on CDN.
        /// This count is "good".
        public fileprivate(set) var ineligibleCount: Int
        /// Count of attachments we expected to see on CDN but did not.
        /// This count is "bad".
        public fileprivate(set) var missingFromCdnCount: Int
        public fileprivate(set) var missingFromCdnSampleAttachmentIds: Set<Attachment.IDType>? = Set()
        /// Count of attachments that exist locally, are eligible for upload, are not marked
        /// uploaded, are not on the CDN, and therefore _should_ be in the upload
        /// queue but are not in the upload queue.
        /// This count is "bad".
        public fileprivate(set) var notScheduledForUploadCount: Int? = 0
        public fileprivate(set) var notScheduledForUploadSampleAttachmentIds: Set<Attachment.IDType>? = Set()
        /// Count of attachments we did not expect to see on CDN but did see.
        /// This count can be "bad" because it could indicate a bug with local state management,
        /// but it could happen in normal edge cases if we just didn't know about a completed upload.
        public fileprivate(set) var discoveredOnCdnCount: Int
        public fileprivate(set) var discoveredOnCdnSampleAttachmentIds: Set<Attachment.IDType>? = Set()

        static var empty: Result {
            return Result(uploadedCount: 0, ineligibleCount: 0, missingFromCdnCount: 0, discoveredOnCdnCount: 0)
        }

        var hasFailures: Bool {
            return missingFromCdnCount > 0 || (notScheduledForUploadCount ?? 0) > 0 || discoveredOnCdnCount > 0
        }

        mutating func addSampleId(_ id: Attachment.IDType, _ keyPath: WritableKeyPath<Result, Set<Attachment.IDType>?>) {
            var sampleIds = self[keyPath: keyPath] ?? Set()
            if sampleIds.count >= 10 {
                // Only keep 10 ids
                return
            }
            sampleIds.insert(id)
            self[keyPath: keyPath] = sampleIds
        }
    }

    public let listMediaStartTimestamp: UInt64
    public fileprivate(set) var fullsize: Result
    public fileprivate(set) var thumbnail: Result
    /// Objects we discovered on CDN that don't match any local attachment;
    /// we can't know if these were thumbnails or fullsize.
    /// This count is "bad".
    public fileprivate(set) var orphanedObjectCount: Int

    var hasFailures: Bool {
        if fullsize.uploadedCount == 0 {
            // The first time we run list media, we have no
            // uploads, so don't count as a failure.
            return false
        }

        // Don't count thumbnail failures
        // Don't count orphans; we maybe just haven't deleted yet.
        return fullsize.hasFailures
    }
}

public protocol BackupListMediaManager {

    /// Returns true if a list media should be run whenever is next possible.
    func getNeedsQueryListMedia(tx: DBReadTransaction) -> Bool

    func queryListMediaIfNeeded() async throws
}

public class BackupListMediaManagerImpl: BackupListMediaManager {

    private let accountKeyStore: AccountKeyStore
    private let attachmentStore: AttachmentStore
    private let attachmentUploadStore: AttachmentUploadStore
    private let backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
    private let backupAttachmentUploadStore: BackupAttachmentUploadStore
    private let backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore
    private let backupListMediaStore: BackupListMediaStore
    private let backupRequestManager: BackupRequestManager
    private let backupSettingsStore: BackupSettingsStore
    private let dateProvider: DateProvider
    private let db: any DB
    private let kvStore: KeyValueStore
    private let logger: PrefixedLogger
    private let notificationPresenter: NotificationPresenter
    private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore
    private let remoteConfigManager: RemoteConfigManager
    private let serialTaskQueue: SerialTaskQueue
    private let tsAccountManager: TSAccountManager

    public init(
        accountKeyStore: AccountKeyStore,
        attachmentStore: AttachmentStore,
        attachmentUploadStore: AttachmentUploadStore,
        backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
        backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
        backupAttachmentUploadStore: BackupAttachmentUploadStore,
        backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
        backupListMediaStore: BackupListMediaStore,
        backupRequestManager: BackupRequestManager,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        db: any DB,
        notificationPresenter: NotificationPresenter,
        orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
        remoteConfigManager: RemoteConfigManager,
        tsAccountManager: TSAccountManager
    ) {
        self.accountKeyStore = accountKeyStore
        self.attachmentStore = attachmentStore
        self.attachmentUploadStore = attachmentUploadStore
        self.backupAttachmentDownloadProgress = backupAttachmentDownloadProgress
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
        self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
        self.backupAttachmentUploadStore = backupAttachmentUploadStore
        self.backupAttachmentUploadEraStore = backupAttachmentUploadEraStore
        self.backupListMediaStore = backupListMediaStore
        self.backupRequestManager = backupRequestManager
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = KeyValueStore(collection: "ListBackupMediaManager")
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.notificationPresenter = notificationPresenter
        self.orphanedBackupAttachmentStore = orphanedBackupAttachmentStore
        self.remoteConfigManager = remoteConfigManager
        self.serialTaskQueue = SerialTaskQueue()
        self.tsAccountManager = tsAccountManager

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(backupPlanDidChange),
            name: .backupPlanChanged,
            object: nil
        )
    }

    public func getNeedsQueryListMedia(tx: DBReadTransaction) -> Bool {
        return needsToQueryListMedia(tx: tx)
    }

    public func queryListMediaIfNeeded() async throws {
        let task = serialTaskQueue.enqueue { [self] in
            try await _queryListMediaIfNeeded()
        }
        let backgroundTask = OWSBackgroundTask(label: #function) { [task] status in
            switch status {
            case .expired:
                task.cancel()
            case .couldNotStart, .success:
                break
            }
        }
        defer { backgroundTask.end() }
        try await withTaskCancellationHandler(
            operation: { _ = try await task.value },
            onCancel: { task.cancel() }
        )
    }

    private func _queryListMediaIfNeeded() async throws -> ListMediaIntegrityCheckResult? {
        let localAci: Aci?
        let backupKey: MediaRootBackupKey?
        let currentUploadEra: String
        let inProgressUploadEra: String?
        let inProgressStartTimestamp: UInt64?
        let uploadEraOfLastListMedia: String?
        let needsToQuery: Bool
        let hasEverRunListMedia: Bool
        let inProgressIntegrityCheckResult: ListMediaIntegrityCheckResult?
        (
            localAci,
            backupKey,
            currentUploadEra,
            inProgressUploadEra,
            inProgressStartTimestamp,
            uploadEraOfLastListMedia,
            needsToQuery,
            hasEverRunListMedia,
            inProgressIntegrityCheckResult,
        ) = db.read { tx in
            return (
                self.tsAccountManager.localIdentifiers(tx: tx)?.aci,
                accountKeyStore.getMediaRootBackupKey(tx: tx),
                backupAttachmentUploadEraStore.currentUploadEra(tx: tx),
                kvStore.getString(Constants.inProgressUploadEraKey, transaction: tx),
                kvStore.getUInt64(Constants.inProgressListMediaStartTimestampKey, transaction: tx),
                kvStore.getString(Constants.lastListMediaUploadEraKey, transaction: tx),
                needsToQueryListMedia(tx: tx),
                kvStore.getBool(Constants.hasEverRunListMediaKey, defaultValue: false, transaction: tx),
                try? kvStore.getCodableValue(forKey: Constants.inProgressIntegrityCheckResultKey, transaction: tx),
            )
        }

        guard needsToQuery else {
            return nil
        }

        guard let localAci else {
            throw OWSAssertionError("Missing localAci!")
        }
        guard let backupKey else {
            throw OWSAssertionError("Media backup key missing")
        }

        let uploadEraAtStartOfListMedia: String
        let startTimestamp: UInt64
        if let inProgressUploadEra, let inProgressStartTimestamp {
            uploadEraAtStartOfListMedia = inProgressUploadEra
            startTimestamp = inProgressStartTimestamp
        } else {
            startTimestamp = try await db.awaitableWrite { tx in
                try self.willBeginQueryListMedia(
                    currentUploadEra: self.backupAttachmentUploadEraStore.currentUploadEra(tx: tx),
                    tx: tx
                )
            }
            uploadEraAtStartOfListMedia = currentUploadEra
        }

        func isRetryable(_ error: Error) -> Bool {
            error.isNetworkFailureOrTimeout || error.is5xxServiceResponse
        }

        do {
            // List-media is a dependency of lots of Backups-related operations,
            // which means we might have many callers calling us repeatedly. To
            // that end, internally retry network errors so we back off a
            // healthy amount for each of those callers.
            return try await Retry.performWithBackoff(
                maxAttempts: 5,
                isRetryable: isRetryable,
            ) {
                try await _queryListMediaIfNeeded(
                    localAci: localAci,
                    backupKey: backupKey,
                    startTimestamp: startTimestamp,
                    uploadEraAtStartOfListMedia: uploadEraAtStartOfListMedia,
                    currentUploadEra: currentUploadEra,
                    uploadEraOfLastListMedia: uploadEraOfLastListMedia,
                    hasEverRunListMedia: hasEverRunListMedia,
                    inProgressIntegrityCheckResult: inProgressIntegrityCheckResult,
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch where isRetryable(error) {
            throw error
        } catch {
            logger.error("Unretryable failure in list media! \(error)")

            if BuildFlags.Backups.performListMediaIntegrityChecks {
                // Post a notification so we hear about this quickly.
                notificationPresenter.notifyUserOfListMediaIntegrityCheckFailure()
            }

            // We failed for a non-retryable reason: "complete" this attempt
            // so we don't make a doomed attempt for each of our callers.
            await db.awaitableWrite { tx in
                didFinishListMedia(
                    startTimestamp: startTimestamp,
                    integrityCheckResult: nil,
                    tx: tx,
                )
            }

            throw error
        }
    }

    private func _queryListMediaIfNeeded(
        localAci: Aci,
        backupKey: MediaRootBackupKey,
        startTimestamp: UInt64,
        uploadEraAtStartOfListMedia: String,
        currentUploadEra: String,
        uploadEraOfLastListMedia: String?,
        hasEverRunListMedia: Bool,
        inProgressIntegrityCheckResult: ListMediaIntegrityCheckResult?,
    ) async throws -> ListMediaIntegrityCheckResult? {

        let hasCompletedListingMedia: Bool = db.read { tx in
            return kvStore.getBool(
                Constants.hasCompletedListingMediaKey,
                defaultValue: false,
                transaction: tx
            )
        }

        if !hasCompletedListingMedia {
            try await makeListMediaRequest(backupKey: backupKey, localAci: localAci)
        }

        let hasCompletedEnumeratingAttchments: Bool = db.read { tx in
            return kvStore.getBool(
                Constants.hasCompletedEnumeratingAttachmentsKey,
                defaultValue: false,
                transaction: tx
            )
        }

        let integrityChecker: ListMediaIntegrityChecker
        if
            BuildFlags.Backups.performListMediaIntegrityChecks,
            // Skip integrity checks if we're in a new upload era, since we
            // expect media to not yet be uploaded.
            currentUploadEra == uploadEraOfLastListMedia
        {
            integrityChecker = ListMediaIntegrityCheckerImpl(
                inProgressResult: inProgressIntegrityCheckResult,
                listMediaStartTimestamp: startTimestamp,
                uploadEraAtStartOfListMedia: uploadEraAtStartOfListMedia,
                uploadEraOfLastListMedia: uploadEraOfLastListMedia,
                attachmentStore: attachmentStore,
                backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                backupAttachmentUploadStore: backupAttachmentUploadStore,
                notificationPresenter: notificationPresenter,
                orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
            )
        } else {
            integrityChecker = ListMediaIntegrityCheckerStub()
        }

        if !hasCompletedEnumeratingAttchments {
            let remoteConfig = remoteConfigManager.currentConfig()
            _ = try await TimeGatedBatch.processAllAsync(db: db, errorTxCompletion: .rollback) { tx in
                try Task.checkCancellation()
                let currentBackupPlan = backupSettingsStore.backupPlan(tx: tx)
                var query = Attachment.Record
                    .order(Column(Attachment.Record.CodingKeys.sqliteId).asc)
                    .filter(Column(Attachment.Record.CodingKeys.mediaName) != nil)
                    .limit(50)
                if
                    let lastAttachmentId: Attachment.IDType = kvStore.getInt64(
                        Constants.lastEnumeratedAttachmentIdKey,
                        transaction: tx
                    )
                {
                    query = query
                        .filter(Column(Attachment.Record.CodingKeys.sqliteId) > lastAttachmentId)
                }
                let attachments = try query.fetchAll(tx.database)

                for attachmentRecord in attachments {
                    let attachment = try Attachment(record: attachmentRecord)
                    guard let fullsizeMediaName = attachment.mediaName else {
                        owsFailDebug("We filtered by mediaName presence, how is it missing")
                        continue
                    }

                    // Check for matches for both the fullsize and the
                    // thumbnail mediaId. Fullsize first.
                    try self.updateAttachmentIfNeeded(
                        attachment: attachment,
                        fullsizeMediaName: fullsizeMediaName,
                        isThumbnail: false,
                        backupKey: backupKey,
                        uploadEraAtStartOfListMedia: uploadEraAtStartOfListMedia,
                        currentBackupPlan: currentBackupPlan,
                        remoteConfig: remoteConfig,
                        hasEverRunListMedia: hasEverRunListMedia,
                        integrityChecker: integrityChecker,
                        tx: tx
                    )

                    // Refetch the attachment to reload any mutations applied
                    // by the fullsize matching.
                    guard let attachment = attachmentStore.fetch(id: attachment.id, tx: tx) else {
                        continue
                    }
                    try self.updateAttachmentIfNeeded(
                        attachment: attachment,
                        fullsizeMediaName: fullsizeMediaName,
                        isThumbnail: true,
                        backupKey: backupKey,
                        uploadEraAtStartOfListMedia: uploadEraAtStartOfListMedia,
                        currentBackupPlan: currentBackupPlan,
                        remoteConfig: remoteConfig,
                        hasEverRunListMedia: hasEverRunListMedia,
                        integrityChecker: integrityChecker,
                        tx: tx
                    )
                }
                let lastAttachmentId = attachments.last?.sqliteId
                if let lastAttachmentId {
                    kvStore.setInt64(lastAttachmentId, key: Constants.lastEnumeratedAttachmentIdKey, transaction: tx)
                } else {
                    // We're done
                    kvStore.removeValue(forKey: Constants.lastEnumeratedAttachmentIdKey, transaction: tx)
                    kvStore.setBool(true, key: Constants.hasCompletedEnumeratingAttachmentsKey, transaction: tx)
                }

                if let integrityCheckResult = integrityChecker.result {
                    try? kvStore.setCodable(integrityCheckResult, key: Constants.inProgressIntegrityCheckResultKey, transaction: tx)
                }

                return attachments.count
            }
        }

        // Any remaining attachments in the table weren't matched against a local attachment
        // and should be marked for deletion.
        // If we created a new attachment stream between when we checked every attachment
        // above and now, that attachment will be queued for media tier upload, and that
        // media tier upload job will cancel the orphan job we schedule here.
        _ = try await TimeGatedBatch.processAllAsync(db: db, errorTxCompletion: .rollback) { tx in
            try Task.checkCancellation()
            let listedMediaObjects = try ListedBackupMediaObject
                .limit(100)
                .fetchAll(tx.database)
            for listedMediaObject in listedMediaObjects {
                try enqueueListedMediaForDeletion(listedMediaObject, tx: tx)
                try listedMediaObject.delete(tx.database)
            }
            for listedMediaObject in listedMediaObjects {
                integrityChecker.updateWithOrphanedObject(
                    mediaId: listedMediaObject.mediaId,
                    backupKey: backupKey,
                    tx: tx
                )
            }
            if let integrityCheckResult = integrityChecker.result {
                try kvStore.setCodable(integrityCheckResult, key: Constants.inProgressIntegrityCheckResultKey, transaction: tx)
            }
            return listedMediaObjects.count
        }

        let needsToRunAgain = await db.awaitableWrite { tx in
            self.didFinishListMedia(startTimestamp: startTimestamp, integrityCheckResult: integrityChecker.result, tx: tx)
            return needsToQueryListMedia(tx: tx)
        }

        integrityChecker.logAndNotifyIfNeeded()

        if needsToRunAgain {
            // Return the first integrity check result, not the second, because
            // usually earlier results are more interesting. Once we run list
            // media once, we've already synced local and remote state.
            _ = try await _queryListMediaIfNeeded()
        }
        return integrityChecker.result
    }

    // MARK: Remote attachment mapping

    private struct ListedBackupMediaObject: Codable, FetchableRecord, MutablePersistableRecord {
        // SQLite row id
        var id: Int64?
        // Either fullsize or thumbnail media id; the server doesn't know.
        let mediaId: Data
        let cdnNumber: UInt32
        // Size on the cdn according to the server
        let objectLength: UInt32

        init(
            mediaId: Data,
            cdnNumber: UInt32,
            objectLength: UInt32,
        ) {
            self.mediaId = mediaId
            self.cdnNumber = cdnNumber
            self.objectLength = objectLength
        }

        public static var databaseTableName: String { "ListedBackupMediaObject" }

        mutating func didInsert(with rowID: Int64, for column: String?) {
            self.id = rowID
        }

        enum CodingKeys: CodingKey {
            case id
            case mediaId
            case cdnNumber
            case objectLength
        }
    }

    /// Query the list media endpoint, building the ListedBackupMediaObject table in the databse.
    ///
    /// The server lists media by mediaId, which we do not store because it is derived from the
    /// mediaName via the backup key (which can change). Therefore, to match against local
    /// attachments we need to index over them all and derive their mediaIds, and match against
    /// the already-persisted server objects.
    private func makeListMediaRequest(
        backupKey: MediaRootBackupKey,
        localAci: Aci,
    ) async throws {
        let backupAuth: BackupServiceAuth = try await backupRequestManager.fetchBackupServiceAuth(
            for: backupKey,
            localAci: localAci,
            auth: .implicit(),
        )

        var nextCursor: String? = db.read { tx in
            return kvStore.getString(Constants.paginationCursorKey, transaction: tx)
        }

        while true {
            try Task.checkCancellation()
            let page = try await backupRequestManager.listMediaObjects(
                cursor: nextCursor,
                limit: nil, /* let the server determine the page size */
                auth: backupAuth
            )
            try await persistListedMediaPage(page)
            if let cursor = page.cursor {
                nextCursor = cursor
            } else {
                // Done
                return
            }
        }
    }

    private func persistListedMediaPage(
        _ page: BackupArchive.Response.ListMediaResult
    ) async throws {
        try await db.awaitableWriteWithRollbackIfThrows { tx in
            for listedMediaObject in page.storedMediaObjects {
                guard let mediaId = try? Data.data(fromBase64Url: listedMediaObject.mediaId) else {
                    owsFailDebug("Invalid mediaId from server!")
                    continue
                }
                guard let objectLength = UInt32(exactly: listedMediaObject.objectLength) else {
                    owsFailDebug("Listed object too large!")
                    continue
                }
                var record = ListedBackupMediaObject(
                    mediaId: mediaId,
                    cdnNumber: listedMediaObject.cdn,
                    objectLength: objectLength
                )

                try record.insert(tx.database)
            }
            if let cursor = page.cursor {
                kvStore.setString(
                    cursor,
                    key: Constants.paginationCursorKey,
                    transaction: tx
                )
            } else {
                // We've reached the last page, mark complete.
                kvStore.removeValue(forKey: Constants.paginationCursorKey, transaction: tx)
                kvStore.setBool(
                    true,
                    key: Constants.hasCompletedListingMediaKey,
                    transaction: tx
                )
            }
        }
    }

    // MARK: Per-Attachment handling

    /// Given an attachment, match it against any listed media in the
    /// ListedBackupMediaObject table, and update it as needed.
    ///
    /// - parameter uploadEraAtStartOfListMedia: The most we can guarantee is
    /// that the listed cdn info is accurate as of the upload era we had when we started listing
    /// media. Because the request is paginated (and this whole job is durable), the upload era
    /// may have since changed, which may make the cdn info now invalid. We will still use
    /// maybe-outdated cdn info at download time; we just don't want to overpromise and assume
    /// its using the uploadEra as of the time we process he listed media.
    /// - parameter currentBackupPlan: Unlike upload era, we want this backup plan to
    /// be the latest as of processing time; we will enqueue.dequeue uploads/downloads based
    /// on backupPlan so whatever the backupPlan was when we started list media doesn't matter,
    /// we upload and download _now_ based on plan state _now_.
    private func updateAttachmentIfNeeded(
        attachment: Attachment,
        fullsizeMediaName: String,
        isThumbnail: Bool,
        backupKey: MediaRootBackupKey,
        uploadEraAtStartOfListMedia: String,
        currentBackupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        hasEverRunListMedia: Bool,
        integrityChecker: ListMediaIntegrityChecker,
        tx: DBWriteTransaction
    ) throws {
        // Either the fullsize or the thumbnail media name
        let mediaName: String
        // Either the fullsize of the thumbnail cdn number if we have it
        let localCdnNumber: UInt32?
        if isThumbnail {
            mediaName = AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: fullsizeMediaName)
            localCdnNumber = attachment.thumbnailMediaTierInfo?.cdnNumber
        } else {
            mediaName = fullsizeMediaName
            localCdnNumber = attachment.mediaTierInfo?.cdnNumber
        }

        let mediaId = try backupKey.deriveMediaId(mediaName)

        let matchedListedMedias = try ListedBackupMediaObject
            .filter(Column(ListedBackupMediaObject.CodingKeys.mediaId) == mediaId)
            .order(Column(ListedBackupMediaObject.CodingKeys.id).asc)
            .fetchAll(tx.database)

        guard
            let matchedListedMedia = preferredListedMedia(
                matchedListedMedias,
                localCdnNumber: localCdnNumber,
                remoteConfig: remoteConfig
            )
        else {
            // Call this _before_ we update the attachment; we want to check
            // against the old local state vs remote state.
            integrityChecker.updateWithUnuploadedAttachment(
                attachment: attachment,
                isFullsize: !isThumbnail,
                tx: tx
            )

            // No listed media matched our local attachment.
            // Mark media tier info (if any) as expired.
            try self.markMediaTierUploadExpiredIfNeeded(
                attachment,
                isThumbnail: isThumbnail,
                currentBackupPlan: currentBackupPlan,
                uploadEraAtStartOfListMedia: uploadEraAtStartOfListMedia,
                remoteConfig: remoteConfig,
                hasEverRunListMedia: hasEverRunListMedia,
                tx: tx
            )
            return
        }

        // Call this _before_ we update the attachment; we want to check
        // against the old local state vs remote state.
        integrityChecker.updateWithUploadedAttachment(
            attachment: attachment,
            isFullsize: !isThumbnail,
            remoteCdnNumber: matchedListedMedia.cdnNumber,
            tx: tx
        )

        if matchedListedMedia.cdnNumber == localCdnNumber {
            // Local and remote state match, nothing to update!
            // Clear out the matched listed media row so we don't
            // mark the upload for deletion later.
            try matchedListedMedia.delete(tx.database)
        }

        // Otherwise we either don't have a local cdn number,
        // or we prefer the cdn number listed. In either case,
        // uplate our local attachment with listed cdn info.
        try self.updateWithListedCdn(
            attachment,
            listedMedia: matchedListedMedia,
            isThumbnail: isThumbnail,
            fullsizeMediaName: fullsizeMediaName,
            uploadEraAtStartOfListMedia: uploadEraAtStartOfListMedia,
            currentBackupPlan: currentBackupPlan,
            remoteConfig: remoteConfig,
            tx: tx
        )
        // Clear out the matched listed media row so we don't
        // mark the upload for deletion later.
        try matchedListedMedia.delete(tx.database)
    }

    /// It is possible (though unusual) to end up with the same object (same mediaId)
    /// on multiple CDNs. (e.g. if we delete an attachnent then having it forwarded to
    /// us again with the same encryption key, then we reupload to media tier and get
    /// a different CDN number).
    ///
    /// This method, given an array of listed media objects with the same mediaId,
    /// returns the preferred object to keep, with the rest being eligible to be deleted
    /// from the media tier.
    ///
    /// In general we want to keep the most "recent" CDN number; the one the server
    /// most recently gave us in an upload form and therefore the most up to date.
    /// We don't know this directly, but if our local copy of an attachment has a cdn
    /// number on it, that means its the most recent upload _this device_ knows about,
    /// so we prefer that. Otherwise let the server choose by picking the one in our
    /// remote config or, lastly, the first one the list media endpoint gave us.
    private func preferredListedMedia(
        _ listedMedias: [ListedBackupMediaObject],
        localCdnNumber: UInt32?,
        remoteConfig: RemoteConfig
    ) -> ListedBackupMediaObject? {
        var preferredListedMedia: ListedBackupMediaObject?
        for listedMedia in listedMedias {
            if listedMedia.cdnNumber == localCdnNumber {
                // Always prefer the one matching the local cdn number,
                // if we have one, on the assumption that the local value
                // represents the most recent upload (the upload on this
                // current, registered device), and therefore the most
                // recent determination by the server of which CDN to use.
                return listedMedia
            }
            if listedMedia.cdnNumber == remoteConfig.mediaTierFallbackCdnNumber {
                // Prefer the remote config cdn number, as we can at least
                // somewhat control this remotely.
                preferredListedMedia = listedMedia
            } else if preferredListedMedia == nil {
                // Otherwise take the first one given to us by the server.
                preferredListedMedia = listedMedia
            }
        }
        return preferredListedMedia
    }

    /// We have a local attachment not represented in listed media;
    /// mark any media tier info as expired/invalid/gone.
    private func markMediaTierUploadExpiredIfNeeded(
        _ attachment: Attachment,
        isThumbnail: Bool,
        currentBackupPlan: BackupPlan,
        uploadEraAtStartOfListMedia: String,
        remoteConfig: RemoteConfig,
        hasEverRunListMedia: Bool,
        tx: DBWriteTransaction
    ) throws {
        if isThumbnail, let thumbnailMediaTierInfo = attachment.thumbnailMediaTierInfo {
            if thumbnailMediaTierInfo.uploadEra == uploadEraAtStartOfListMedia {
                logger.warn("Unexpectedly missing thumbnail we thought was on media tier cdn \(attachment.id)")
            } else {
                // The uploadEra has rotated, so it's reasonable that the
                // attachment is un-uploaded.
            }

            try self.attachmentUploadStore.markThumbnailMediaTierUploadExpired(
                attachment: attachment,
                tx: tx
            )
        }

        if !isThumbnail, let mediaTierInfo = attachment.mediaTierInfo {
            if mediaTierInfo.uploadEra == uploadEraAtStartOfListMedia {
                logger.warn("Unexpectedly missing fullsize we thought was on media tier cdn \(attachment.id)")
            } else {
                // The uploadEra has rotated, so it's reasonable that the
                // attachment is un-uploaded.
            }

            try self.attachmentUploadStore.markMediaTierUploadExpired(
                attachment: attachment,
                tx: tx
            )
        }

        // Refetch the attachment so it reflects the latest updates.
        guard let attachment = attachmentStore.fetch(id: attachment.id, tx: tx) else {
            throw OWSAssertionError("How did the attachment get deleted?")
        }

        // If the media tier upload we had was expired, we need to
        // reupload, so enqueue that.
        // Note: we enqueue uploads on non-primary devices; the uploads
        // just won't be run.
        try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
            attachment,
            mode: isThumbnail ? .thumbnailOnly : .fullsizeOnly,
            tx: tx
        )

        if
            let existingDownload = try backupAttachmentDownloadStore.getEnqueuedDownload(
                attachmentRowId: attachment.id,
                thumbnail: isThumbnail,
                tx: tx
            )
        {
            try self.cancelEnqueuedDownload(
                existingDownload,
                for: attachment,
                isThumbnail: isThumbnail,
                currentBackupPlan: currentBackupPlan,
                remoteConfig: remoteConfig,
                tx: tx
            )
        }
    }

    private func cancelEnqueuedDownload(
        _ existingDownload: QueuedBackupAttachmentDownload,
        for attachment: Attachment,
        isThumbnail: Bool,
        currentBackupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        tx: DBWriteTransaction
    ) throws {
        try backupAttachmentDownloadStore.remove(
            attachmentId: attachment.id,
            thumbnail: isThumbnail,
            tx: tx
        )
        // Mark the cancelled download as "finished" because it was cancelled,
        // but we want the progress bar to complete.
        var shouldMarkDownloadProgressFinished = true
        if
            !isThumbnail,
            let transitTierEligibilityState = BackupAttachmentDownloadEligibility.transitTierFullsizeState(
                attachment: attachment,
                attachmentTimestamp: existingDownload.maxOwnerTimestamp,
                currentTimestamp: dateProvider().ows_millisecondsSince1970,
                remoteConfig: remoteConfig,
                backupPlan: currentBackupPlan,
                isPrimaryDevice: true // Only primaries run list-media
            )
        {
            // We just found we can't download from media tier, but
            // fullsize downloads can also come from transit tier (and
            // are represented by the same download row). If indeed eligible,
            // re-enqueue as just a transit tier download.
            var existingDownload = existingDownload
            existingDownload.id = nil
            existingDownload.canDownloadFromMediaTier = false
            existingDownload.state = transitTierEligibilityState
            try existingDownload.insert(tx.database)
            shouldMarkDownloadProgressFinished = false
        }
        if shouldMarkDownloadProgressFinished {
            tx.addSyncCompletion {
                if !isThumbnail {
                    Task {
                        await self.backupAttachmentDownloadProgress.didFinishDownloadOfFullsizeAttachment(
                            withId: attachment.id,
                            byteCount: UInt64(QueuedBackupAttachmentDownload.estimatedByteCount(
                                attachment: attachment,
                                reference: nil,
                                isThumbnail: isThumbnail,
                                canDownloadFromMediaTier: true
                            ))
                        )
                    }
                }
            }
        }
    }

    /// Update a local attachment with matched listed media cdn info.
    /// The local attachment may or may not already have media tier
    /// cdn information; it will be overwritten.
    private func updateWithListedCdn(
        _ attachment: Attachment,
        listedMedia: ListedBackupMediaObject,
        isThumbnail: Bool,
        fullsizeMediaName: String,
        uploadEraAtStartOfListMedia: String,
        currentBackupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        tx: DBWriteTransaction
    ) throws {
        // Update the attachment itself.
        let didSetCdnInfo = try self.updateCdnInfoIfPossible(
            of: attachment,
            from: listedMedia,
            isThumbnail: isThumbnail,
            uploadEraAtStartOfListMedia: uploadEraAtStartOfListMedia,
            fullsizeMediaName: fullsizeMediaName,
            tx: tx
        )

        var attachment = attachment
        if didSetCdnInfo {
            // Refetch the attachment so we have the latest info.
            guard let refetched = attachmentStore.fetch(id: attachment.id, tx: tx) else {
                throw OWSAssertionError("Attachment gone? How?")
            }
            attachment = refetched
        }

        // Since we now know this is uploaded, we can go ahead and remove
        // from the upload queue if present.
        if
            let finishedRecord = try backupAttachmentUploadStore.markUploadDone(
                for: attachment.id,
                fullsize: isThumbnail.negated,
                tx: tx,
                file: nil,
                function: nil,
                line: nil
            )
        {
            logger.info("Marked discovered attachment \(attachment.id) done. fullsize? \(isThumbnail.negated)")
            if finishedRecord.isFullsize {
                Task {
                    await backupAttachmentUploadProgress.didFinishUploadOfFullsizeAttachment(
                        uploadRecord: finishedRecord
                    )
                }
            }
        }

        // Enqueue a download from the newly-discovered cdn info.
        // If it was already enqueued, won't hurt anything.
        try enqueueDownloadIfNeeded(
            attachment: attachment,
            isThumbnail: isThumbnail,
            currentBackupPlan: currentBackupPlan,
            remoteConfig: remoteConfig,
            tx: tx
        )
    }

    /// - returns True if cdn info was set
    private func updateCdnInfoIfPossible(
        of attachment: Attachment,
        from listedMedia: ListedBackupMediaObject,
        isThumbnail: Bool,
        uploadEraAtStartOfListMedia: String,
        fullsizeMediaName: String,
        tx: DBWriteTransaction
    ) throws -> Bool {
        if isThumbnail {
            // Thumbnails are easy; no additional metadata is needed.
            try attachmentUploadStore.markThumbnailUploadedToMediaTier(
                attachment: attachment,
                thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo(
                    cdnNumber: listedMedia.cdnNumber,
                    uploadEra: uploadEraAtStartOfListMedia,
                    lastDownloadAttemptTimestamp: nil
                ),
                mediaName: fullsizeMediaName,
                tx: tx
            )
            return true
        }
        // In order for the fullsize attachment to download, we need some metadata.
        // We might have this either from a local stream (if we matched against
        // the media name/id we generated locally) or from a restored backup (if
        // we matched against the media name/id we pulled off the backup proto).
        let fullsizeUnencryptedByteCount = attachment.mediaTierInfo?.unencryptedByteCount
            ?? attachment.streamInfo?.unencryptedByteCount
        let fullsizeSHA256ContentHash = attachment.mediaTierInfo?.sha256ContentHash
            ?? attachment.streamInfo?.sha256ContentHash
            ?? attachment.sha256ContentHash
        guard
            let fullsizeUnencryptedByteCount,
            let fullsizeSHA256ContentHash
        else {
            // We have a matching local attachment but we don't have
            // sufficient metadata from either a backup or local stream
            // to be able to download, anyway. Schedule the upload for
            // deletion, its unuseable. This should never happen*, because
            // how would we have a media id to match against but lack the
            // other info?
            // * never, unless we trigger a manual list media before
            // OrphanedBackupAttachmentManager finishes.
            logger.error("Missing media tier metadata but matched by media id somehow")
            try enqueueListedMediaForDeletion(listedMedia, tx: tx)
            return false
        }

        try attachmentUploadStore.markUploadedToMediaTier(
            attachment: attachment,
            mediaTierInfo: Attachment.MediaTierInfo(
                cdnNumber: listedMedia.cdnNumber,
                unencryptedByteCount: fullsizeUnencryptedByteCount,
                sha256ContentHash: fullsizeSHA256ContentHash,
                incrementalMacInfo: attachment.mediaTierInfo?.incrementalMacInfo,
                uploadEra: uploadEraAtStartOfListMedia,
                lastDownloadAttemptTimestamp: nil
            ),
            mediaName: fullsizeMediaName,
            tx: tx
        )
        return true
    }

    private func enqueueDownloadIfNeeded(
        attachment: Attachment,
        isThumbnail: Bool,
        currentBackupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        tx: DBWriteTransaction
    ) throws {
        let currentTimestamp = dateProvider().ows_millisecondsSince1970

        // We only want to fetch all references if we need to (since its expensive)
        // but if we do so ensure we only do so once across multiple usage sites.
        var cachedMostRecentReference: AttachmentReference?
        func fetchMostRecentReference() throws -> AttachmentReference {
            if let cachedMostRecentReference { return cachedMostRecentReference }
            let reference = try self.attachmentStore.fetchMostRecentReference(toAttachmentId: attachment.id, tx: tx)
            cachedMostRecentReference = reference
            return reference
        }

        // We check only media tier eligibility, as that's what may have changed
        // as a result of list media. The attachment may already have been eligible
        // for transit tier download; we will just overwrite the already enqueued download.
        let mediaTierDownloadState: QueuedBackupAttachmentDownload.State?
        // But to actually enqueue, we want the combined transit + media tier state
        // so that we don't overwrite existing transit tier state incorrectly.
        let combinedDownloadState: QueuedBackupAttachmentDownload.State?
        if isThumbnail {
            mediaTierDownloadState = try BackupAttachmentDownloadEligibility.mediaTierThumbnailState(
                attachment: attachment,
                backupPlan: currentBackupPlan,
                attachmentTimestamp: try {
                    switch try fetchMostRecentReference().owner {
                    case .message(let messageSource):
                        return messageSource.receivedAtTimestamp
                    case .thread, .storyMessage:
                        return nil
                    }
                }(),
                currentTimestamp: currentTimestamp,
            )
            combinedDownloadState = mediaTierDownloadState
        } else {
            let eligibility = try BackupAttachmentDownloadEligibility.forAttachment(
                attachment,
                reference: try fetchMostRecentReference(),
                currentTimestamp: currentTimestamp,
                backupPlan: currentBackupPlan,
                remoteConfig: remoteConfig,
                isPrimaryDevice: true // Only primaries run list-media
            )
            mediaTierDownloadState = eligibility.fullsizeMediaTierState
            combinedDownloadState = eligibility.fullsizeState
        }

        guard let mediaTierDownloadState, let combinedDownloadState else {
            // Not possible to download.
            return
        }

        switch mediaTierDownloadState {
        case .done:
            // Don't bother enqueueing if already done.
            return
        case .ineligible:
            // Its ineligible now due to backupPlan state, but we should
            // still enqueue it (as ineligible) so it can become ready later
            // if backupPlan state changes.
            fallthrough
        case .ready:
            // Dequeue any existing download first; this will reset the retry counter
            try backupAttachmentDownloadStore.remove(
                attachmentId: attachment.id,
                thumbnail: isThumbnail,
                tx: tx
            )

            _ = try backupAttachmentDownloadStore.enqueue(
                ReferencedAttachment(
                    reference: try fetchMostRecentReference(),
                    attachment: attachment
                ),
                thumbnail: isThumbnail,
                // We got here because we discovered we can download
                // from media tier, that's the whole point.
                canDownloadFromMediaTier: true,
                state: combinedDownloadState,
                currentTimestamp: currentTimestamp,
                tx: tx
            )
        }
    }

    private func enqueueListedMediaForDeletion(
        _ listedMedia: ListedBackupMediaObject,
        tx: DBWriteTransaction
    ) throws {
        var orphanRecord = OrphanedBackupAttachment.discoveredOnServer(
            cdnNumber: listedMedia.cdnNumber,
            mediaId: listedMedia.mediaId
        )
        try orphanedBackupAttachmentStore.insert(&orphanRecord, tx: tx)
    }

    // MARK: State

    private func needsToQueryListMedia(tx: DBReadTransaction) -> Bool {
        guard tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice else {
            return false
        }

        switch backupSettingsStore.backupPlan(tx: tx) {
        case .disabled, .disabling, .free:
            return false
        case .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        if kvStore.getString(Constants.inProgressUploadEraKey, transaction: tx) != nil {
            return true
        }

        guard let lastQueriedUploadEra = kvStore.getString(Constants.lastListMediaUploadEraKey, transaction: tx) else {
            // We've never run list-media on this device! Do so now. (This
            // ensures we run a list-media after restoring onto a new device.)
            return true
        }

        if backupAttachmentUploadEraStore.currentUploadEra(tx: tx) != lastQueriedUploadEra {
            return true
        }

        if backupListMediaStore.getManualNeedsListMedia(tx: tx) {
            return true
        }

        // As a catch-all defense against bugs or whatever else, periodically
        // query to make sure our local state is in sync with the server.
        let nextPeriodicListMediaDate: Date = {
            guard
                let lastListMediaDate = kvStore
                    .getUInt64(Constants.lastListMediaStartTimestampKey, transaction: tx)
                    .map({ Date(millisecondsSince1970: $0) })
            else {
                return .distantPast
            }

            let remoteConfig = remoteConfigManager.currentConfig()
            let refreshInterval: TimeInterval
            if backupSettingsStore.hasConsumedMediaTierCapacity(tx: tx) {
                refreshInterval = remoteConfig.backupListMediaOutOfQuotaRefreshInterval
            } else {
                refreshInterval = remoteConfig.backupListMediaDefaultRefreshInterval
            }

            return lastListMediaDate.addingTimeInterval(refreshInterval)
        }()

        return dateProvider() > nextPeriodicListMediaDate
    }

    /// Returns start timestamp for this run
    private func willBeginQueryListMedia(
        currentUploadEra: String,
        tx: DBWriteTransaction
    ) throws -> UInt64 {
        let startTimestamp = dateProvider().ows_millisecondsSince1970
        if kvStore.getString(Constants.inProgressUploadEraKey, transaction: tx) != nil {
            guard let startTimestamp = kvStore.getUInt64(Constants.inProgressListMediaStartTimestampKey, transaction: tx) else {
                owsFailDebug("Missing start timestamp!")
                return startTimestamp
            }
            return startTimestamp
        }
        try ListedBackupMediaObject.deleteAll(tx.database)
        self.kvStore.setString(currentUploadEra, key: Constants.inProgressUploadEraKey, transaction: tx)
        self.kvStore.setUInt64(
            startTimestamp,
            key: Constants.inProgressListMediaStartTimestampKey,
            transaction: tx
        )
        return startTimestamp
    }

    private func didFinishListMedia(
        startTimestamp: UInt64,
        integrityCheckResult: ListMediaIntegrityCheckResult?,
        tx: DBWriteTransaction
    ) {
        self.kvStore.setBool(true, key: Constants.hasEverRunListMediaKey, transaction: tx)
        if let uploadEra = kvStore.getString(Constants.inProgressUploadEraKey, transaction: tx) {
            self.kvStore.setString(uploadEra, key: Constants.lastListMediaUploadEraKey, transaction: tx)
            self.kvStore.removeValue(forKey: Constants.inProgressUploadEraKey, transaction: tx)
        } else {
            owsFailDebug("Missing in progress upload era?")
        }
        self.kvStore.setUInt64(startTimestamp, key: Constants.lastListMediaStartTimestampKey, transaction: tx)
        backupListMediaStore.setManualNeedsListMedia(false, tx: tx)
        kvStore.removeValue(forKey: Constants.inProgressListMediaStartTimestampKey, transaction: tx)

        if let integrityCheckResult {
            if integrityCheckResult.hasFailures {
                try? backupListMediaStore.setLastFailingIntegrityCheckResult(integrityCheckResult, tx: tx)
            }
            try? backupListMediaStore.setMostRecentIntegrityCheckResult(integrityCheckResult, tx: tx)
        }
        kvStore.removeValue(forKey: Constants.inProgressIntegrityCheckResultKey, transaction: tx)

        self.kvStore.setBool(false, key: Constants.hasCompletedListingMediaKey, transaction: tx)
        kvStore.removeValue(forKey: Constants.paginationCursorKey, transaction: tx)
        self.kvStore.setBool(false, key: Constants.hasCompletedEnumeratingAttachmentsKey, transaction: tx)
        self.kvStore.removeValue(forKey: Constants.lastEnumeratedAttachmentIdKey, transaction: tx)
    }

    @objc
    private func backupPlanDidChange() {
        Task {
            switch self.db.read(block: backupSettingsStore.backupPlan(tx:)) {
            case .free, .paid, .paidAsTester, .paidExpiringSoon, .disabling:
                return
            case .disabled:
                // Rotate the last integrity check failure when disabled
                await self.db.awaitableWrite { tx in
                    try? self.backupListMediaStore.setLastFailingIntegrityCheckResult(nil, tx: tx)
                    try? self.backupListMediaStore.setMostRecentIntegrityCheckResult(nil, tx: tx)
                }
            }
        }
    }

    private enum Constants {
        /// Maps to the upload era (active subscription) when we last queried the list media
        /// endpoint, or nil if its never been queried.
        static let lastListMediaUploadEraKey = "lastListMediaUploadEra"

        /// Maps to the timestamp we last completed a list media request.
        static let lastListMediaStartTimestampKey = "lastListMediaTimestamp"
        static let inProgressListMediaStartTimestampKey = "inProgressListMediaTimestamp"

        /// True if we've ever run list media in the lifetime of this app.
        static let hasEverRunListMediaKey = "hasEverRunListMedia"

        /// If there is a list media in progress, the value at this key is the upload era that was set
        /// at the start of that in progress run.
        static let inProgressUploadEraKey = "inProgressUploadEraKey"

        /// If we have finished all pages of the list media request, hasCompletedPaginationKey's value
        /// will be true. If not, paginationCursorKey points to the cursor provided by the server on the last
        /// page, or nil if no pages have finished processing yet.
        static let paginationCursorKey = "paginationCursorKey"
        static let hasCompletedListingMediaKey = "hasCompletedListingMediaKey"

        /// If we have finished enumerating all attachments to compare to listed media,
        /// hasCompletedEnumeratingAttachmentsKey''s value will be true.
        /// If not, lastEnumeratedAttachmentIdKey's value is the last attachment id enumerated,
        /// or nil if no attachments have been enumerated yet.
        static let lastEnumeratedAttachmentIdKey = "lastEnumeratedAttachmentIdKey"
        static let hasCompletedEnumeratingAttachmentsKey = "hasCompletedEnumeratingAttachmentsKey"

        static let inProgressIntegrityCheckResultKey = "inProgressIntegrityCheckResultKey"
    }
}

// MARK: -

#if TESTABLE_BUILD

class MockBackupListMediaManager: BackupListMediaManager {

    func getNeedsQueryListMedia(tx: DBReadTransaction) -> Bool {
        return false
    }

    func queryListMediaIfNeeded() async throws {
        // Nothing
    }

    func getLastFailingIntegrityCheckResult(tx: DBReadTransaction) throws -> ListMediaIntegrityCheckResult? {
        nil
    }

    func getMostRecentIntegrityCheckResult(tx: DBReadTransaction) throws -> ListMediaIntegrityCheckResult? {
        nil
    }

    func setManualNeedsListMedia(tx: DBWriteTransaction) {
        // Nothing
    }
}

#endif

private protocol ListMediaIntegrityChecker {

    func updateWithUnuploadedAttachment(
        attachment: Attachment,
        isFullsize: Bool,
        tx: DBReadTransaction
    )

    func updateWithUploadedAttachment(
        attachment: Attachment,
        isFullsize: Bool,
        remoteCdnNumber: UInt32,
        tx: DBReadTransaction
    )

    func updateWithOrphanedObject(
        mediaId: Data,
        backupKey: MediaRootBackupKey,
        tx: DBReadTransaction
    )

    var result: ListMediaIntegrityCheckResult? { get }

    func logAndNotifyIfNeeded()
}

private class ListMediaIntegrityCheckerImpl: ListMediaIntegrityChecker {

    var _result: ListMediaIntegrityCheckResult

    private let uploadEraAtStartOfListMedia: String
    private let uploadEraOfLastListMedia: String?

    private let attachmentStore: AttachmentStore
    private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
    private let backupAttachmentUploadStore: BackupAttachmentUploadStore
    private let logger: PrefixedLogger
    private let notificationPresenter: NotificationPresenter
    private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore

    init(
        inProgressResult: ListMediaIntegrityCheckResult?,
        listMediaStartTimestamp: UInt64,
        uploadEraAtStartOfListMedia: String,
        uploadEraOfLastListMedia: String?,
        attachmentStore: AttachmentStore,
        backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
        backupAttachmentUploadStore: BackupAttachmentUploadStore,
        notificationPresenter: NotificationPresenter,
        orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
    ) {
        self.uploadEraAtStartOfListMedia = uploadEraAtStartOfListMedia
        self.uploadEraOfLastListMedia = uploadEraOfLastListMedia
        self._result = inProgressResult ?? ListMediaIntegrityCheckResult(
            listMediaStartTimestamp: listMediaStartTimestamp,
            fullsize: .empty,
            thumbnail: .empty,
            orphanedObjectCount: 0
        )
        self.attachmentStore = attachmentStore
        self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
        self.backupAttachmentUploadStore = backupAttachmentUploadStore
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.notificationPresenter = notificationPresenter
        self.orphanedBackupAttachmentStore = orphanedBackupAttachmentStore
    }

    func updateWithUploadedAttachment(
        attachment: Attachment,
        isFullsize: Bool,
        remoteCdnNumber: UInt32,
        tx: DBReadTransaction
    ) {
        // If local state says its uploaded, then all is good.
        let localCdnNumber: UInt32?
        let hadMediaTierInfo: Bool
        if isFullsize {
            hadMediaTierInfo = attachment.mediaTierInfo != nil
            localCdnNumber = attachment.mediaTierInfo?.cdnNumber
        } else {
            hadMediaTierInfo = attachment.thumbnailMediaTierInfo != nil
            localCdnNumber = attachment.thumbnailMediaTierInfo?.cdnNumber
        }

        switch localCdnNumber {
        case nil:
            if hadMediaTierInfo {
                // We thought this was uploaded but didn't have the CDN number.
                // This happens with attachments restored from a backup that was
                // created before the attachment got uploaded by the old device;
                // the attachment is optimistically treated as uploaded in the backup.
                // List media discovering the cdn number in this way is expected
                // and good behavior, don't mark any issues.
                _result[keyPath: resultKeyPath(isFullsize: isFullsize)].uploadedCount += 1
                return
            } else {
                // We've discovered this upload on the media tier.
                let enqueuedUpload = try? backupAttachmentUploadStore.getEnqueuedUpload(
                    for: attachment.id,
                    fullsize: isFullsize,
                    tx: tx
                )
                switch enqueuedUpload?.state {
                case .ready:
                    // If it was enqueued for upload, its possible we previously attempted to upload
                    // and succeeded server-side but got interrupted before updating local state after,
                    // so its still in the upload queue. This is ok; we would have re-attempted upload
                    // and found it already uploaded, given the chance.
                    return
                case .done, nil:
                    // If it was not in the queue, that means discovering it on the server is unexpected.
                    _result[keyPath: resultKeyPath(isFullsize: isFullsize)].discoveredOnCdnCount += 1
                    _result[keyPath: resultKeyPath(isFullsize: isFullsize)].addSampleId(attachment.id, \.discoveredOnCdnSampleAttachmentIds)
                    return
                }
            }
        case remoteCdnNumber:
            // Local and remote state match
            _result[keyPath: resultKeyPath(isFullsize: isFullsize)].uploadedCount += 1
        default:
            // We thought it was uploaded, and it was, but at a different cdn number.
            // This is unusual but not catastrophic; for now we only use one cdn
            // number so just count it as uploaded.
            _result[keyPath: resultKeyPath(isFullsize: isFullsize)].uploadedCount += 1
        }
    }

    func updateWithUnuploadedAttachment(
        attachment: Attachment,
        isFullsize: Bool,
        tx: DBReadTransaction
    ) {
        // If local state says its uploaded, and its not, that's a problem.
        if isFullsize {
            if attachment.mediaTierInfo?.isUploaded(currentUploadEra: uploadEraAtStartOfListMedia) == true {
                _result[keyPath: resultKeyPath(isFullsize: isFullsize)].missingFromCdnCount += 1
                _result[keyPath: resultKeyPath(isFullsize: isFullsize)].addSampleId(attachment.id, \.missingFromCdnSampleAttachmentIds)
                return
            }
        } else {
            if attachment.thumbnailMediaTierInfo?.isUploaded(currentUploadEra: uploadEraAtStartOfListMedia) == true {
                _result[keyPath: resultKeyPath(isFullsize: isFullsize)].missingFromCdnCount += 1
                _result[keyPath: resultKeyPath(isFullsize: isFullsize)].addSampleId(attachment.id, \.missingFromCdnSampleAttachmentIds)
                return
            }
        }

        // Its not uploaded; do we think its eligible?
        let isEligible = backupAttachmentUploadScheduler.isEligibleToUpload(
            attachment,
            fullsize: isFullsize,
            currentUploadEra: uploadEraAtStartOfListMedia,
            tx: tx
        )
        if !isEligible {
            // Not uploaded, not eligible. All is good in the world.
            return
        }

        // Check if enqueued for upload.
        let enqueuedUpload = try? backupAttachmentUploadStore.getEnqueuedUpload(
            for: attachment.id,
            fullsize: isFullsize,
            tx: tx
        )
        switch enqueuedUpload?.state {
        case .ready:
            // Not uploaded, but pending upload, this is fine.
            return
        case .done, nil:
            // Not uploaded, eligible, not scheduled. Uh-oh.
            _result[keyPath: resultKeyPath(isFullsize: isFullsize)].notScheduledForUploadCount =
                (_result[keyPath: resultKeyPath(isFullsize: isFullsize)].notScheduledForUploadCount ?? 0) + 1
            _result[keyPath: resultKeyPath(isFullsize: isFullsize)].addSampleId(attachment.id, \.notScheduledForUploadSampleAttachmentIds)
            return
        }

    }

    func updateWithOrphanedObject(
        mediaId: Data,
        backupKey: MediaRootBackupKey,
        tx: DBReadTransaction
    ) {
        if uploadEraOfLastListMedia != uploadEraAtStartOfListMedia {
            // If this is our first list media for this upload era, ignore orphans we see.
            // It is possible that the orphan came from another device, while this device
            // was unregistered or before it ever registered, and that device never got the
            // chance to issue the orphan delete before its process ended.
            return
        }

        // First try and match by mediaId.
        if (try? orphanedBackupAttachmentStore.hasPendingDelete(forMediaId: mediaId, tx: tx)) == true {
            // Its an orphan, but one we know about. skip.
            return
        }
        // Now check mediaNames we have pending delete, map them to mediaId, and try to match.
        var foundMatch = false
        try? orphanedBackupAttachmentStore.enumerateMediaNamesPendingDelete(tx: tx) { mediaName, stop in
            let foundMediaId = try? backupKey.deriveMediaId(mediaName)
            if foundMediaId == mediaId {
                foundMatch = true
                stop = true
            }
        }
        if foundMatch {
            // Its an orphan, but one we know about. skip.
            return
        }
        _result.orphanedObjectCount += 1
    }

    func logAndNotifyIfNeeded() {
        var shouldNotify = false

        logger.info("\(_result.fullsize.uploadedCount) fullsize uploads")
        logger.info("\(_result.fullsize.ineligibleCount) ineligible attachments")
        logger.info("\(_result.thumbnail.uploadedCount) thumbnail uploads")
        logger.info("\(_result.thumbnail.ineligibleCount) ineligible attachments")
        if _result.fullsize.missingFromCdnCount > 0 {
            shouldNotify = true
            logger.error("Missing fullsize uploads from CDN, samples: \(_result.fullsize.missingFromCdnSampleAttachmentIds ?? Set())")
        }
        if (_result.fullsize.notScheduledForUploadCount ?? 0) > 0 {
            shouldNotify = true
            logger.error("Unscheduled fullsize uploads, samples: \(_result.fullsize.notScheduledForUploadSampleAttachmentIds ?? Set())")
        }
        if _result.fullsize.discoveredOnCdnCount > 0 {
            shouldNotify = true
            logger.error("Discovered fullsize upload on CDN, samples: \(_result.fullsize.discoveredOnCdnSampleAttachmentIds ?? Set())")
        }

        // Don't notify for thumbnail issues.
        if _result.thumbnail.missingFromCdnCount > 0 {
            logger.warn("Missing thumbnail uploads from CDN, samples: \(_result.thumbnail.missingFromCdnSampleAttachmentIds ?? Set())")
        }
        if (_result.thumbnail.notScheduledForUploadCount ?? 0) > 0 {
            logger.warn("Unscheduled thumbnail uploads, samples: \(_result.thumbnail.notScheduledForUploadSampleAttachmentIds ?? Set())")
        }
        if _result.thumbnail.discoveredOnCdnCount > 0 {
            logger.warn("Discovered thumbnail upload on CDN, samples: \(_result.thumbnail.discoveredOnCdnSampleAttachmentIds ?? Set())")
        }

        if _result.orphanedObjectCount > 0 {
            shouldNotify = true
            logger.error("Discovered \(_result.orphanedObjectCount) orphans on media tier")
        }

        if shouldNotify {
            notificationPresenter.notifyUserOfListMediaIntegrityCheckFailure()
        }
    }

    private func resultKeyPath(isFullsize: Bool) -> WritableKeyPath<ListMediaIntegrityCheckResult, ListMediaIntegrityCheckResult.Result> {
        return isFullsize ? \.fullsize : \.thumbnail
    }

    var result: ListMediaIntegrityCheckResult? {
        return _result
    }
}

private class ListMediaIntegrityCheckerStub: ListMediaIntegrityChecker {

    init() {}

    func updateWithUploadedAttachment(
        attachment: Attachment,
        isFullsize: Bool,
        remoteCdnNumber: UInt32,
        tx: DBReadTransaction
    ) {}

    func updateWithUnuploadedAttachment(
        attachment: Attachment,
        isFullsize: Bool,
        tx: DBReadTransaction
    ) {}

    func updateWithOrphanedObject(
        mediaId: Data,
        backupKey: MediaRootBackupKey,
        tx: DBReadTransaction
    ) {}

    func logAndNotifyIfNeeded() {}

    var result: ListMediaIntegrityCheckResult? {
        return nil
    }
}
