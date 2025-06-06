//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public protocol BackupListMediaManager {
    func queryListMediaIfNeeded() async throws

    func setNeedsQueryListMedia(tx: DBWriteTransaction)
}

public class BackupListMediaManagerImpl: BackupListMediaManager {

    private let attachmentStore: AttachmentStore
    private let attachmentUploadStore: AttachmentUploadStore
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let backupAttachmentUploadStore: BackupAttachmentUploadStore
    private let backupKeyMaterial: BackupKeyMaterial
    private let backupRequestManager: BackupRequestManager
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let dateProvider: DateProvider
    private let db: any DB
    private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore
    private let remoteConfigManager: RemoteConfigManager
    private let tsAccountManager: TSAccountManager

    private let kvStore: KeyValueStore

    public init(
        attachmentStore: AttachmentStore,
        attachmentUploadStore: AttachmentUploadStore,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
        backupAttachmentUploadStore: BackupAttachmentUploadStore,
        backupKeyMaterial: BackupKeyMaterial,
        backupRequestManager: BackupRequestManager,
        backupSubscriptionManager: BackupSubscriptionManager,
        dateProvider: @escaping DateProvider,
        db: any DB,
        orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
        remoteConfigManager: RemoteConfigManager,
        tsAccountManager: TSAccountManager
    ) {
        self.attachmentStore = attachmentStore
        self.attachmentUploadStore = attachmentUploadStore
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.backupAttachmentUploadStore = backupAttachmentUploadStore
        self.backupKeyMaterial = backupKeyMaterial
        self.backupRequestManager = backupRequestManager
        self.backupSubscriptionManager = backupSubscriptionManager
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = KeyValueStore(collection: "ListBackupMediaManager")
        self.orphanedBackupAttachmentStore = orphanedBackupAttachmentStore
        self.remoteConfigManager = remoteConfigManager
        self.tsAccountManager = tsAccountManager
    }

    private let taskQueue = SerialTaskQueue()

    public func queryListMediaIfNeeded() async throws {
        // Enqueue in a serial task queue; we only want to run one of these at a time.
        try await taskQueue.enqueue(operation: { [weak self] in
            try await self?._queryListMediaIfNeeded()
        }).value
    }

    private func _queryListMediaIfNeeded() async throws {
        guard FeatureFlags.Backups.fileAlpha else {
            return
        }
        let (
            isPrimaryDevice,
            localAci,
            currentUploadEra,
            needsToQuery,
            backupKey
        ) = try db.read { tx in
            let currentUploadEra = self.backupSubscriptionManager.getUploadEra(tx: tx)
            return (
                self.tsAccountManager.registrationState(tx: tx).isPrimaryDevice,
                self.tsAccountManager.localIdentifiers(tx: tx)?.aci,
                currentUploadEra,
                try self.needsToQueryListMedia(currentUploadEra: currentUploadEra, tx: tx),
                try backupKeyMaterial.backupKey(type: .media, tx: tx)
            )
        }
        guard needsToQuery else {
            return
        }

        guard let localAci, let isPrimaryDevice else {
            throw OWSAssertionError("Not registered")
        }

        let backupAuth: BackupServiceAuth?
        do {
            let fetchedBackupAuth: BackupServiceAuth = try await backupRequestManager.fetchBackupServiceAuth(
                for: .media,
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

        // We go popping entries off this map as we process them.
        // By the end, anything left in here was not in the list response.
        var mediaIdMap = try db.read { tx in try self.buildMediaIdMap(backupKey: backupKey, tx: tx) }

        // If we have no backupAuth here, we have no backup at all, so
        // proceed as if we got no results from list media.
        if let backupAuth {
            var cursor: String?
            while true {
                let result = try await backupRequestManager.listMediaObjects(
                    cursor: cursor,
                    limit: nil, /* let the server determine the page size */
                    auth: backupAuth
                )

                try await result.storedMediaObjects.forEachChunk(chunkSize: 100) { chunk in
                    try await db.awaitableWrite { tx in
                        for storedMediaObject in chunk {
                            try self.handleListedMedia(
                                storedMediaObject,
                                mediaIdMap: &mediaIdMap,
                                uploadEra: currentUploadEra,
                                isPrimaryDevice: isPrimaryDevice,
                                tx: tx
                            )
                        }
                    }
                }

                cursor = result.cursor
                if cursor == nil {
                    break
                }
            }
        }

        let hasEverRunListMedia = db.read { tx in
            kvStore.getBool(Constants.hasEverRunListMediaKey, defaultValue: false, transaction: tx)
        }

        // Any remaining attachments in the dictionary weren't listed by the server;
        // Potentially mark it as non-uploaded.
        let remainingLocalAttachments: [LocalAttachment]

        if !hasEverRunListMedia {
            // If we've never run list media at any point in the past, walk over _every_
            // other attachment so that we can enqueue it for media tier upload.
            // This acts as a migration of sorts to ensure the upload queue becomes populated
            // with all attachments for users who had attachments before backups existed.
            remainingLocalAttachments = Array(mediaIdMap.values)
        } else {
            // Otherwise we only need to walk over those attachments we may want to modify.
            remainingLocalAttachments = mediaIdMap.values.filter { localAttachment in
                guard localAttachment.hadMediaTierInfo else {
                    // All we're doing here is marking media tier info expired/invalid.
                    // We don't need to do this for attachments that didn't have media
                    // tier info to begin with.
                    return false
                }
                if localAttachment.cdnNumber != nil {
                    // Any where we had a cdn number means the exporting primary client _thought_
                    // the attachment was uploaded, and won't be attempting reupload.
                    // So we can go ahead and mark these non-uploaded.
                    return true
                } else if isPrimaryDevice {
                    // If we are the primary, by definition the old primary is unregistered
                    // and cannot be uploading stuff. If its not uploaded by now, it won't be.
                    return true
                } else if (backupAuth?.backupLevel ?? .free) == .free {
                    // Even if we're a secondary device, if we're free tier according to
                    // the current latest auth credential, then the primary can't be
                    // uploading stuff, so if its not listed its not gonna be in the future.
                    return true
                } else {
                    return false
                }
            }
        }
        if remainingLocalAttachments.isEmpty.negated {
            try await remainingLocalAttachments.forEachChunk(chunkSize: 100) { chunk in
                try await db.awaitableWrite { tx in
                    try chunk.forEach { localAttachment in
                        try self.markMediaTierUploadExpired(localAttachment, currentUploadEra: currentUploadEra, tx: tx)
                    }
                    if chunk.endIndex == remainingLocalAttachments.endIndex {
                        self.didQueryListMedia(uploadEraAtStartOfRequest: currentUploadEra, tx: tx)
                    }
                }
            }
        } else {
            await db.awaitableWrite { tx in
                self.didQueryListMedia(uploadEraAtStartOfRequest: currentUploadEra, tx: tx)
            }
        }
    }

    private func handleListedMedia(
        _ listedMedia: BackupArchive.Response.StoredMedia,
        mediaIdMap: inout [Data: LocalAttachment],
        uploadEra: String,
        isPrimaryDevice: Bool,
        tx: DBWriteTransaction
    ) throws {
        let mediaId = try Data.data(fromBase64Url: listedMedia.mediaId)
        guard let localAttachment = mediaIdMap.removeValue(forKey: mediaId) else {
            if isPrimaryDevice {
                // If we don't have the media locally, schedule it for deletion.
                // (Linked devices don't do uploads and so shouldn't delete uploads
                // either; the primary may have uploaded an attachment from a message
                // we haven't received yet).
                try enqueueListedMediaForDeletion(listedMedia, mediaId: mediaId, tx: tx)
            }
            return
        }

        guard let localCdnNumber = localAttachment.cdnNumber else {
            // Set the listed cdn number on the attachment.
            try updateWithListedCdn(
                localAttachment: localAttachment,
                listedMedia: listedMedia,
                mediaId: mediaId,
                uploadEra: uploadEra,
                tx: tx
            )
            return
        }

        if localCdnNumber > listedMedia.cdn {
            // We have a duplicate or outdated entry on an old cdn.
            Logger.info("Duplicate or outdated media tier cdn item found. Old cdn: \(listedMedia.cdn) new: \(localCdnNumber)")
            try enqueueListedMediaForDeletion(listedMedia, mediaId: mediaId, tx: tx)
            // Re-add the local metadata to the map; we may later find an entry
            // at the latest cdn.
            mediaIdMap[mediaId] = localAttachment
            return
        } else if localCdnNumber < listedMedia.cdn {
            // The cdn has a newer upload! Set our local cdn and schedule the old
            // one for deletion.
            try updateWithListedCdn(
                localAttachment: localAttachment,
                listedMedia: listedMedia,
                mediaId: mediaId,
                uploadEra: uploadEra,
                tx: tx
            )
            return
        } else {
            // The cdn number locally and on the server matches;
            // both states agree and nothing needs changing.
            return
        }
    }

    // MARK: Helpers

    private func enqueueListedMediaForDeletion(
        _ listedMedia: BackupArchive.Response.StoredMedia,
        mediaId: Data,
        tx: DBWriteTransaction
    ) throws {
        var orphanRecord = OrphanedBackupAttachment.discoveredOnServer(
            cdnNumber: listedMedia.cdn,
            mediaId: mediaId
        )
        try orphanedBackupAttachmentStore.insert(&orphanRecord, tx: tx)
    }

    private func updateWithListedCdn(
        localAttachment: LocalAttachment,
        listedMedia: BackupArchive.Response.StoredMedia,
        mediaId: Data,
        uploadEra: String,
        tx: DBWriteTransaction
    ) throws {
        guard let attachment = attachmentStore.fetch(id: localAttachment.id, tx: tx) else {
            return
        }
        if localAttachment.isThumbnail {
            try attachmentUploadStore.markThumbnailUploadedToMediaTier(
                attachment: attachment,
                thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo(
                    cdnNumber: listedMedia.cdn,
                    uploadEra: uploadEra,
                    lastDownloadAttemptTimestamp: nil
                ),
                tx: tx
            )
        } else {
            // In order for the attachment to be downloadable, we need some metadata.
            // We might have this either from a local stream (if we matched against
            // the media name/id we generated locally) or from a restored backup (if
            // we matched against the media name/id we pulled off the backup proto).
            if
                let unencryptedByteCount = attachment.mediaTierInfo?.unencryptedByteCount
                    ?? attachment.streamInfo?.unencryptedByteCount,
                let digestSHA256Ciphertext = attachment.mediaTierInfo?.digestSHA256Ciphertext
                    ?? attachment.streamInfo?.digestSHA256Ciphertext
            {
                try attachmentUploadStore.markUploadedToMediaTier(
                    attachment: attachment,
                    mediaTierInfo: Attachment.MediaTierInfo(
                        cdnNumber: listedMedia.cdn,
                        unencryptedByteCount: unencryptedByteCount,
                        digestSHA256Ciphertext: digestSHA256Ciphertext,
                        incrementalMacInfo: attachment.mediaTierInfo?.incrementalMacInfo,
                        uploadEra: uploadEra,
                        lastDownloadAttemptTimestamp: nil
                    ),
                    tx: tx
                )
            } else {
                // We have a matching local attachment but we don't have
                // sufficient metadata from either a backup or local stream
                // to be able to download, anyway. Schedule the upload for
                // deletion, its unuseable. This should never happen, because
                // how would we have a media id to match against but lack the
                // other info?
                owsFailDebug("Missing media tier metadata but have media name somehow")
                try enqueueListedMediaForDeletion(listedMedia, mediaId: mediaId, tx: tx)
            }
        }

        // Since we now know this is uploaded, we can go ahead and remove
        // from the upload queue.
        if
            let removedRecord = try backupAttachmentUploadStore.removeQueuedUpload(
                for: attachment.id,
                fullsize: localAttachment.isThumbnail.negated,
                tx: tx
            )
        {
            Task {
                await backupAttachmentUploadProgress.didFinishUploadOfAttachment(uploadRecord: removedRecord)
            }
        }

        // If the existing record had a cdn number, and that cdn number
        // is smaller than the remote cdn number, its a duplicate on an
        // old cdn and should be marked for deletion.
        if
            let oldCdn = localAttachment.cdnNumber,
            oldCdn < listedMedia.cdn
        {
            var orphanRecord = OrphanedBackupAttachment.discoveredOnServer(
                cdnNumber: UInt32(oldCdn),
                mediaId: mediaId
            )
            try orphanedBackupAttachmentStore.insert(&orphanRecord, tx: tx)
        }
    }

    private func markMediaTierUploadExpired(
        _ localAttachment: LocalAttachment,
        currentUploadEra: String,
        tx: DBWriteTransaction
    ) throws {
        guard
            let attachment = self.attachmentStore.fetch(
                id: localAttachment.id,
                tx: tx
            )
        else {
            return
        }

        if localAttachment.hadMediaTierInfo {
            if localAttachment.isThumbnail {
                try self.attachmentUploadStore.markThumbnailMediaTierUploadExpired(
                    attachment: attachment,
                    tx: tx
                )
            } else {
                try self.attachmentUploadStore.markMediaTierUploadExpired(
                    attachment: attachment,
                    tx: tx
                )
            }
        }

        func getHighestPriorityReference() throws -> AttachmentReference? {
            var referenceToUse: AttachmentReference?
            try attachmentStore.enumerateAllReferences(
                toAttachmentId: attachment.id,
                tx: tx
            ) { reference, _ in
                guard let ownerType = reference.owner.asUploadOwnerType() else {
                    return
                }
                if referenceToUse?.owner.asUploadOwnerType()?.isHigherPriority(than: ownerType) != true {
                    referenceToUse = reference
                }
            }
            return referenceToUse
        }

        if let stream = attachment.asStream() {
            let eligibility = BackupAttachmentUploadEligibility(stream, currentUploadEra: currentUploadEra)
            if
                (localAttachment.isThumbnail && eligibility.needsUploadThumbnail)
                    || (!localAttachment.isThumbnail && eligibility.needsUploadFullsize),
                let reference = try getHighestPriorityReference()
            {
                try backupAttachmentUploadStore.enqueue(
                    ReferencedAttachmentStream(reference: reference, attachmentStream: stream),
                    fullsize: localAttachment.isThumbnail.negated,
                    tx: tx
                )
            }
        }

        if !localAttachment.isEligibleForTransitTierDownload {
            // If not eligible for transit tier download, go ahead and dequeue
            // the download record. (If we are eligible for transit tier download,
            // we may still want to download).
            try backupAttachmentDownloadStore.removeQueuedDownload(attachmentId: localAttachment.id, tx: tx)
        }
    }

    // MARK: Local attachment mapping

    private struct LocalAttachment {
        let id: Attachment.IDType
        let isThumbnail: Bool
        let isEligibleForTransitTierDownload: Bool
        // These are UInt32 in our protocol, but they're actually very small
        // so we fit them in UInt8 here to save space.
        let cdnNumber: UInt8?
        let hadMediaTierInfo: Bool

        init(
            attachment: Attachment,
            isThumbnail: Bool,
            isEligibleForTransitTierDownload: Bool,
            cdnNumber: UInt32?,
            hadMediaTierInfo: Bool
        ) {
            self.id = attachment.id
            self.isThumbnail = isThumbnail
            self.isEligibleForTransitTierDownload = isEligibleForTransitTierDownload
            self.hadMediaTierInfo = hadMediaTierInfo
            if let cdnNumber {
                if let uint8 = UInt8(exactly: cdnNumber) {
                    self.cdnNumber = uint8
                } else {
                    owsFailDebug("Canary: CDN number too large!")
                    self.cdnNumber = .max
                }
            } else {
                self.cdnNumber = nil
            }
        }
    }

    /// Build a map from mediaId to attachment id for every attachment in the databse.
    ///
    /// The server lists media by mediaId, which we do not store because it is derived from the
    /// mediaName via the backup key (which can change). Therefore, to match against local
    /// attachments first we need to create a mediaId mapping, deriving using the current backup key.
    ///
    /// Each attachment gets an entry for its fullsize media id, and, if it is eligible for thumbnail-ing,
    /// a second entry for the media id for its thumbnail.
    ///
    /// Today, this loads the map into memory. If the memory load of this dictionary ever becomes
    /// a problem, we can write it to an ephemeral sqlite table with a UNIQUE mediaId column.
    private func buildMediaIdMap(
        backupKey: BackupKey,
        tx: DBReadTransaction
    ) throws -> [Data: LocalAttachment] {

        let currentTimestamp = dateProvider().ows_millisecondsSince1970
        let remoteConfig = remoteConfigManager.currentConfig()

        var map = [Data: LocalAttachment]()
        try self.attachmentStore.enumerateAllAttachmentsWithMediaName(tx: tx) { attachment in
            guard let mediaName = attachment.mediaName else {
                owsFailDebug("Query returned attachment without media name!")
                return
            }
            let fullsizeMediaId = Data(try backupKey.deriveMediaId(mediaName))

            let isEligibleForTransitTierDownload = BackupAttachmentDownloadEligibility.canDownloadTransitTierFullsize(
                attachment: attachment,
                // Use transit tier upload timestamp for this metric; it doesn't have to be precise.
                attachmentTimestamp: attachment.transitTierInfo?.uploadTimestamp,
                currentTimestamp: currentTimestamp,
                remoteConfig: remoteConfig
            )

            map[fullsizeMediaId] = LocalAttachment(
                attachment: attachment,
                isThumbnail: false,
                isEligibleForTransitTierDownload: isEligibleForTransitTierDownload,
                cdnNumber: attachment.mediaTierInfo?.cdnNumber,
                hadMediaTierInfo: attachment.mediaTierInfo != nil
            )
            if
                AttachmentBackupThumbnail.canBeThumbnailed(attachment)
                || attachment.thumbnailMediaTierInfo != nil
            {
                // Also prep a thumbnail media name.
                let thumbnailMediaId = Data(try backupKey.deriveMediaId(
                    AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName)
                ))
                map[thumbnailMediaId] = LocalAttachment(
                    attachment: attachment,
                    isThumbnail: true,
                    // We don't do thumbnails from transit tier.
                    isEligibleForTransitTierDownload: false,
                    cdnNumber: attachment.thumbnailMediaTierInfo?.cdnNumber,
                    hadMediaTierInfo: attachment.thumbnailMediaTierInfo != nil
                )
            }
        }
        return map
    }

    // MARK: State

    private func needsToQueryListMedia(currentUploadEra: String, tx: DBReadTransaction) throws -> Bool {
        let lastQueriedUploadEra = kvStore.getString(Constants.lastListMediaUploadEraKey, transaction: tx)
        guard let lastQueriedUploadEra else {
            // If we've never queried, we absolutely should.
            return true
        }
        guard tsAccountManager.registrationState(tx: tx).isPrimaryDevice == true else {
            // We only query once ever on linked devices, not again when
            // state changes.
            return true
        }
        if currentUploadEra != lastQueriedUploadEra {
            return true
        }
        let nowMs = dateProvider().ows_millisecondsSince1970
        let lastListMediaMs = kvStore.getUInt64(Constants.lastListMediaTimestampKey, defaultValue: 0, transaction: tx)
        if nowMs > lastListMediaMs, nowMs - lastListMediaMs > Constants.refreshIntervalMs {
            return true
        }
        return false
    }

    private func didQueryListMedia(uploadEraAtStartOfRequest uploadEra: String, tx: DBWriteTransaction) {
        self.kvStore.setBool(true, key: Constants.hasEverRunListMediaKey, transaction: tx)
        self.kvStore.setString(uploadEra, key: Constants.lastListMediaUploadEraKey, transaction: tx)
        self.kvStore.setUInt64(dateProvider().ows_millisecondsSince1970, key: Constants.lastListMediaTimestampKey, transaction: tx)
    }

    public func setNeedsQueryListMedia(tx: DBWriteTransaction) {
        self.kvStore.removeValue(forKey: Constants.lastListMediaUploadEraKey, transaction: tx)
    }

    private enum Constants {
        /// Maps to the upload era (active subscription) when we last queried the list media
        /// endpoint, or nil if its never been queried.
        static let lastListMediaUploadEraKey = "lastListMediaUploadEra"

        /// Maps to the timestamp we last completed a list media request.
        static let lastListMediaTimestampKey = "lastListMediaTimestamp"

        /// True if we've ever run list media in the lifetime of this app.
        static let hasEverRunListMediaKey = "hasEverRunListMedia"

        /// If we haven't listed in this long, we will list again.
        static let refreshIntervalMs: UInt64 = .dayInMs * 30
    }
}
