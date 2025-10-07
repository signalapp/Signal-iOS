//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol AttachmentUploadManager {
    /// Upload a transient backup file that isn't an attachment (not saved to the database or sent).
    func uploadBackup(
        localUploadMetadata: Upload.EncryptedBackupUploadMetadata,
        form: Upload.Form,
        progress: OWSProgressSink?
    ) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata>

    /// Upload a transient attachment that isn't saved to the database for sending.
    func uploadTransientAttachment(
        dataSource: DataSource,
        progress: OWSProgressSink?
    ) async throws -> Upload.Result<Upload.LocalUploadMetadata>

    /// Upload a transient link'n'sync attachment that isn't saved to the database for sending.
    func uploadLinkNSyncAttachment(
        dataSource: DataSource,
        progress: OWSProgressSink?
    ) async throws -> Upload.Result<Upload.LinkNSyncUploadMetadata>

    /// Upload an Attachment to the given endpoint.
    /// Will fail if the attachment doesn't exist or isn't available locally.
    func uploadTransitTierAttachment(
        attachmentId: Attachment.IDType,
        progress: OWSProgressSink?
    ) async throws

    /// Upload an attachment to the media tier (uploading to the transit tier if needed and copying to the media tier).
    /// Will fail if the attachment doesn't exist or isn't available locally.
    func uploadMediaTierAttachment(
        attachmentId: Attachment.IDType,
        uploadEra: String,
        localAci: Aci,
        backupKey: MediaRootBackupKey,
        auth: BackupServiceAuth,
        progress: OWSProgressSink?
    ) async throws

    /// Upload an attachment's thumbnail to the media tier (uploading to the transit tier and copying to the media tier).
    /// Will fail if the attachment doesn't exist or isn't available locally.
    func uploadMediaTierThumbnailAttachment(
        attachmentId: Attachment.IDType,
        uploadEra: String,
        localAci: Aci,
        backupKey: MediaRootBackupKey,
        auth: BackupServiceAuth,
        progress: OWSProgressSink?
    ) async throws
}

extension AttachmentUploadManager {

    public func uploadBackup(
        localUploadMetadata: Upload.EncryptedBackupUploadMetadata,
        form: Upload.Form
    ) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata> {
        try await uploadBackup(
            localUploadMetadata: localUploadMetadata,
            form: form,
            progress: nil
        )
    }

    public func uploadTransientAttachment(
        dataSource: DataSource
    ) async throws -> Upload.Result<Upload.LocalUploadMetadata> {
        try await uploadTransientAttachment(
            dataSource: dataSource,
            progress: nil
        )
    }

    public func uploadLinkNSyncAttachment(
        dataSource: DataSource
    ) async throws -> Upload.Result<Upload.LinkNSyncUploadMetadata> {
        try await uploadLinkNSyncAttachment(
            dataSource: dataSource,
            progress: nil
        )
    }

    public func uploadTransitTierAttachment(
        attachmentId: Attachment.IDType
    ) async throws {
        try await uploadTransitTierAttachment(
            attachmentId: attachmentId,
            progress: nil
        )
    }

    public func uploadMediaTierAttachment(
        attachmentId: Attachment.IDType,
        uploadEra: String,
        localAci: Aci,
        backupKey: MediaRootBackupKey,
        auth: BackupServiceAuth
    ) async throws {
        try await  uploadMediaTierAttachment(
            attachmentId: attachmentId,
            uploadEra: uploadEra,
            localAci: localAci,
            backupKey: backupKey,
            auth: auth,
            progress: nil
        )
    }

    public func uploadMediaTierThumbnailAttachment(
        attachmentId: Attachment.IDType,
        uploadEra: String,
        localAci: Aci,
        backupKey: MediaRootBackupKey,
        auth: BackupServiceAuth
    ) async throws {
        try await uploadMediaTierThumbnailAttachment(
            attachmentId: attachmentId,
            uploadEra: uploadEra,
            localAci: localAci,
            backupKey: backupKey,
            auth: auth,
            progress: nil
        )
    }
}

public actor AttachmentUploadManagerImpl: AttachmentUploadManager {

    private let accountKeyStore: AccountKeyStore
    private let attachmentEncrypter: Upload.Shims.AttachmentEncrypter
    private let attachmentStore: AttachmentStore
    private let attachmentUploadStore: AttachmentUploadStore
    private let attachmentThumbnailService: AttachmentThumbnailService
    private let backupRequestManager: BackupRequestManager
    private let dateProvider: DateProvider
    private let db: any DB
    private let fileSystem: Upload.Shims.FileSystem
    private let interactionStore: InteractionStore
    private let networkManager: NetworkManager
    private let remoteConfigProvider: any RemoteConfigProvider
    private let signalService: OWSSignalServiceProtocol
    private let sleepTimer: Upload.Shims.SleepTimer
    private let storyStore: StoryStore

    private struct ActiveUploadKey: Hashable {
        let attachmentId: Attachment.IDType
        let isThumbnailUpload: Bool

        init(attachmentId: Attachment.IDType, uploadType: UploadType) {
            self.attachmentId = attachmentId
            switch uploadType {
            case .transitTier:
                self.isThumbnailUpload = false
            case .mediaTier(_, let isThumbnail):
                self.isThumbnailUpload = isThumbnail
            }
        }
    }

    // Map of active upload tasks.
    private var activeUploads = [ActiveUploadKey: Task<(AttachmentUploadRecord, Upload.AttachmentResult), Error>]()

    private enum UploadType {
        case transitTier
        case mediaTier(auth: BackupServiceAuth, isThumbnail: Bool)

        var sourceType: AttachmentUploadRecord.SourceType {
            switch self {
            case .transitTier:
                return .transit
            case .mediaTier(_, let isThumbnail):
                return isThumbnail ? .thumbnail : .media
            }
        }

    }

    public init(
        accountKeyStore: AccountKeyStore,
        attachmentEncrypter: Upload.Shims.AttachmentEncrypter,
        attachmentStore: AttachmentStore,
        attachmentUploadStore: AttachmentUploadStore,
        attachmentThumbnailService: AttachmentThumbnailService,
        backupRequestManager: BackupRequestManager,
        dateProvider: @escaping DateProvider,
        db: any DB,
        fileSystem: Upload.Shims.FileSystem,
        interactionStore: InteractionStore,
        networkManager: NetworkManager,
        remoteConfigProvider: any RemoteConfigProvider,
        signalService: OWSSignalServiceProtocol,
        sleepTimer: Upload.Shims.SleepTimer,
        storyStore: StoryStore
    ) {
        self.accountKeyStore = accountKeyStore
        self.attachmentEncrypter = attachmentEncrypter
        self.attachmentStore = attachmentStore
        self.attachmentUploadStore = attachmentUploadStore
        self.attachmentThumbnailService = attachmentThumbnailService
        self.backupRequestManager = backupRequestManager
        self.dateProvider = dateProvider
        self.db = db
        self.fileSystem = fileSystem
        self.interactionStore = interactionStore
        self.networkManager = networkManager
        self.remoteConfigProvider = remoteConfigProvider
        self.signalService = signalService
        self.sleepTimer = sleepTimer
        self.storyStore = storyStore
    }

    public func uploadBackup(
        localUploadMetadata: Upload.EncryptedBackupUploadMetadata,
        form: Upload.Form,
        progress: OWSProgressSink?
    ) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata> {
        let logger = PrefixedLogger(prefix: "[Upload]", suffix: "[backup]")
        do {
            let attempt = try await AttachmentUpload.buildAttempt(
                for: localUploadMetadata,
                form: form,
                signalService: signalService,
                fileSystem: fileSystem,
                dateProvider: dateProvider,
                logger: logger
            )
            return try await AttachmentUpload.start(
                attempt: attempt,
                dateProvider: dateProvider,
                sleepTimer: sleepTimer,
                progress: progress,
            )
        } catch {
            if error.isNetworkFailureOrTimeout {
                logger.warn("Upload failed due to network error")
            } else if error is CancellationError {
                logger.warn("Upload cancelled")
            } else {
                if let statusCode = error.httpStatusCode {
                    logger.warn("Unexpected upload error [status: \(statusCode)]")
                } else {
                    logger.warn("Unexpected upload error")
                }
            }
            throw error
        }
    }

    public func uploadTransientAttachment(
        dataSource: DataSource,
        progress: OWSProgressSink?
    ) async throws -> Upload.Result<Upload.LocalUploadMetadata> {
        let logger = PrefixedLogger(prefix: "[Upload]", suffix: "[transient]")

        let temporaryFile = fileSystem.temporaryFileUrl()
        guard let sourceURL = dataSource.dataUrl else {
            throw OWSAssertionError("Failed to access data source file")
        }
        let metadata = try attachmentEncrypter.encryptAttachment(at: sourceURL, output: temporaryFile)
        let localMetadata = try Upload.LocalUploadMetadata.validateAndBuild(fileUrl: temporaryFile, metadata: metadata)
        let form = try await Upload.FormRequest(
            networkManager: networkManager
        ).start()

        do {
            // We don't show progress for transient uploads
            let attempt = try await AttachmentUpload.buildAttempt(
                for: localMetadata,
                form: form,
                signalService: signalService,
                fileSystem: fileSystem,
                dateProvider: dateProvider,
                logger: logger
            )
            return try await AttachmentUpload.start(
                attempt: attempt,
                dateProvider: dateProvider,
                sleepTimer: sleepTimer,
                progress: nil
            )
        } catch {
            if error.isNetworkFailureOrTimeout {
                logger.warn("Upload failed due to network error")
            } else if error is CancellationError {
                logger.warn("Upload cancelled")
            } else {
                if let statusCode = error.httpStatusCode {
                    logger.warn("Unexpected upload error [status: \(statusCode)]")
                } else {
                    logger.warn("Unexpected upload error")
                }
            }
            throw error
        }
    }

    public func uploadLinkNSyncAttachment(
        dataSource: DataSource,
        progress: OWSProgressSink?
    ) async throws -> Upload.Result<Upload.LinkNSyncUploadMetadata> {
        let logger = PrefixedLogger(prefix: "[Upload]", suffix: "[link'n'sync]")

        let dataLength = dataSource.dataLength
        guard
            let sourceURL = dataSource.dataUrl,
            dataLength > 0,
            let dataLength = UInt32(exactly: dataLength)
        else {
            throw OWSAssertionError("Failed to access data source file")
        }
        let metadata = Upload.LinkNSyncUploadMetadata(fileUrl: sourceURL, encryptedDataLength: dataLength)
        let form = try await Upload.FormRequest(
            networkManager: networkManager
        ).start()

        do {
            // We don't show progress for transient uploads
            let attempt = try await AttachmentUpload.buildAttempt(
                for: metadata,
                form: form,
                signalService: signalService,
                fileSystem: fileSystem,
                dateProvider: dateProvider,
                logger: logger
            )
            return try await AttachmentUpload.start(
                attempt: attempt,
                dateProvider: dateProvider,
                sleepTimer: sleepTimer,
                progress: progress
            )
        } catch {
            if error.isNetworkFailureOrTimeout {
                logger.warn("Upload failed due to network error")
            } else if error is CancellationError {
                logger.warn("Upload cancelled")
            } else {
                if let statusCode = error.httpStatusCode {
                    logger.warn("Unexpected upload error [status: \(statusCode)]")
                } else {
                    logger.warn("Unexpected upload error")
                }
            }
            throw error
        }
    }

    public func uploadTransitTierAttachment(
        attachmentId: Attachment.IDType,
        progress: OWSProgressSink?
    ) async throws {
        let logger = PrefixedLogger(prefix: "[Upload]", suffix: "[\(attachmentId)]")

        let encryptedByteCount = db.read { tx in
            return attachmentStore.fetch(id: attachmentId, tx: tx)?.streamInfo?.encryptedByteCount
        } ?? 0

        let progressSource = await progress?.addSource(
            withLabel: "upload",
            unitCount: UInt64(encryptedByteCount)
        )

        let wrappedProgress: OWSProgressSink = OWSProgress.createSink { [weak self] progressValue in
            self?.updateProgress(id: attachmentId, progress: Double(progressValue.percentComplete))
            if let progressSource, progressSource.completedUnitCount < progressValue.completedUnitCount {
                progressSource.incrementCompletedUnitCount(
                    by: progressValue.completedUnitCount - progressSource.completedUnitCount
                )
            }
        }

        let (record, result) = try await uploadAttachment(
            attachmentId: attachmentId,
            type: .transitTier,
            logger: logger,
            progress: wrappedProgress
        )

        // Update the attachment and associated messages with the success
        // and clean up and left over upload state
        try await db.awaitableWrite { tx in
            // Read the attachment fresh from the DB
            guard let attachmentStream = try? self.fetchAttachment(
                attachmentId: attachmentId,
                logger: logger,
                tx: tx
            ).asStream() else {
                logger.warn("Attachment deleted while uploading")
                return
            }

            try self.updateTransitTier(
                attachmentStream: attachmentStream,
                with: result,
                logger: logger,
                tx: tx
            )

            self.cleanup(record: record, logger: logger, tx: tx)
        }
    }

    public func uploadMediaTierAttachment(
        attachmentId: Attachment.IDType,
        uploadEra: String,
        localAci: Aci,
        backupKey: MediaRootBackupKey,
        auth: BackupServiceAuth,
        progress: OWSProgressSink?
    ) async throws {
        let logger = PrefixedLogger(prefix: "[MediaTierUpload]", suffix: "[\(attachmentId)]")
        let (record, uploadResult) = try await uploadAttachment(
            attachmentId: attachmentId,
            type: .mediaTier(auth: auth, isThumbnail: false),
            logger: logger,
            progress: progress
        )

        // Read the attachment fresh from the DB
        guard
            let attachmentStream = try? db.read(block: { try self.fetchAttachment(
                attachmentId: attachmentId,
                logger: logger,
                tx: $0
            )}).asStream(),
            let mediaName = attachmentStream.attachment.mediaName
        else {
            logger.warn("Attachment deleted while uploading")
            return
        }

        let cdnNumber: UInt32
        do {
            cdnNumber =  try await self.copyToMediaTier(
                backupKey: backupKey,
                auth: auth,
                mediaName: mediaName,
                uploadEra: uploadEra,
                result: uploadResult,
                logger: logger
            )
        } catch let error as BackupArchive.Response.CopyToMediaTierError {
            switch error {
            case .sourceObjectNotFound:
                let attachmentFileUrl = AttachmentStream.absoluteAttachmentFileURL(
                    relativeFilePath: attachmentStream.localRelativeFilePath
                )
                let fileMissingOrEmpty = !OWSFileSystem.fileOrFolderExists(url: attachmentFileUrl)
                    || (OWSFileSystem.fileSize(of: attachmentFileUrl)?.uint32Value ?? 0) == 0

                try await db.awaitableWrite { tx in
                    // Clean up the upload record; if we failed to copy
                    // we want to start an upload fresh next time.
                    self.cleanup(record: record, logger: logger, tx: tx)

                    if fileMissingOrEmpty {
                        logger.error("Missing attachment file!")

                        guard let attachment = attachmentStore.fetch(id: attachmentStream.id, tx: tx) else {
                            return
                        }

                        let params = Attachment.ConstructionParams.forOffloadingFiles(
                            attachment: attachment,
                            localRelativeFilePathThumbnail: nil
                        )
                        var newRecord = Attachment.Record(params: params)
                        newRecord.sqliteId = attachment.id
                        try newRecord.update(tx.database)
                    }

                    if
                        uploadResult.localUploadMetadata.isReusedTransitTierUpload,
                        let transitTierInfo = attachmentStream.attachment.latestTransitTierInfo
                    {
                        // We reused a transit tier upload but the source couldn't be found.
                        // That transit tier upload is now invalid.
                        // Refetch the attachment
                        guard let attachment = attachmentStore.fetch(id: attachmentStream.id, tx: tx) else {
                            return
                        }

                        try self.attachmentUploadStore.markTransitTierUploadExpired(
                            attachment: attachment,
                            info: transitTierInfo,
                            tx: tx
                        )
                    }
                }
                throw error
            default:
                throw error
            }
        } catch {
            throw error
        }

        try await db.awaitableWrite { tx in
            // Refetch the attachment to ensure other fields are up-to-date.
            guard let attachmentStream = attachmentStore.fetch(id: attachmentStream.id, tx: tx)?.asStream() else {
                return
            }

            let mediaTierInfo = Attachment.MediaTierInfo(
                cdnNumber: cdnNumber,
                unencryptedByteCount: uploadResult.localUploadMetadata.plaintextDataLength,
                sha256ContentHash: attachmentStream.sha256ContentHash,
                // TODO: [Attachment Streaming] support incremental mac
                incrementalMacInfo: nil,
                uploadEra: uploadEra,
                lastDownloadAttemptTimestamp: nil
            )

            try self.attachmentUploadStore.markUploadedToMediaTier(
                attachment: attachmentStream.attachment,
                mediaTierInfo: mediaTierInfo,
                mediaName: attachmentStream.info.mediaName,
                tx: tx
            )

            // To upload to media tier, we also upload to transit tier and then perform a copy.
            // We can save the transit tier info from that upload to the attachment, in some cases.
            let shouldUpdateTransitTierInfo: Bool = {
                guard let oldTransitTierInfo = attachmentStream.attachment.latestTransitTierInfo else {
                    // First case: we had no transit tier info; something is better than nothing.
                    return true
                }
                let nowMs = dateProvider().ows_millisecondsSince1970
                if
                    nowMs > oldTransitTierInfo.uploadTimestamp,
                    nowMs - oldTransitTierInfo.uploadTimestamp > remoteConfigProvider.currentConfig().messageQueueTimeMs
                {
                    // Second case: the transit tier info is old and expired.
                    return true
                }
                if
                    nowMs > oldTransitTierInfo.uploadTimestamp,
                    nowMs - oldTransitTierInfo.uploadTimestamp > UInt64(Upload.Constants.uploadReuseWindow * Double(MSEC_PER_SEC)),
                    oldTransitTierInfo.encryptionKey != attachmentStream.attachment.encryptionKey
                {
                    // Third case: the transit tier info isn't expired, but exceeded its reuse window
                    // anyway so it wasn't going to be used for forwarding. May as well replace it
                    // with an upload that can be used for _something_.
                    return true
                }
                // Note: if the old transit tier info has been within the reuse window
                // _and_ used the same encryption key, we wouldn't have reuploaded for
                // this media tier copy so "oldTransitTierInfo" would be the very one
                // we reused to create "uploadResult" without uploading to begin with.
                return false
            }()

            if shouldUpdateTransitTierInfo {
                let transitTierInfo = Attachment.TransitTierInfo(
                    cdnNumber: uploadResult.cdnNumber,
                    cdnKey: uploadResult.cdnKey,
                    uploadTimestamp: uploadResult.beginTimestamp,
                    encryptionKey: uploadResult.localUploadMetadata.key,
                    unencryptedByteCount: uploadResult.localUploadMetadata.plaintextDataLength,
                    // ALWAYS use digest for integrity check for uploaded attachments;
                    // we only allow sending using a digest integrity check not a plaintext hash
                    // so prefer digest if we have both. If we don't, this attachment we just
                    // uploaded will fail to send.
                    integrityCheck: .digestSHA256Ciphertext(uploadResult.localUploadMetadata.digest),
                    // TODO: [Attachment Streaming] support incremental mac
                    incrementalMacInfo: nil,
                    lastDownloadAttemptTimestamp: nil
                )
                // Refetch so we get the updated media tier info from above.
                if let attachmentStream = attachmentStore.fetch(id: attachmentStream.id, tx: tx)?.asStream() {
                    try self.attachmentUploadStore.markUploadedToTransitTier(
                        attachmentStream: attachmentStream,
                        info: transitTierInfo,
                        tx: tx
                    )
                }
            }

            self.cleanup(record: record, logger: logger, tx: tx)
        }
    }

    public func uploadMediaTierThumbnailAttachment(
        attachmentId: Attachment.IDType,
        uploadEra: String,
        localAci: Aci,
        backupKey: MediaRootBackupKey,
        auth: BackupServiceAuth,
        progress: OWSProgressSink?
    ) async throws {
        let logger = PrefixedLogger(prefix: "[MediaTierThumbnailUpload]", suffix: "[\(attachmentId)]")
        let (record, result) = try await uploadAttachment(
            attachmentId: attachmentId,
            type: .mediaTier(auth: auth, isThumbnail: true),
            logger: logger,
            progress: progress
        )

        // Read the attachment fresh from the DB
        guard
            let attachmentStream = try? db.read(block: { try self.fetchAttachment(
                attachmentId: attachmentId,
                logger: logger,
                tx: $0
            )}).asStream(),
            let mediaName = attachmentStream.attachment.mediaName
        else {
            logger.warn("Attachment deleted while uploading")
            return
        }

        let cdnNumber: UInt32
        do {
            cdnNumber = try await self.copyToMediaTier(
                backupKey: backupKey,
                auth: auth,
                mediaName: AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName),
                uploadEra: uploadEra,
                result: result,
                logger: logger
            )
        } catch let error as BackupArchive.Response.CopyToMediaTierError {
            switch error {
            case .sourceObjectNotFound:
                await db.awaitableWrite { tx in
                    // Clean up the upload record; if we failed to copy
                    // we want to start an upload fresh.
                    self.cleanup(record: record, logger: logger, tx: tx)
                }
                throw error
            default:
                throw error
            }
        } catch {
            throw error
        }

        try await db.awaitableWrite { tx in
            // Refetch the attachment to ensure other fields are up-to-date.
            guard let attachmentStream = attachmentStore.fetch(id: attachmentStream.id, tx: tx)?.asStream() else {
                return
            }

            let thumbnailInfo = Attachment.ThumbnailMediaTierInfo(
                cdnNumber: cdnNumber,
                uploadEra: uploadEra,
                lastDownloadAttemptTimestamp: nil
            )

            try self.attachmentUploadStore.markThumbnailUploadedToMediaTier(
                attachment: attachmentStream.attachment,
                thumbnailMediaTierInfo: thumbnailInfo,
                mediaName: attachmentStream.info.mediaName,
                tx: tx
            )

            self.cleanup(record: record, logger: logger, tx: tx)
        }
    }

    /// Entry point for uploading an `AttachmentStream`
    /// Fetches the `AttachmentStream`, fetches an upload form, builds the AttachmentUpload, begins the
    /// upload, and updates the `AttachmentStream` upon success.
    ///
    /// It is assumed any errors that could be retried or otherwise handled will have happend at a lower level,
    /// so any error encountered here is considered unrecoverable and thrown to the caller.
    ///
    /// Resumption of an active upload can be handled at a lower level, but if the endpoint returns an
    /// error that requires a full restart, this is the method that will be called to fetch a new upload form and
    /// rebuild the endpoint and upload state before trying again.
    private func uploadAttachment(
        attachmentId: Attachment.IDType,
        type: UploadType,
        logger: PrefixedLogger,
        progress: OWSProgressSink?
    ) async throws -> (record: AttachmentUploadRecord, result: Upload.AttachmentResult) {

        let activeUploadKey = ActiveUploadKey(attachmentId: attachmentId, uploadType: type)
        if let activeUpload = activeUploads[activeUploadKey] {
            // If this fails, it means the internal retry logic has given up, so don't
            // attempt any retries here
            do {
                return try await activeUpload.value
            } catch {
                return try await uploadAttachment(
                    attachmentId: attachmentId,
                    type: type,
                    logger: logger,
                    progress: progress
                )
            }
        }

        let attachment = try db.read(block: { tx in
            try fetchAttachment(attachmentId: attachmentId, logger: logger, tx: tx)
        })

        let uploadTask = Task {
            defer {
                // Clear out the active upload task once it finishes running.
                activeUploads[activeUploadKey] = nil
            }

            // This task will only fail if a non-recoverable error is encountered, or the
            // max number of retries is exhausted.
            return try await self.upload(
                attachment: attachment,
                type: type,
                logger: logger,
                progress: progress
            )
        }

        // Add the active task to allow any additional scheduled uploads to reuse the same upload
        activeUploads[activeUploadKey] = uploadTask
        return try await uploadTask.value
    }

    private func upload(
        attachment: Attachment,
        type: UploadType,
        logger: PrefixedLogger,
        progress: OWSProgressSink?
    ) async throws -> (AttachmentUploadRecord, Upload.AttachmentResult) {
        let attachmentId = attachment.id
        var updateRecord = false
        var cleanupMetadata = false

        // Fetch the record if it exists, or create a new one.
        // Note this record isn't persisted in this method, so it will need to be saved later.
        var attachmentUploadRecord = try self.fetchOrCreateAttachmentRecord(
            for: attachmentId,
            sourceType: type.sourceType,
            db: db
        )

        // Fetch or build the LocalUploadMetadata.
        // See `Attachment.transitUploadStrategy(dateProvider:)` for details on when metadata
        // is reused vs. constructed new.
        let localMetadata: Upload.LocalUploadMetadata
        switch try await getOrFetchUploadMetadata(
            attachment: attachment,
            type: type,
            record: attachmentUploadRecord,
            logger: logger
        ) {
        case .existing(let metadata), .reuse(let metadata):
            // Cached metadata is still good to use
            localMetadata = metadata

            if metadata.key != attachmentUploadRecord.localMetadata?.key {
                // If we're using a different key, reset the metadata
                // and start with a fresh upload form.
                updateRecord = true
                attachmentUploadRecord.localMetadata = metadata
                attachmentUploadRecord.uploadForm = nil
                attachmentUploadRecord.uploadFormTimestamp = nil
                attachmentUploadRecord.uploadSessionUrl = nil
            }

        case .new(let metadata):
            localMetadata = metadata
            updateRecord = true
            cleanupMetadata = true

            // New metadata was constructed, so clear out the stale upload form.
            attachmentUploadRecord.localMetadata = metadata
            attachmentUploadRecord.uploadForm = nil
            attachmentUploadRecord.uploadFormTimestamp = nil
            attachmentUploadRecord.uploadSessionUrl = nil
        case .alreadyUploaded(let metadata):
            // No need to upload - Cleanup the upload record and return
            return (
                attachmentUploadRecord,
                Upload.AttachmentResult(
                    cdnKey: metadata.cdnKey,
                    cdnNumber: metadata.cdnNumber,
                    localUploadMetadata: metadata,
                    beginTimestamp: dateProvider().ows_millisecondsSince1970,
                    finishTimestamp: dateProvider().ows_millisecondsSince1970
                )
            )
        }

        /// Check for a cached upload form
        /// This can be up to ~7 days old from the point of upload starting. Just to avoid running into any fuzzieness around the 7 day expiration, expire the form after 6 days
        /// If the upload hasn't started, the form shouldnt' be cached
        let uploadForm: Upload.Form
        if
            let form = attachmentUploadRecord.uploadForm,
            let formTimestamp = attachmentUploadRecord.uploadFormTimestamp,
            // And we are still in the window to reuse it
            dateProvider().timeIntervalSince(
                Date(millisecondsSince1970: formTimestamp)
            ) <= Upload.Constants.uploadFormReuseWindow
        {
            uploadForm = form
        } else {
            updateRecord = true
            switch type {
            case .transitTier:
                uploadForm = try await Upload.FormRequest(
                    networkManager: self.networkManager
                ).start()
            case .mediaTier(let auth, _):
                uploadForm = try await self.backupRequestManager
                    .fetchBackupMediaAttachmentUploadForm(auth: auth)
            }

            attachmentUploadRecord.uploadForm = uploadForm
            attachmentUploadRecord.uploadFormTimestamp = Date().ows_millisecondsSince1970
            attachmentUploadRecord.uploadSessionUrl = nil
        }

        do {
            let attempt = try await AttachmentUpload.buildAttempt(
                for: localMetadata,
                form: uploadForm,
                existingSessionUrl: attachmentUploadRecord.uploadSessionUrl,
                signalService: self.signalService,
                fileSystem: self.fileSystem,
                dateProvider: self.dateProvider,
                logger: logger
            )

            // The upload record has modified the metadata, upload form,
            // or upload session URL, so persist it before beginning the upload.
            if updateRecord || attachmentUploadRecord.uploadSessionUrl == nil {
                try await db.awaitableWrite { tx in
                    attachmentUploadRecord.uploadSessionUrl = attempt.uploadLocation
                    try self.attachmentUploadStore.upsert(record: attachmentUploadRecord, tx: tx)
                }
            }

            let result = try await AttachmentUpload.start(
                attempt: attempt,
                dateProvider: self.dateProvider,
                sleepTimer: sleepTimer,
                progress: progress
            )

            // On success, cleanup the temp file.  Temp files are only created for
            // new local metadata, otherwise the existing attachment file location is used.
            // TODO: Tie this in with OrphanedAttachmentRecord to track this
            if cleanupMetadata {
                if
                    localMetadata.fileUrl == (attachment.streamInfo?.localRelativeFilePath).map({
                        AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: $0)
                    })
                {
                    owsFailDebug("Attempting to delete attachment file!")
                } else {
                    do {
                        try fileSystem.deleteFile(url: localMetadata.fileUrl)
                    } catch {
                        owsFailDebug("Error: \(error)")
                    }
                }
            }
            return (attachmentUploadRecord, result.asAttachmentResult)
        } catch {

            // If the max number of upload failures was hit, give up and throw an error
            if attachmentUploadRecord.attempt >= Upload.Constants.maxUploadAttempts {
                await db.awaitableWrite { tx in
                    self.cleanup(record: attachmentUploadRecord, logger: logger, tx: tx)
                }
                throw error
            }

            // If an uploadFailure has percolated up to this layer, it means AttachmentUpload
            // has failed in it's retries. Usually this means something with the form or
            // metadata is in error or expired, so clear everything out and try again.
            if case Upload.Error.uploadFailure = error {

                // Only bump the attempt count if the upload failed.  Don't bump for things
                // like network issues
                attachmentUploadRecord.attempt += 1

                // If the error has made it here, something was encountered during upload that requires
                // a full restart of the upload.
                // This means at least throwing away the upload form, and just to be sure,
                // throw away the local metadata as well.
                attachmentUploadRecord.localMetadata = nil
                attachmentUploadRecord.uploadForm = nil
                attachmentUploadRecord.uploadSessionUrl = nil

                try await db.awaitableWrite { tx in
                    try self.attachmentUploadStore.upsert(record: attachmentUploadRecord, tx: tx)
                }
                return try await upload(
                    attachment: attachment,
                    type: type,
                    logger: logger,
                    progress: progress
                )
            } else if case Upload.Error.missingFile = error {
                try await db.awaitableWrite { tx in
                    if
                        let attachmentRelFilePath = attachment.streamInfo?.localRelativeFilePath,
                        // If the missing file matches the url of the primary attachment file,
                        // mark the whole attachment as not having a file anymore.
                        localMetadata.fileUrl == AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: attachmentRelFilePath),
                        let attachment = attachmentStore.fetch(id: attachmentId, tx: tx)
                    {
                        logger.error("Primary attachment file missing!")
                        let params = Attachment.ConstructionParams.forOffloadingFiles(
                            attachment: attachment,
                            localRelativeFilePathThumbnail: nil
                        )
                        var newRecord = Attachment.Record(params: params)
                        newRecord.sqliteId = attachment.id
                        try newRecord.update(tx.database)
                    }
                    // Delete the upload record; whatever the state was we need to start over next time.
                    try self.attachmentUploadStore.removeRecord(
                        for: attachmentUploadRecord.attachmentId,
                        sourceType: attachmentUploadRecord.sourceType,
                        tx: tx
                    )
                }
                throw error
            } else {
                // Some other non-upload error was encountered - exit from the upload for now.
                // Network failures or task cancellation shouldn't bump the attempt count, but
                // any other error type should
                if error.isNetworkFailureOrTimeout {
                    logger.warn("Upload failed due to network error")
                } else if error is CancellationError {
                    logger.warn("Upload cancelled")
                } else {
                    attachmentUploadRecord.attempt += 1
                    try await db.awaitableWrite { tx in
                        try self.attachmentUploadStore.upsert(record: attachmentUploadRecord, tx: tx)
                    }
                    if let statusCode = error.httpStatusCode {
                        logger.warn("Unexpected upload error [status: \(statusCode)]")
                    } else {
                        logger.warn("Unexpected upload error")
                    }
                }
                throw error
            }
        }
    }

    // MARK: - Helpers

    private func fetchOrCreateAttachmentRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        db: any DB
    ) throws -> AttachmentUploadRecord {
        var attachmentUploadRecord: AttachmentUploadRecord
        if let record = try db.read(block: { tx in
            try self.attachmentUploadStore.fetchAttachmentUploadRecord(for: attachmentId, sourceType: sourceType, tx: tx)
        }) {
            attachmentUploadRecord = record
        } else {
            attachmentUploadRecord = AttachmentUploadRecord(sourceType: sourceType, attachmentId: attachmentId)
        }
        return attachmentUploadRecord
    }

    private enum MetadataResult {
        case new(Upload.LocalUploadMetadata)
        case existing(Upload.LocalUploadMetadata)
        case reuse(Upload.LocalUploadMetadata)
        case alreadyUploaded(Upload.ReusedUploadMetadata)
    }

    private func getOrFetchUploadMetadata(
        attachment: Attachment,
        type: UploadType,
        record: AttachmentUploadRecord,
        logger: PrefixedLogger
    ) async throws -> MetadataResult {

        switch type {
        case .mediaTier(_, isThumbnail: false):
            // We never allow uploads of data we don't have locally.
            guard let stream = attachment.asStream() else {
                logger.warn("Attachment is not uploadable.")
                throw OWSUnretryableError()
            }

            let now: Date = dateProvider()
            let messageQueueTime: TimeInterval = remoteConfigProvider.currentConfig().messageQueueTime

            if
                !Upload.disableTransitTierUploadReuse,
                // We have an existing upload
                let transitTierInfo = attachment.latestTransitTierInfo,
                // It uses the same primary key (it isn't a reupload with a rotated key)
                transitTierInfo.encryptionKey == attachment.encryptionKey,
                // We expect it isn't expired
                now - Date(millisecondsSince1970: transitTierInfo.uploadTimestamp) < messageQueueTime
            {
                // Reuse the existing transit tier upload without reuploading.
                return .alreadyUploaded(.init(
                    cdnKey: transitTierInfo.cdnKey,
                    cdnNumber: transitTierInfo.cdnNumber,
                    key: attachment.encryptionKey,
                    digest: stream.encryptedFileSha256Digest,
                    plaintextDataLength: stream.unencryptedByteCount,
                    // This is the length from the stream, not the transit tier,
                    // but the length is the same regardless of the key used.
                    // Note we use this when copying to media tier (the server requires
                    // the blob length on CDN) which is somewhat brittle if our local
                    // padding length doesn't match the padding length from the sender
                    // on CDN. This only becomes a problem if we ever change padding
                    // values or they drift between clients.
                    encryptedDataLength: stream.encryptedByteCount
                ))
            } else {
                let metadata = Upload.LocalUploadMetadata(
                    fileUrl: stream.fileURL,
                    key: attachment.encryptionKey,
                    digest: stream.info.digestSHA256Ciphertext,
                    encryptedDataLength: stream.info.encryptedByteCount,
                    plaintextDataLength: stream.info.unencryptedByteCount
                )
                return .reuse(metadata)
            }

        case .mediaTier(_, isThumbnail: true):
            // We never allow uploads of data we don't have locally.
            guard
                let stream = attachment.asStream(),
                let mediaName = attachment.mediaName
            else {
                logger.warn("Attachment is not uploadable.")
                throw OWSUnretryableError()
            }
            let fileUrl = fileSystem.temporaryFileUrl()

            guard let mrbk = db.read(block: { accountKeyStore.getMediaRootBackupKey(tx: $0) }) else {
                logger.warn("Media tier upload missing root key.")
                throw OWSUnretryableError()
            }

            let encryptionKey = try mrbk.mediaEncryptionMetadata(
                mediaName: AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName),
                type: .transitTierThumbnail
            )
            guard
                let thumbnailImage = await attachmentThumbnailService.thumbnailImage(
                    for: stream,
                    quality: .backupThumbnail
                )
            else {
                logger.warn("Unable to generate thumbnail; may not be visual media?")
                throw OWSUnretryableError()
            }

            let thumbnailData = try attachmentThumbnailService.backupThumbnailData(image: thumbnailImage)

            let (encryptedThumbnailData, encryptedThumbnailMetadata) = try Cryptography.encrypt(
                thumbnailData,
                encryptionKey: encryptionKey.encryptionKey,
                applyExtraPadding: true
            )

            // Write the thumbnail to the file.
            try encryptedThumbnailData.write(to: fileUrl)

            return .reuse(Upload.LocalUploadMetadata(
                fileUrl: fileUrl,
                key: encryptionKey.encryptionKey,
                digest: encryptedThumbnailMetadata.digest,
                encryptedDataLength: UInt32(encryptedThumbnailData.count),
                plaintextDataLength: UInt32(thumbnailData.count)
            ))

        case .transitTier:
            switch attachment.transitUploadStrategy(dateProvider: dateProvider) {
            case .cannotUpload:
                logger.warn("Attachment is not uploadable.")
                // Can't upload non-stream attachments; terminal failure.
                throw OWSUnretryableError()
            case .reuseExistingUpload(let metadata):
                logger.debug("Attachment previously uploaded.")
                return .alreadyUploaded(metadata)
            case .reuseStreamEncryption(let metadata):
                return .reuse(metadata)
            case .freshUpload(let stream):
                // Attempting to upload an existing attachment that's older than 3 days requires
                // the attachment to be re-encrypted before upload.
                // If this exists in the upload record from a prior attempt, use
                // that file if it still exists.
                if
                    let metadata = record.localMetadata,
                    // TODO:
                    // Currently, the file url is in a temp directory and doesn't
                    // persist across launches, so this will never be hit. The fix for this
                    // is to store the temporary file in a more persistent location, and
                    // register the file with the OrphanedAttachmentCleaner
                    OWSFileSystem.fileOrFolderExists(url: metadata.fileUrl)
                {
                    return .existing(metadata)
                } else {
                    let metadata = try buildMetadata(forUploading: stream)
                    return .new(metadata)
                }
            }
        }
    }

    private func fetchAttachment(
        attachmentId: Attachment.IDType,
        logger: PrefixedLogger,
        tx: DBReadTransaction
    ) throws -> Attachment {
        guard let attachment = attachmentStore.fetch(id: attachmentId, tx: tx) else {
            logger.warn("Missing attachment.")
            // Not finding a local attachment is a terminal failure.
            throw OWSUnretryableError()
        }
        return attachment
    }

    private func cleanup(record: AttachmentUploadRecord, logger: PrefixedLogger, tx: DBWriteTransaction) {
        do {
            try self.attachmentUploadStore.removeRecord(for: record.attachmentId, sourceType: record.sourceType, tx: tx)
        } catch {
            logger.warn("Failed to clean existing upload record for (\(record.attachmentId))")
        }
    }

    // Update all the necessary places once the upload succeeds
    private func updateTransitTier(
        attachmentStream: AttachmentStream,
        with result: Upload.AttachmentResult,
        logger: PrefixedLogger,
        tx: DBWriteTransaction
    ) throws {

        let transitTierInfo = Attachment.TransitTierInfo(
            cdnNumber: result.cdnNumber,
            cdnKey: result.cdnKey,
            uploadTimestamp: result.beginTimestamp,
            encryptionKey: result.localUploadMetadata.key,
            unencryptedByteCount: result.localUploadMetadata.plaintextDataLength,
            // ALWAYS use digest for integrity check for uploaded attachments;
            // we only allow sending using a digest integrity check not a plaintext hash
            // so prefer digest if we have both. If we don't, this attachment we just
            // uploaded to be able to send will fail to send.
            integrityCheck: .digestSHA256Ciphertext(result.localUploadMetadata.digest),
            // TODO: [Attachment Streaming] support incremental mac
            incrementalMacInfo: nil,
            lastDownloadAttemptTimestamp: nil
        )

        try self.attachmentUploadStore.markUploadedToTransitTier(
            attachmentStream: attachmentStream,
            info: transitTierInfo,
            tx: tx
        )

        do {
            try self.attachmentStore.enumerateAllReferences(
                toAttachmentId: attachmentStream.attachment.id,
                tx: tx
            ) { attachmentReference, _ in
                switch attachmentReference.owner {
                case .message(let messageSource):
                    guard
                        let interaction = self.interactionStore.fetchInteraction(
                            rowId: messageSource.messageRowId,
                            tx: tx
                        )
                    else {
                        logger.warn("Missing interaction.")
                        return
                    }
                    self.db.touch(interaction: interaction, shouldReindex: false, tx: tx)
                case .storyMessage(let storyMessageSource):
                    guard
                        let storyMessage = self.storyStore.fetchStoryMessage(
                            rowId: storyMessageSource.storyMsessageRowId,
                            tx: tx
                        )
                    else {
                        logger.warn("Missing story message.")
                        return
                    }
                    self.db.touch(storyMessage: storyMessage, tx: tx)
                case .thread:
                    break
                }
            }
        } catch {
            Logger.error("Failed to enumerate references: \(error)")
        }
    }

    public func copyToMediaTier(
        backupKey: MediaRootBackupKey,
        auth: BackupServiceAuth,
        mediaName: String,
        uploadEra: String,
        result: Upload.AttachmentResult,
        logger: PrefixedLogger
    ) async throws -> UInt32 {
        let mediaEncryptionMetadata = try backupKey.mediaEncryptionMetadata(
            mediaName: mediaName,
            type: .outerLayerFullsizeOrThumbnail
        )

        return try await backupRequestManager.copyToMediaTier(
            item: .init(
                sourceAttachment: .init(
                    cdn: result.cdnNumber,
                    key: result.cdnKey
                ),
                objectLength: result.localUploadMetadata.encryptedDataLength,
                mediaId: mediaEncryptionMetadata.mediaId,
                hmacKey: mediaEncryptionMetadata.hmacKey,
                aesKey: mediaEncryptionMetadata.aesKey
            ),
            auth: auth
        )
    }

    func buildMetadata(forUploading attachmentStream: AttachmentStream) throws -> Upload.LocalUploadMetadata {
        // First we need to decrypt, so we can re-encrypt for upload.
        let tmpDecryptedFile = fileSystem.temporaryFileUrl()
        let decryptionMedatata = DecryptionMetadata(
            key: attachmentStream.attachment.encryptionKey,
            // No need to validate for an already-validated stream
            integrityCheck: .sha256ContentHash(attachmentStream.sha256ContentHash),
            length: Int(clamping: attachmentStream.info.encryptedByteCount),
            plaintextLength: Int(clamping: attachmentStream.info.unencryptedByteCount)
        )
        try attachmentEncrypter.decryptAttachment(at: attachmentStream.fileURL, metadata: decryptionMedatata, output: tmpDecryptedFile)

        // Now re-encrypt with a fresh set of keys.
        // We use a tmp file on purpose; we already have the source file for the attachment
        // and don't need to keep around this copy encrypted with different keys; its useful
        // for upload only and can cleaned up by the OS after.
        let tmpReencryptedFile = fileSystem.temporaryFileUrl()
        let reencryptedMetadata = try attachmentEncrypter.encryptAttachment(at: tmpDecryptedFile, output: tmpReencryptedFile)

        // we upload the re-encrypted file.
        return try .validateAndBuild(fileUrl: tmpReencryptedFile, metadata: reencryptedMetadata)
    }

    private nonisolated func updateProgress(id: Attachment.IDType, progress: Double) {
        NotificationCenter.default.postOnMainThread(
            name: Upload.Constants.attachmentUploadProgressNotification,
            object: nil,
            userInfo: [
                Upload.Constants.uploadProgressKey: progress,
                Upload.Constants.uploadAttachmentIDKey: id
            ]
        )
    }
}

extension Upload.Result where Metadata: AttachmentUploadMetadata {

    var asAttachmentResult: Upload.AttachmentResult {
        return Upload.AttachmentResult(
            cdnKey: cdnKey,
            cdnNumber: cdnNumber,
            localUploadMetadata: localUploadMetadata,
            beginTimestamp: beginTimestamp,
            finishTimestamp: finishTimestamp
        )
    }
}

extension Upload {
    public static var disableTransitTierUploadReuse: Bool {
        get { DebugFlags.internalSettings && UserDefaults.standard.bool(forKey: "disableTransitTierUploadReuse") }
        set {
            guard DebugFlags.internalSettings else { return }
            UserDefaults.standard.set(newValue, forKey: "disableTransitTierUploadReuse")
        }
    }
}
