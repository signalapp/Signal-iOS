//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import Testing

@testable import SignalServiceKit

public class BackupListMediaManagerTests {

    let attachmentStore = AttachmentStoreImpl()
    let backupAttachmentDownloadStore = BackupAttachmentDownloadStoreImpl()
    let backupAttachmentUploadScheduler = BackupAttachmentUploadSchedulerMock()
    let backupAttachmentUploadStore = BackupAttachmentUploadStoreImpl()
    let backupKeyMaterial = BackupKeyMaterialMock()
    fileprivate let backupRequestManager = BackupRequestManagerMock()
    let backupSettingsStore = BackupSettingsStore()
    let db = InMemoryDB()
    let orphanedBackupAttachmentStore = OrphanedBackupAttachmentStoreImpl()
    let remoteConfigManager = StubbableRemoteConfigManager()
    let tsAccountManager = MockTSAccountManager()

    let listMediaManager: BackupListMediaManager

    init() {
        let dateProvider: DateProvider = {
            Date()
        }
        self.listMediaManager = BackupListMediaManagerImpl(
            attachmentStore: attachmentStore,
            attachmentUploadStore: AttachmentUploadStoreImpl(
                attachmentStore: attachmentStore
            ),
            backupAttachmentDownloadProgress: BackupAttachmentDownloadProgressMock(),
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupAttachmentUploadProgress: BackupAttachmentUploadProgressMock(),
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            backupAttachmentUploadStore: backupAttachmentUploadStore,
            backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore(),
            backupKeyMaterial: backupKeyMaterial,
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
            remoteConfigManager: remoteConfigManager,
            tsAccountManager: tsAccountManager
        )
    }

    @Test
    func testListMedia() async throws {
        let localUploadEra = "1"

        let remoteConfigCdnNumber: UInt32 = 100
        remoteConfigManager.cachedConfig = RemoteConfig(
            clockSkew: 0,
            valueFlags: ["global.backups.mediaTierFallbackCdnNumber": "\(remoteConfigCdnNumber)"],
        )

        backupKeyMaterial.mediaBackupKey = try BackupKey(
            contents: Data(repeating: 8, count: 32)
        )

        await db.awaitableWrite { tx in
            backupSettingsStore.setBackupPlan(.paid(optimizeLocalStorage: false), tx: tx)
        }

        // Make a few attachments so we hit a couple pages of results
        // from the request and from local db reads.
        let numAttachmentsPerCase = 50

        // There are N cases we care about:

        // Case 1: Attachment exists locally but not on CDN
        let localOnlyIds = await db.awaitableWrite { tx in
            return (0..<numAttachmentsPerCase).map { _ in
                return insertAttachment(
                    mediaName: UUID().uuidString,
                    mediaTierInfo: .init(
                        cdnNumber: 1,
                        unencryptedByteCount: 100,
                        sha256ContentHash: UUID().data,
                        incrementalMacInfo: nil,
                        uploadEra: localUploadEra,
                        lastDownloadAttemptTimestamp: nil
                    ),
                    scheduleDownload: true,
                    tx: tx
                )
            }
        }

        // Case 2: Attachment exists on cdn but not locally
        let orphanCdnNumber: UInt32 = 99
        let remoteOnlyCdnNumberMedia = (0..<numAttachmentsPerCase).map { _ in
            return BackupArchive.Response.StoredMedia(
                cdn: orphanCdnNumber,
                mediaId: UUID().uuidString,
                objectLength: 100
            )
        }
        // For other cases, we'll add duplicate entries on cdn at different
        // cdn numbers that should be orphaned like case 2
        var orphanCdnNumberMedia = [BackupArchive.Response.StoredMedia]()

        // Case 3: exists on both, local didn't have cdn info
        let discoveredCdnNumber: UInt32 = 5
        var discoveredCdnNumberMedia = [BackupArchive.Response.StoredMedia]()
        let discoveredCdnNumberIds = try await db.awaitableWrite { tx in
            return try (0..<numAttachmentsPerCase).map { _ in
                let mediaName = UUID().uuidString
                let mediaId = try backupKeyMaterial.mediaBackupKey.deriveMediaId(mediaName)
                discoveredCdnNumberMedia.append(.init(
                    cdn: discoveredCdnNumber,
                    mediaId: mediaId.asBase64Url,
                    objectLength: 100
                ))
                return insertAttachment(
                    mediaName: mediaName,
                    mediaTierInfo: nil,
                    scheduleUpload: true,
                    tx: tx
                )
            }
        }

        // Case 4: exists on both, cdn number matches.
        let matchingCdnNumber: UInt32 = 3
        var matchingCdnNumberMedia = [BackupArchive.Response.StoredMedia]()
        let matchingCdnNumberIds = try await db.awaitableWrite { tx in
            return try (0..<numAttachmentsPerCase).map { _ in
                let mediaName = UUID().uuidString
                let mediaId = try backupKeyMaterial.mediaBackupKey.deriveMediaId(mediaName)
                matchingCdnNumberMedia.append(.init(
                    cdn: matchingCdnNumber,
                    mediaId: mediaId.asBase64Url,
                    objectLength: 100
                ))
                orphanCdnNumberMedia.append(.init(
                    cdn: orphanCdnNumber,
                    mediaId: mediaId.asBase64Url,
                    objectLength: 100
                ))
                return insertAttachment(
                    mediaName: mediaName,
                    mediaTierInfo: .init(
                        cdnNumber: matchingCdnNumber,
                        unencryptedByteCount: 100,
                        sha256ContentHash: UUID().data,
                        incrementalMacInfo: nil,
                        uploadEra: localUploadEra,
                        lastDownloadAttemptTimestamp: nil
                    ),
                    tx: tx
                )
            }
        }

        // Case 5: exists on both, cdn number doesn't match.
        var nonMatchingCdnNumberMedia = [BackupArchive.Response.StoredMedia]()
        let nonMatchingCdnNumberIds = try await db.awaitableWrite { tx in
            return try (0..<numAttachmentsPerCase).map { _ in
                let mediaName = UUID().uuidString
                let mediaId = try backupKeyMaterial.mediaBackupKey.deriveMediaId(mediaName)
                nonMatchingCdnNumberMedia.append(.init(
                    // Prefer a cdn number matching remote config,
                    // instead of the other orphaned one below
                    cdn: remoteConfigCdnNumber,
                    mediaId: mediaId.asBase64Url,
                    objectLength: 100
                ))
                orphanCdnNumberMedia.append(.init(
                    cdn: remoteConfigCdnNumber,
                    mediaId: mediaId.asBase64Url,
                    objectLength: 100
                ))
                return insertAttachment(
                    mediaName: mediaName,
                    mediaTierInfo: .init(
                        cdnNumber: matchingCdnNumber,
                        unencryptedByteCount: 100,
                        sha256ContentHash: UUID().data,
                        incrementalMacInfo: nil,
                        uploadEra: localUploadEra,
                        lastDownloadAttemptTimestamp: nil
                    ),
                    tx: tx
                )
            }
        }

        // Set up mock list response
        backupRequestManager.listMediaResults = [
            BackupArchive.Response.ListMediaResult(
                storedMediaObjects: remoteOnlyCdnNumberMedia,
                backupDir: "",
                mediaDir: "",
                cursor: "someCursor"
            ),
            BackupArchive.Response.ListMediaResult(
                storedMediaObjects: discoveredCdnNumberMedia,
                backupDir: "",
                mediaDir: "",
                cursor: "someCursor"
            ),
            BackupArchive.Response.ListMediaResult(
                storedMediaObjects: matchingCdnNumberMedia,
                backupDir: "",
                mediaDir: "",
                cursor: "someCursor"
            ),
            BackupArchive.Response.ListMediaResult(
                storedMediaObjects: nonMatchingCdnNumberMedia,
                backupDir: "",
                mediaDir: "",
                cursor: "someCursor"
            ),
            BackupArchive.Response.ListMediaResult(
                storedMediaObjects: orphanCdnNumberMedia,
                backupDir: "",
                mediaDir: "",
                cursor: nil
            )
        ]

        try await listMediaManager.queryListMediaIfNeeded()

        // Case 1 should've been marked as not uploaded to media tier,
        // removed from download queue and added to upload queue.
        db.read { tx in
            for attachmentId in localOnlyIds {
                let attachment = attachmentStore.fetch(id: attachmentId, tx: tx)!
                #expect(attachment.mediaTierInfo == nil)

                #expect(try! backupAttachmentDownloadStore.getEnqueuedDownload(
                    attachmentRowId: attachmentId,
                    thumbnail: false,
                    tx: tx
                ) == nil)

                #expect(self.backupAttachmentUploadScheduler.enqueuedAttachmentIds.contains(attachmentId))
            }
        }

        // Case 2, and other duplicates, should've been marked for deletion.
        db.read { tx in
            for orphanMedia in remoteOnlyCdnNumberMedia + orphanCdnNumberMedia {
                let mediaId = try! Data.data(fromBase64Url: orphanMedia.mediaId)
                #expect(try! OrphanedBackupAttachment
                    .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaId) == mediaId)
                    .filter(Column(OrphanedBackupAttachment.CodingKeys.cdnNumber) == orphanMedia.cdn)
                    .fetchCount(tx.database)
                    == 1
                )
            }
        }

        // Case 3 should be updated with cdn info, with uploads dequeued.
        db.read { tx in
            for attachmentId in discoveredCdnNumberIds {
                let attachment = attachmentStore.fetch(id: attachmentId, tx: tx)!
                #expect(attachment.mediaTierInfo?.cdnNumber == discoveredCdnNumber)

                #expect(try! QueuedBackupAttachmentUpload
                    .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.attachmentRowId) == attachmentId)
                    .fetchCount(tx.database)
                    == 0
                )
            }
        }

        // Case 4 should be untouched
        db.read { tx in
            for attachmentId in matchingCdnNumberIds {
                let attachment = attachmentStore.fetch(id: attachmentId, tx: tx)!
                #expect(attachment.mediaTierInfo?.cdnNumber == matchingCdnNumber)
            }
        }

        // Case 5 should be updated with the remote cdn number
        db.read { tx in
            for attachmentId in nonMatchingCdnNumberIds {
                let attachment = attachmentStore.fetch(id: attachmentId, tx: tx)!
                #expect(attachment.mediaTierInfo?.cdnNumber == remoteConfigCdnNumber)
            }
        }
    }

    // MARK: - Helpers

    typealias Attachment = SignalServiceKit.Attachment

    private func insertAttachment(
        mediaName: String,
        mediaTierInfo: Attachment.MediaTierInfo?,
        scheduleDownload: Bool = false,
        scheduleUpload: Bool = false,
        tx: DBWriteTransaction
    ) -> Attachment.IDType {
        let thread = TSThread(uniqueId: UUID().uuidString)
        try! thread.asRecord().insert(tx.database)
        let attachmentParams: Attachment.ConstructionParams
        if scheduleDownload {
            attachmentParams = Attachment.ConstructionParams.fromBackup(
                blurHash: nil,
                mimeType: "image/jpeg",
                encryptionKey: UUID().data,
                transitTierInfo: nil,
                sha256ContentHash: UUID().data,
                mediaName: mediaName,
                mediaTierInfo: mediaTierInfo,
                thumbnailMediaTierInfo: nil
            )
        } else {
            attachmentParams = Attachment.ConstructionParams.mockStream(
                mediaName: mediaName
            )
        }
        var attachmentRecord = Attachment.Record(params: attachmentParams)
        try! attachmentRecord.insert(tx.database)
        if let mediaTierInfo {
            let updateParams = Attachment.ConstructionParams.forUpdatingAsUploadedToMediaTier(
                attachment: try! Attachment(record: attachmentRecord),
                mediaTierInfo: mediaTierInfo,
                mediaName: mediaName
            )
            var updateRecord = Attachment.Record(params: updateParams)
            updateRecord.sqliteId = attachmentRecord.sqliteId
            try! updateRecord.update(tx.database)
        }
        // We make all the attachments just thread wallpapers for ease of setup;
        // for list media purposes it doesn't matter if its a message attachment
        // or thread wallpaper attachment.
        let referenceParams = AttachmentReference.ConstructionParams.mock(
            owner: .thread(.threadWallpaperImage(.init(
                threadRowId: thread.sqliteRowId!,
                creationTimestamp: 0
            )))
        )
        let referenceRecord = try! referenceParams.buildRecord(
            attachmentRowId: attachmentRecord.sqliteId!
        )
        try! referenceRecord.insert(tx.database)

        if scheduleDownload {
            try! backupAttachmentDownloadStore.enqueue(
                ReferencedAttachment(
                    reference: AttachmentReference(record: referenceRecord as! AttachmentReference.ThreadAttachmentReferenceRecord),
                    attachment: Attachment(record: attachmentRecord)
                ),
                thumbnail: false,
                canDownloadFromMediaTier: true,
                state: .ready,
                currentTimestamp: 0,
                tx: tx
            )
        }

        if scheduleUpload {
            try! backupAttachmentUploadStore.enqueue(
                Attachment(record: attachmentRecord).asStream()!,
                owner: .threadWallpaper,
                fullsize: true,
                tx: tx
            )
        }

        return attachmentRecord.sqliteId!
    }
}

// MAEK: - Mocks

private class BackupRequestManagerMock: BackupRequestManager {

    init() {}

    func fetchBackupServiceAuth(
        for credentialType: SignalServiceKit.BackupAuthCredentialType,
        localAci: LibSignalClient.Aci,
        auth: SignalServiceKit.ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool
    ) async throws -> SignalServiceKit.BackupServiceAuth {
        return BackupServiceAuth.mock(type: .media, backupLevel: .paid)
    }

    func fetchBackupUploadForm(
        backupByteLength: UInt32,
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws -> SignalServiceKit.Upload.Form {
        fatalError("Unimplemented")
    }

    func fetchBackupMediaAttachmentUploadForm(
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws -> SignalServiceKit.Upload.Form {
        fatalError("Unimplemented")
    }

    func fetchMediaTierCdnRequestMetadata(
        cdn: Int32,
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws -> SignalServiceKit.MediaTierReadCredential {
        fatalError("Unimplemented")
    }

    func fetchBackupRequestMetadata(
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws -> SignalServiceKit.BackupReadCredential {
        fatalError("Unimplemented")
    }

    func copyToMediaTier(
        item: SignalServiceKit.BackupArchive.Request.MediaItem,
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws -> UInt32 {
        fatalError("Unimplemented")
    }

    func copyToMediaTier(
        items: [SignalServiceKit.BackupArchive.Request.MediaItem],
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws -> [SignalServiceKit.BackupArchive.Response.BatchedBackupMediaResult] {
        fatalError("Unimplemented")
    }

    var listMediaResults = [BackupArchive.Response.ListMediaResult]()

    func listMediaObjects(
        cursor: String?,
        limit: UInt32?,
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws -> SignalServiceKit.BackupArchive.Response.ListMediaResult {
        return listMediaResults.popFirst()!
    }

    func deleteMediaObjects(
        objects: [SignalServiceKit.BackupArchive.Request.DeleteMediaTarget],
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws {
        fatalError("Unimplemented")
    }

    func redeemReceipt(receiptCredentialPresentation: Data) async throws {
        fatalError("Unimplemented")
    }
}
