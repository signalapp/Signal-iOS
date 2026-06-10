//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import Testing

@testable import SignalServiceKit

public class BackupListMediaManagerTests {

    private lazy var accountKeyStore = AccountKeyStore(backupSettingsStore: backupSettingsStore)
    private let attachmentStore = AttachmentStore()
    private let attachmentUploadStore = AttachmentUploadStore()
    private let backupAttachmentDownloadProgress = BackupAttachmentDownloadProgressMock()
    private let backupAttachmentDownloadStore = BackupAttachmentDownloadStore()
    private let backupAttachmentUploadProgress = BackupAttachmentUploadProgressMock(initialCompleted: 0, total: 100)
    private let backupAttachmentUploadStore = BackupAttachmentUploadStore()
    private let backupAttachmentUploadEraStore = BackupAttachmentUploadEraStore()
    private let backupListMediaStore = BackupListMediaStore()
    private lazy var backupMediaErrorNotificationPresenter = BackupMediaErrorNotificationPresenter(
        dateProvider: dateProvider,
        db: db,
        notificationPresenter: notificationPresenter,
    )
    private let backupRequestManager = BackupRequestManagerMock()
    private let backupSettingsStore = BackupSettingsStore()
    private let dateProvider: DateProvider = { Date() }
    private let db = InMemoryDB()
    private let interactionStore = InteractionStoreImpl()
    private let notificationPresenter = NoopNotificationPresenterImpl()
    private let orphanedBackupAttachmentStore = OrphanedBackupAttachmentStore()
    private let remoteConfigManager = StubbableRemoteConfigManager()
    private let tsAccountManager = MockTSAccountManager()
    private lazy var backupAttachmentUploadScheduler = BackupAttachmentUploadScheduler(
        attachmentStore: attachmentStore,
        backupAttachmentUploadStore: backupAttachmentUploadStore,
        backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
        dateProvider: dateProvider,
        interactionStore: interactionStore,
        remoteConfigProvider: remoteConfigManager,
        tsAccountManager: tsAccountManager,
    )

    private lazy var listMediaManager = BackupListMediaManagerImpl(
        accountKeyStore: accountKeyStore,
        attachmentStore: attachmentStore,
        attachmentUploadStore: attachmentUploadStore,
        backupAttachmentDownloadProgress: backupAttachmentDownloadProgress,
        backupAttachmentDownloadStore: backupAttachmentDownloadStore,
        backupAttachmentUploadProgress: backupAttachmentUploadProgress,
        backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
        backupAttachmentUploadStore: backupAttachmentUploadStore,
        backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
        backupListMediaStore: backupListMediaStore,
        backupMediaErrorNotificationPresenter: backupMediaErrorNotificationPresenter,
        backupRequestManager: backupRequestManager,
        backupSettingsStore: backupSettingsStore,
        dateProvider: dateProvider,
        db: db,
        notificationPresenter: notificationPresenter,
        orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
        remoteConfigManager: remoteConfigManager,
        tsAccountManager: tsAccountManager,
    )

    @Test
    func testListMedia() async throws {
        let localUploadEra = "1"

        let remoteConfigCdnNumber: UInt32 = 100
        remoteConfigManager._currentConfig = RemoteConfig(
            clockSkew: 0,
            valueFlags: ["global.backups.mediaTierFallbackCdnNumber": "\(remoteConfigCdnNumber)"],
        )

        let mediaRootBackupKey = MediaRootBackupKey(backupKey: .generateRandom())
        await db.awaitableWrite { tx in
            accountKeyStore.setMediaRootBackupKey(mediaRootBackupKey, tx: tx)
            backupSettingsStore.setBackupPlan(.paid(optimizeLocalStorage: false), tx: tx)
        }

        // Make a few attachments so we hit a couple pages of results
        // from the request and from local db reads.
        let numAttachmentsPerCase = 50

        // There are N cases we care about:

        // Case 1: Attachment exists locally but not on CDN
        let localOnlyIds = await db.awaitableWrite { tx in
            return (0..<numAttachmentsPerCase).map { _ in
                let plaintextHash = Randomness.generateRandomBytes(32)
                return insertAttachment(
                    plaintextHash: plaintextHash,
                    encryptionKey: .generate(),
                    mediaTierInfo: .init(
                        cdnNumber: 1,
                        unencryptedByteCount: 100,
                        plaintextHash: plaintextHash,
                        incrementalMacInfo: nil,
                        uploadEra: localUploadEra,
                        lastDownloadAttemptTimestamp: nil,
                    ),
                    tx: tx,
                )
            }
        }

        // Case 2: Attachment exists on cdn but not locally
        let orphanCdnNumber: UInt32 = 99
        let remoteOnlyCdnNumberMedia = (0..<numAttachmentsPerCase).map { _ in
            return BackupArchive.Response.StoredMedia(
                cdn: orphanCdnNumber,
                mediaId: Randomness.generateRandomBytes(15).hexadecimalString,
                objectLength: 100,
            )
        }
        // For other cases, we'll add duplicate entries on cdn at different
        // cdn numbers that should be orphaned like case 2
        var orphanCdnNumberMedia = [BackupArchive.Response.StoredMedia]()

        // Case 3: exists on both, local didn't have cdn info
        let discoveredCdnNumber: UInt32 = 5
        var discoveredCdnNumberMedia = [BackupArchive.Response.StoredMedia]()
        let discoveredCdnNumberIds = await db.awaitableWrite { tx in
            return (0..<numAttachmentsPerCase).map { _ in
                let plaintextHash = Randomness.generateRandomBytes(32)
                let encryptionKey = AttachmentKey.generate()
                let mediaName = Attachment.mediaName(
                    plaintextHash: plaintextHash,
                    encryptionKey: encryptionKey.combinedKey,
                )
                let fullsizeMediaId = try! mediaRootBackupKey.deriveMediaId(mediaName)
                let thumbnailMediaId = try! mediaRootBackupKey.deriveMediaId(AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName))
                for mediaId in [fullsizeMediaId, thumbnailMediaId] {
                    discoveredCdnNumberMedia.append(.init(
                        cdn: discoveredCdnNumber,
                        mediaId: mediaId.asBase64Url,
                        objectLength: 100,
                    ))
                }
                return insertAttachment(
                    plaintextHash: plaintextHash,
                    encryptionKey: encryptionKey,
                    mediaTierInfo: nil,
                    tx: tx,
                )
            }
        }

        // Case 4: exists on both, cdn number matches.
        let matchingCdnNumber: UInt32 = 3
        var matchingCdnNumberMedia = [BackupArchive.Response.StoredMedia]()
        let matchingCdnNumberIds = await db.awaitableWrite { tx in
            return (0..<numAttachmentsPerCase).map { _ in
                let plaintextHash = Randomness.generateRandomBytes(32)
                let encryptionKey = AttachmentKey.generate()
                let mediaName = Attachment.mediaName(
                    plaintextHash: plaintextHash,
                    encryptionKey: encryptionKey.combinedKey,
                )
                let fullsizeMediaId = try! mediaRootBackupKey.deriveMediaId(mediaName)
                let thumbnailMediaId = try! mediaRootBackupKey.deriveMediaId(AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName))
                for mediaId in [fullsizeMediaId, thumbnailMediaId] {
                    matchingCdnNumberMedia.append(.init(
                        cdn: matchingCdnNumber,
                        mediaId: mediaId.asBase64Url,
                        objectLength: 100,
                    ))
                    orphanCdnNumberMedia.append(.init(
                        cdn: orphanCdnNumber,
                        mediaId: mediaId.asBase64Url,
                        objectLength: 100,
                    ))
                }
                return insertAttachment(
                    plaintextHash: plaintextHash,
                    encryptionKey: encryptionKey,
                    mediaTierInfo: .init(
                        cdnNumber: matchingCdnNumber,
                        unencryptedByteCount: 100,
                        plaintextHash: plaintextHash,
                        incrementalMacInfo: nil,
                        uploadEra: localUploadEra,
                        lastDownloadAttemptTimestamp: nil,
                    ),
                    tx: tx,
                )
            }
        }

        // Case 5: exists on both, cdn number doesn't match.
        var nonMatchingCdnNumberMedia = [BackupArchive.Response.StoredMedia]()
        let nonMatchingCdnNumberIds = await db.awaitableWrite { tx in
            return (0..<numAttachmentsPerCase).map { _ in
                let plaintextHash = Randomness.generateRandomBytes(32)
                let encryptionKey = AttachmentKey.generate()
                let mediaName = Attachment.mediaName(
                    plaintextHash: plaintextHash,
                    encryptionKey: encryptionKey.combinedKey,
                )
                let fullsizeMediaId = try! mediaRootBackupKey.deriveMediaId(mediaName)
                let thumbnailMediaId = try! mediaRootBackupKey.deriveMediaId(AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName))
                for mediaId in [fullsizeMediaId, thumbnailMediaId] {
                    nonMatchingCdnNumberMedia.append(.init(
                        // Prefer a cdn number matching remote config,
                        // instead of the other orphaned one below
                        cdn: remoteConfigCdnNumber,
                        mediaId: mediaId.asBase64Url,
                        objectLength: 100,
                    ))
                    orphanCdnNumberMedia.append(.init(
                        cdn: remoteConfigCdnNumber,
                        mediaId: mediaId.asBase64Url,
                        objectLength: 100,
                    ))
                }
                return insertAttachment(
                    plaintextHash: plaintextHash,
                    encryptionKey: encryptionKey,
                    mediaTierInfo: .init(
                        cdnNumber: matchingCdnNumber,
                        unencryptedByteCount: 100,
                        plaintextHash: plaintextHash,
                        incrementalMacInfo: nil,
                        uploadEra: localUploadEra,
                        lastDownloadAttemptTimestamp: nil,
                    ),
                    tx: tx,
                )
            }
        }

        // Set up mock list response
        backupRequestManager.listMediaResults = [
            BackupArchive.Response.ListMediaResult(
                storedMediaObjects: remoteOnlyCdnNumberMedia,
                backupDir: "",
                mediaDir: "",
                cursor: "someCursor",
            ),
            BackupArchive.Response.ListMediaResult(
                storedMediaObjects: discoveredCdnNumberMedia,
                backupDir: "",
                mediaDir: "",
                cursor: "someCursor",
            ),
            BackupArchive.Response.ListMediaResult(
                storedMediaObjects: matchingCdnNumberMedia,
                backupDir: "",
                mediaDir: "",
                cursor: "someCursor",
            ),
            BackupArchive.Response.ListMediaResult(
                storedMediaObjects: nonMatchingCdnNumberMedia,
                backupDir: "",
                mediaDir: "",
                cursor: "someCursor",
            ),
            BackupArchive.Response.ListMediaResult(
                storedMediaObjects: orphanCdnNumberMedia,
                backupDir: "",
                mediaDir: "",
                cursor: nil,
            ),
        ]

        try await listMediaManager.queryListMediaIfNeeded()

        // Case 1 should've been marked as not uploaded to media tier,
        // removed from download queue and added to upload queue for both
        // fullsize and thumbnail.
        db.read { tx in
            for attachmentId in localOnlyIds {
                let attachment = attachmentStore.fetch(id: attachmentId, tx: tx)!
                #expect(attachment.mediaTierInfo == nil)
                #expect(attachment.thumbnailMediaTierInfo == nil)

                for thumbnail in [true, false] {
                    let enqueuedDownload = backupAttachmentDownloadStore.getEnqueuedDownload(
                        attachmentRowId: attachmentId,
                        thumbnail: thumbnail,
                        tx: tx,
                    )
                    let enqueuedUpload = backupAttachmentUploadStore.getEnqueuedUpload(
                        for: attachmentId,
                        fullsize: !thumbnail,
                        tx: tx,
                    )

                    #expect(enqueuedDownload == nil)
                    #expect(enqueuedUpload != nil)
                }
            }
        }

        // Case 2, and other duplicates, should've been marked for deletion.
        db.read { tx in
            for orphanMedia in remoteOnlyCdnNumberMedia + orphanCdnNumberMedia {
                let mediaId = try! Data.data(fromBase64Url: orphanMedia.mediaId)
                #expect(
                    try! OrphanedBackupAttachment
                        .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaId) == mediaId)
                        .filter(Column(OrphanedBackupAttachment.CodingKeys.cdnNumber) == orphanMedia.cdn)
                        .fetchCount(tx.database)
                        == 1,
                )
            }
        }

        // Case 3 should be updated with cdn info, with no uploads enqueued (for
        // either fullsize or thumbnail).
        db.read { tx in
            for attachmentId in discoveredCdnNumberIds {
                let attachment = attachmentStore.fetch(id: attachmentId, tx: tx)!
                let queuedUploadCount = try! QueuedBackupAttachmentUpload
                    .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.attachmentRowId) == attachmentId)
                    .fetchCount(tx.database)

                #expect(attachment.mediaTierInfo?.cdnNumber == discoveredCdnNumber)
                #expect(attachment.thumbnailMediaTierInfo?.cdnNumber == discoveredCdnNumber)
                #expect(queuedUploadCount == 0)
            }
        }

        // Case 4 should be untouched
        db.read { tx in
            for attachmentId in matchingCdnNumberIds {
                let attachment = attachmentStore.fetch(id: attachmentId, tx: tx)!
                #expect(attachment.mediaTierInfo?.cdnNumber == matchingCdnNumber)
                #expect(attachment.thumbnailMediaTierInfo?.cdnNumber == matchingCdnNumber)
            }
        }

        // Case 5 should be updated with the remote cdn number
        db.read { tx in
            for attachmentId in nonMatchingCdnNumberIds {
                let attachment = attachmentStore.fetch(id: attachmentId, tx: tx)!
                #expect(attachment.mediaTierInfo?.cdnNumber == remoteConfigCdnNumber)
                #expect(attachment.thumbnailMediaTierInfo?.cdnNumber == remoteConfigCdnNumber)
            }
        }
    }

    // MARK: - Helpers

    typealias Attachment = SignalServiceKit.Attachment

    private func insertAttachment(
        plaintextHash: Data,
        encryptionKey: AttachmentKey,
        mediaTierInfo: Attachment.MediaTierInfo?,
        tx: DBWriteTransaction,
    ) -> Attachment.IDType {
        owsPrecondition(mediaTierInfo == nil || mediaTierInfo!.plaintextHash == plaintextHash)

        let thread = TSThread(uniqueId: UUID().uuidString)
        try! thread.insert(tx.database)

        var attachmentRecord = Attachment.Record.mockStream(
            encryptionKey: encryptionKey,
            plaintextHash: plaintextHash,
        )
        try! attachmentRecord.insert(tx.database)

        if let mediaTierInfo {
            let attachment = Attachment(record: attachmentRecord)
            attachment.mediaTierInfo = mediaTierInfo

            attachmentRecord = Attachment.Record(attachment: attachment)
            try! attachmentRecord.update(tx.database)
        }

        // We make all the attachments just thread wallpapers for ease of setup;
        // for list media purposes it doesn't matter if its a message attachment
        // or thread wallpaper attachment.
        let referenceParams = AttachmentReference.ConstructionParams.mock(
            owner: .thread(.threadWallpaperImage(.init(
                threadRowId: thread.sqliteRowId!,
                creationTimestamp: 0,
            ))),
        )
        _ = attachmentStore.addReference(
            referenceParams,
            attachmentRowId: attachmentRecord.sqliteId!,
            tx: tx,
        )

        return attachmentRecord.sqliteId!
    }
}
