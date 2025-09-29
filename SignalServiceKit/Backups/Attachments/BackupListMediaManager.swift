//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient

public struct ListMediaIntegrityCheckResult: Codable {
    public struct Result: Codable {
        /// Count of attachments we expected to see on CDN and did see on CDN.
        /// This count is "good".
        public private(set) var uploadedCount: Int
        /// Count of attachments we did not expect to see on CDN (because they are ineligible
        /// for backups, e.g. have a DM timer) and did not see on CDN.
        /// This count is "good".
        public private(set) var ineligibleCount: Int
        /// Count of attachments we expected to see on CDN but did not.
        /// This count is "bad".
        public private(set) var missingFromCdnCount: Int
        /// Count of attachments we did not expect to see on CDN but did see.
        /// This count can be "bad" because it could indicate a bug with local state management,
        /// but it could happen in normal edge cases if we just didn't know about a completed upload.
        public private(set) var discoveredOnCdnCount: Int

        static var empty: Result {
            return Result(uploadedCount: 0, ineligibleCount: 0, missingFromCdnCount: 0, discoveredOnCdnCount: 0)
        }

        var hasFailures: Bool {
            return missingFromCdnCount > 0 || discoveredOnCdnCount > 0
        }

        fileprivate mutating func updateWith(_ attachmentResult: BackupListMediaManagerImpl.AttachmentMatchResult) {
            switch attachmentResult {
            case .uploaded:
                uploadedCount += 1
            case .notUploaded:
                ineligibleCount += 1
            case .missingFromCdn:
                missingFromCdnCount += 1
            case .discoveredOnCdn:
                discoveredOnCdnCount += 1
            }
        }
    }

    public let listMediaStartTimestamp: UInt64
    public fileprivate(set) var fullsize: Result
    public fileprivate(set) var thumbnail: Result
    /// Objects we discovered on CDN that don't match any local attachment;
    /// we can't know if these were thumbnails or fullsize.
    public fileprivate(set) var orphanedObjectCount: Int

    static func empty(listMediaStartTimestamp: UInt64) -> ListMediaIntegrityCheckResult {
        return ListMediaIntegrityCheckResult(
            listMediaStartTimestamp: listMediaStartTimestamp,
            fullsize: .empty,
            thumbnail: .empty,
            orphanedObjectCount: 0
        )
    }

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
    func queryListMediaIfNeeded() async throws

    func getLastFailingIntegrityCheckResult(tx: DBReadTransaction) throws -> ListMediaIntegrityCheckResult?

    func getMostRecentIntegrityCheckResult(tx: DBReadTransaction) throws -> ListMediaIntegrityCheckResult?

    func setManualNeedsListMedia(tx: DBWriteTransaction)
}

final public class BackupListMediaManagerImpl: BackupListMediaManager {

    private let accountKeyStore: AccountKeyStore
    private let attachmentStore: AttachmentStore
    private let attachmentUploadStore: AttachmentUploadStore
    private let backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
    private let backupAttachmentUploadStore: BackupAttachmentUploadStore
    private let backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore
    private let backupRequestManager: BackupRequestManager
    private let backupSettingsStore: BackupSettingsStore
    private let dateProvider: DateProvider
    private let db: any DB
    private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore
    private let remoteConfigManager: RemoteConfigManager
    private let tsAccountManager: TSAccountManager

    private let kvStore: KeyValueStore

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
        backupRequestManager: BackupRequestManager,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        db: any DB,
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
        self.backupRequestManager = backupRequestManager
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = KeyValueStore(collection: "ListBackupMediaManager")
        self.orphanedBackupAttachmentStore = orphanedBackupAttachmentStore
        self.remoteConfigManager = remoteConfigManager
        self.tsAccountManager = tsAccountManager

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(backupPlanDidChange),
            name: .backupPlanChanged,
            object: nil
        )
    }

    public func getLastFailingIntegrityCheckResult(tx: DBReadTransaction) throws -> ListMediaIntegrityCheckResult? {
        try kvStore.getCodableValue(forKey: Constants.lastNonEmptyIntegrityCheckResultKey, transaction: tx)
    }

    public func getMostRecentIntegrityCheckResult(tx: DBReadTransaction) throws -> ListMediaIntegrityCheckResult? {
        try kvStore.getCodableValue(forKey: Constants.lastIntegrityCheckResultKey, transaction: tx)
    }

    private let taskQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    /// Nil if we have not run list media this app launch (only held in memory).
    /// Set to the upload era where we ran list media this app launch.
    /// Should only be accessed from the taskQueue for locking purposes.
    private var lastListMediaUploadEraThisAppSession: String?

    public func queryListMediaIfNeeded() async throws {
        let task = Task {
            // Enqueue in a concurrent(1) task queue; we only want to run one of these at a time.
            try await taskQueue.run { [weak self] in
                try await self?._queryListMediaIfNeeded()
            }
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

    private func _queryListMediaIfNeeded() async throws -> ListMediaIntegrityCheckResult {
        guard FeatureFlags.Backups.supported else {
            return .empty(listMediaStartTimestamp: 0)
        }
        let (
            isPrimaryDevice,
            localAci,
            currentUploadEra,
            inProgressUploadEra,
            inProgressStartTimestamp,
            needsToQuery,
            hasEverRunListMedia,
            backupKey,
            inProgressIntegrityCheckResult,
        ) = try db.read { tx in
            let currentUploadEra = self.backupAttachmentUploadEraStore.currentUploadEra(tx: tx)
            let currentBackupPlan = backupSettingsStore.backupPlan(tx: tx)
            let integrityCheckResult: ListMediaIntegrityCheckResult? =
                try self.kvStore.getCodableValue(forKey: Constants.inProgressIntegrityCheckResultKey, transaction: tx)
            return (
                self.tsAccountManager.registrationState(tx: tx).isPrimaryDevice,
                self.tsAccountManager.localIdentifiers(tx: tx)?.aci,
                currentUploadEra,
                kvStore.getString(Constants.inProgressUploadEraKey, transaction: tx),
                kvStore.getUInt64(Constants.inProgressListMediaStartTimestampKey, transaction: tx),
                try self.needsToQueryListMedia(
                    currentUploadEra: currentUploadEra,
                    currentBackupPlan: currentBackupPlan,
                    tx: tx
                ),
                self.kvStore.getBool(Constants.hasEverRunListMediaKey, defaultValue: false, transaction: tx),
                self.accountKeyStore.getMediaRootBackupKey(tx: tx),
                integrityCheckResult
            )
        }
        guard needsToQuery else {
            return .empty(listMediaStartTimestamp: 0)
        }

        guard let localAci, let isPrimaryDevice else {
            throw OWSAssertionError("Not registered")
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

        let hasCompletedListingMedia: Bool = db.read { tx in
            return kvStore.getBool(
                Constants.hasCompletedListingMediaKey,
                defaultValue: false,
                transaction: tx
            )
        }

        if !hasCompletedListingMedia {
            let backupAuth: BackupServiceAuth?
            do {
                let fetchedBackupAuth: BackupServiceAuth = try await backupRequestManager.fetchBackupServiceAuth(
                    for: backupKey,
                    localAci: localAci,
                    auth: .implicit(),
                    // We want to affirmatively check for paid tier status
                    forceRefreshUnlessCachedPaidCredential: true
                )
                backupAuth = fetchedBackupAuth
            } catch let error as BackupAuthCredentialFetchError {
                switch error {
                case .noExistingBackupId:
                    // If we have no backup, there's no media tier to compare
                    // against, so we treat the list media result as empty.
                    backupAuth = nil
                }
            } catch let error {
                throw error
            }

            try Task.checkCancellation()

            // If we have no backupAuth here, we have no backup at all, so
            // proceed as if we got no results from list media.
            if let backupAuth {
                // Queries list media and writes the results to the database
                // so they're available for matching against local attachments below.
                try await self.makeListMediaRequest(backupAuth: backupAuth)
            }
        }

        let hasCompletedEnumeratingAttchments: Bool = db.read { tx in
            return kvStore.getBool(
                Constants.hasCompletedEnumeratingAttachmentsKey,
                defaultValue: false,
                transaction: tx
            )
        }

        var integrityCheckResult = inProgressIntegrityCheckResult ?? .empty(listMediaStartTimestamp: startTimestamp)

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
                    let fullsizeResult = try self.updateAttachmentIfNeeded(
                        attachment: attachment,
                        fullsizeMediaName: fullsizeMediaName,
                        isThumbnail: false,
                        backupKey: backupKey,
                        uploadEraAtStartOfListMedia: uploadEraAtStartOfListMedia,
                        currentBackupPlan: currentBackupPlan,
                        remoteConfig: remoteConfig,
                        isPrimaryDevice: isPrimaryDevice,
                        hasEverRunListMedia: hasEverRunListMedia,
                        tx: tx
                    )
                    integrityCheckResult.fullsize.updateWith(fullsizeResult)

                    // Refetch the attachment to reload any mutations applied
                    // by the fullsize matching.
                    guard let attachment = attachmentStore.fetch(id: attachment.id, tx: tx) else {
                        continue
                    }
                    let thumbnailResult = try self.updateAttachmentIfNeeded(
                        attachment: attachment,
                        fullsizeMediaName: fullsizeMediaName,
                        isThumbnail: true,
                        backupKey: backupKey,
                        uploadEraAtStartOfListMedia: uploadEraAtStartOfListMedia,
                        currentBackupPlan: currentBackupPlan,
                        remoteConfig: remoteConfig,
                        isPrimaryDevice: isPrimaryDevice,
                        hasEverRunListMedia: hasEverRunListMedia,
                        tx: tx
                    )
                    integrityCheckResult.thumbnail.updateWith(thumbnailResult)
                }
                let lastAttachmentId = attachments.last?.sqliteId
                if let lastAttachmentId {
                    kvStore.setInt64(lastAttachmentId, key: Constants.lastEnumeratedAttachmentIdKey, transaction: tx)
                } else {
                    // We're done
                    kvStore.removeValue(forKey: Constants.lastEnumeratedAttachmentIdKey, transaction: tx)
                    kvStore.setBool(true, key: Constants.hasCompletedEnumeratingAttachmentsKey, transaction: tx)
                }

                try kvStore.setCodable(integrityCheckResult, key: Constants.inProgressIntegrityCheckResultKey, transaction: tx)

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
                if isPrimaryDevice {
                    try self.enqueueListedMediaForDeletion(listedMediaObject, tx: tx)
                }
                try listedMediaObject.delete(tx.database)
            }
            integrityCheckResult.orphanedObjectCount += listedMediaObjects.count
            try kvStore.setCodable(integrityCheckResult, key: Constants.inProgressIntegrityCheckResultKey, transaction: tx)
            return listedMediaObjects.count
        }

        let needsToRunAgain = try await db.awaitableWrite { tx in
            try self.didFinishListMedia(startTimestamp: startTimestamp, integrityCheckResult: integrityCheckResult, tx: tx)
            let currentUploadEra = backupAttachmentUploadEraStore.currentUploadEra(tx: tx)
            let currentBackupPlan = backupSettingsStore.backupPlan(tx: tx)
            return try self.needsToQueryListMedia(
                currentUploadEra: currentUploadEra,
                currentBackupPlan: currentBackupPlan,
                tx: tx
            )
        }
        if needsToRunAgain {
            // Return the first integrity check result, not the second, because
            // usually earlier results are more interesting. Once we run list
            // media once, we've already synced local and remote state.
            _ = try await _queryListMediaIfNeeded()
        }
        return integrityCheckResult
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
        backupAuth: BackupServiceAuth
    ) async throws {
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

    fileprivate enum AttachmentMatchResult {
        /// Our local state and the remote state matched up; we expected
        /// an attachment to exist on media tier cdn and it did exist.
        /// We may optionally have updated our local knowledge of the cdn number.
        case uploaded(updatedCdnNumber: Bool)
        /// Our local state and the remote state matched up; we expected
        /// an attachment not to exist on media tier cdn and it did not exist.
        case notUploaded
        /// Locally we thought an attachment was on CDN but it was not listed;
        /// we have marked it as not uploaded.
        case missingFromCdn
        /// Locally we did not think an attachment was on CDN but it was there;
        /// we have marked it as uploaded.
        case discoveredOnCdn
    }

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
        isPrimaryDevice: Bool,
        hasEverRunListMedia: Bool,
        tx: DBWriteTransaction
    ) throws -> AttachmentMatchResult {
        // Either the fullsize or the thumbnail media name
        let mediaName: String
        // Either the fullsize of the thumbnail cdn number if we have it
        let localCdnNumber: UInt32?
        let attachmentWasAssumedUploaded: Bool
        if isThumbnail {
            mediaName = AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: fullsizeMediaName)
            localCdnNumber = attachment.thumbnailMediaTierInfo?.cdnNumber
            attachmentWasAssumedUploaded = attachment.thumbnailMediaTierInfo?.cdnNumber != nil
        } else {
            mediaName = fullsizeMediaName
            localCdnNumber = attachment.mediaTierInfo?.cdnNumber
            attachmentWasAssumedUploaded = attachment.mediaTierInfo?.cdnNumber != nil
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
            // No listed media matched our local attachment.
            // Mark media tier info (if any) as expired.
            try self.markMediaTierUploadExpiredIfNeeded(
                attachment,
                isThumbnail: isThumbnail,
                localCdnNumber: localCdnNumber,
                currentBackupPlan: currentBackupPlan,
                remoteConfig: remoteConfig,
                isPrimaryDevice: isPrimaryDevice,
                hasEverRunListMedia: hasEverRunListMedia,
                tx: tx
            )
            if attachmentWasAssumedUploaded {
                return .missingFromCdn
            } else {
                return .notUploaded
            }
        }

        if matchedListedMedia.cdnNumber == localCdnNumber {
            // Local and remote state match, nothing to update!
            // Clear out the matched listed media row so we don't
            // mark the upload for deletion later.
            try matchedListedMedia.delete(tx.database)
            return .uploaded(updatedCdnNumber: false)
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
            isPrimaryDevice: isPrimaryDevice,
            tx: tx
        )
        // Clear out the matched listed media row so we don't
        // mark the upload for deletion later.
        try matchedListedMedia.delete(tx.database)

        if !attachmentWasAssumedUploaded {
            return .discoveredOnCdn
        } else {
            return .uploaded(updatedCdnNumber: true)
        }
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
        localCdnNumber: UInt32?,
        currentBackupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        isPrimaryDevice: Bool,
        hasEverRunListMedia: Bool,
        tx: DBWriteTransaction
    ) throws {
        // Only remove media tier info (and cancel download) if there's
        // no chance it will be uploaded by another device in the near future.
        let mightBeUploadedByAnotherDeviceSoon: Bool
        if isPrimaryDevice {
            // Only primaries upload, and that's us.
            mightBeUploadedByAnotherDeviceSoon = false
        } else if localCdnNumber != nil {
            // If a cdn number was previously set, that means we
            // thought it was definitely uploaded, not waiting for
            // a future upload to happen.
            mightBeUploadedByAnotherDeviceSoon = false
        } else if currentBackupPlan == .disabled || currentBackupPlan == .free {
            // If we're not currently paid tier uploads won't be happening.
            mightBeUploadedByAnotherDeviceSoon = false
        } else {
            mightBeUploadedByAnotherDeviceSoon = true
        }

        if mightBeUploadedByAnotherDeviceSoon {
            // Don't stop the enqueued download if another device may upload
            // soon. Also don't clear media tier info (that would also stop
            // any downloads).

            if !hasEverRunListMedia {
                // If we've never run list media at any point in the past, schedule
                // uploads even for attachments whose state we don't otherwise touch.
                // This acts as a migration of sorts to ensure the upload queue becomes populated
                // with all attachments for users who had attachments before backups existed.
                try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                    attachment,
                    mode: isThumbnail ? .thumbnailOnly : .fullsizeOnly,
                    tx: tx
                )
            }
            return
        }
        if isThumbnail, attachment.thumbnailMediaTierInfo != nil {
            Logger.warn("Unexpectedly missing thumbnail we thought was on media tier cdn \(attachment.id)")
            try self.attachmentUploadStore.markThumbnailMediaTierUploadExpired(
                attachment: attachment,
                tx: tx
            )
        }
        if !isThumbnail, attachment.mediaTierInfo != nil {
            Logger.warn("Unexpectedly missing fullsize we thought was on media tier cdn \(attachment.id)")
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
                isPrimaryDevice: isPrimaryDevice,
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
        isPrimaryDevice: Bool,
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
                isPrimaryDevice: isPrimaryDevice
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
        isPrimaryDevice: Bool,
        tx: DBWriteTransaction
    ) throws {
        // Update the attachment itself.
        let didSetCdnInfo = try self.updateCdnInfoIfPossible(
            of: attachment,
            from: listedMedia,
            isThumbnail: isThumbnail,
            uploadEraAtStartOfListMedia: uploadEraAtStartOfListMedia,
            fullsizeMediaName: fullsizeMediaName,
            isPrimaryDevice: isPrimaryDevice,
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
                tx: tx
            )
        {
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
            isPrimaryDevice: isPrimaryDevice,
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
        isPrimaryDevice: Bool,
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
            Logger.error("Missing media tier metadata but matched by media id somehow")
            if isPrimaryDevice {
                try enqueueListedMediaForDeletion(listedMedia, tx: tx)
            }
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
        isPrimaryDevice: Bool,
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
                isPrimaryDevice: isPrimaryDevice
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

    private func needsToQueryListMedia(
        currentUploadEra: String,
        currentBackupPlan: BackupPlan,
        tx: DBReadTransaction
    ) throws -> Bool {
        switch currentBackupPlan {
        case .disabled:
            return false
        case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        if kvStore.getString(Constants.inProgressUploadEraKey, transaction: tx) != nil {
            return true
        }

        let lastQueriedUploadEra = kvStore.getString(Constants.lastListMediaUploadEraKey, transaction: tx)
        guard let lastQueriedUploadEra else {
            // If we've never queried, we absolutely should.
            return true
        }
        guard tsAccountManager.registrationState(tx: tx).isPrimaryDevice == true else {
            // We only query once ever on linked devices, not again when
            // state changes.
            return false
        }
        if currentUploadEra != lastQueriedUploadEra {
            return true
        }
        switch currentBackupPlan {
        case .disabled, .disabling:
            return false
        case .free:
            return false
        case .paid, .paidExpiringSoon, .paidAsTester:
            // Only query once per app session per upload era; this overrides the manual
            // toggle and the date-based checks.
            if lastListMediaUploadEraThisAppSession == currentUploadEra {
                return false
            }

            if kvStore.getBool(Constants.manuallySetNeedsListMediaKey, defaultValue: false, transaction: tx) {
                return true
            }

            // If paid tier, query periodically as a catch-all to ensure local state
            // stays in sync with the server.
            let nowMs = dateProvider().ows_millisecondsSince1970
            let lastListMediaMs = kvStore.getUInt64(Constants.lastListMediaStartTimestampKey, defaultValue: 0, transaction: tx)
            if nowMs > lastListMediaMs, nowMs - lastListMediaMs > Constants.refreshIntervalMs {
                return true
            }
            return false
        }
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
        integrityCheckResult: ListMediaIntegrityCheckResult,
        tx: DBWriteTransaction
    ) throws {
        self.kvStore.setBool(true, key: Constants.hasEverRunListMediaKey, transaction: tx)
        if let uploadEra = kvStore.getString(Constants.inProgressUploadEraKey, transaction: tx) {
            self.kvStore.setString(uploadEra, key: Constants.lastListMediaUploadEraKey, transaction: tx)
            self.lastListMediaUploadEraThisAppSession = uploadEra
            self.kvStore.removeValue(forKey: Constants.inProgressUploadEraKey, transaction: tx)
        } else {
            owsFailDebug("Missing in progress upload era?")
        }
        self.kvStore.setUInt64(startTimestamp, key: Constants.lastListMediaStartTimestampKey, transaction: tx)
        self.kvStore.setBool(false, key: Constants.manuallySetNeedsListMediaKey, transaction: tx)
        kvStore.removeValue(forKey: Constants.inProgressListMediaStartTimestampKey, transaction: tx)

        if integrityCheckResult.hasFailures {
            try kvStore.setCodable(integrityCheckResult, key: Constants.lastNonEmptyIntegrityCheckResultKey, transaction: tx)
        }
        try kvStore.setCodable(integrityCheckResult, key: Constants.lastIntegrityCheckResultKey, transaction: tx)
        kvStore.removeValue(forKey: Constants.inProgressIntegrityCheckResultKey, transaction: tx)

        self.kvStore.setBool(false, key: Constants.hasCompletedListingMediaKey, transaction: tx)
        kvStore.removeValue(forKey: Constants.paginationCursorKey, transaction: tx)
        self.kvStore.setBool(false, key: Constants.hasCompletedEnumeratingAttachmentsKey, transaction: tx)
        self.kvStore.removeValue(forKey: Constants.lastEnumeratedAttachmentIdKey, transaction: tx)
    }

    @objc
    private func backupPlanDidChange() {
        switch db.read(block: backupSettingsStore.backupPlan(tx:)) {
        case .free, .paid, .paidAsTester, .paidExpiringSoon, .disabling:
            return
        case .disabled:
            // Rotate the last integrity check failure when disabled
            db.write { tx in
                kvStore.removeValue(forKey: Constants.lastNonEmptyIntegrityCheckResultKey, transaction: tx)
                kvStore.removeValue(forKey: Constants.lastIntegrityCheckResultKey, transaction: tx)
            }
        }
    }

    public func setManualNeedsListMedia(tx: DBWriteTransaction) {
        kvStore.setBool(true, key: Constants.manuallySetNeedsListMediaKey, transaction: tx)
    }

    private enum Constants {
        /// Maps to the upload era (active subscription) when we last queried the list media
        /// endpoint, or nil if its never been queried.
        static let lastListMediaUploadEraKey = "lastListMediaUploadEra"

        /// Maps to the timestamp we last completed a list media request.
        static let lastListMediaStartTimestampKey = "lastListMediaTimestamp"
        static let inProgressListMediaStartTimestampKey = "inProgressListMediaTimestamp"

        static let manuallySetNeedsListMediaKey = "manuallySetNeedsListMediaKey"

        /// True if we've ever run list media in the lifetime of this app.
        static let hasEverRunListMediaKey = "hasEverRunListMedia"

        /// If we haven't listed in this long, we will list again.
        static let refreshIntervalMs: UInt64 = .dayInMs * 30

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

        static let lastNonEmptyIntegrityCheckResultKey = "lastNonEmptyIntegrityCheckResultKey"
        static let lastIntegrityCheckResultKey = "lastIntegrityCheckResultKey"
        static let inProgressIntegrityCheckResultKey = "inProgressIntegrityCheckResultKey"
    }
}

// MARK: -

#if TESTABLE_BUILD

final class MockBackupListMediaManager: BackupListMediaManager {
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
