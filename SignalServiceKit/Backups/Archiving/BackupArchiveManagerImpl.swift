//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
import GRDB

public enum BackupValidationError: Error {
    case unknownFields([String])
    case validationFailed(message: String, unknownFields: [String])
    case ioError(String)
    case unknownError
}

public enum BackupImportError: Error {
    case unsupportedVersion
}

public class BackupArchiveManagerImpl: BackupArchiveManager {
    public enum Constants {
        fileprivate static let keyValueStoreCollectionName = "MessageBackupManager"
        fileprivate static let keyValueStoreRestoreStateKey = "keyValueStoreRestoreStateKey"
        fileprivate static let keyValueStoreNeedForwardSecrecyTokenFetchKey = "keyValueStoreNeedForwardSecrecyTokenFetchKey"

        public static let supportedBackupVersion: UInt64 = 1

        /// The ratio of frames processed for which to sample memory.
        fileprivate static let memorySamplerFrameRatio: Float = BuildFlags.Backups.detailedBenchLogging ? 0.001 : 0
    }

    private class NotImplementedError: Error {}
    private class BackupError: Error {}
    private typealias LoggableErrorAndProto = BackupArchive.LoggableErrorAndProto

    private let accountDataArchiver: BackupArchiveAccountDataArchiver
    private let adHocCallArchiver: BackupArchiveAdHocCallArchiver
    private let appVersion: AppVersion
    private let attachmentDownloadManager: AttachmentDownloadManager
    private let attachmentUploadManager: AttachmentUploadManager
    private let avatarFetcher: BackupArchiveAvatarFetcher
    private let backupArchiveErrorPresenter: BackupArchiveErrorPresenter
    private let backupAttachmentCoordinator: BackupAttachmentCoordinator
    private let backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore
    private let backupNonceMetadataStore: BackupNonceMetadataStore
    private let backupRequestManager: BackupRequestManager
    private let backupSettingsStore: BackupSettingsStore
    private let backupStickerPackDownloadStore: BackupStickerPackDownloadStore
    private let callLinkRecipientArchiver: BackupArchiveCallLinkRecipientArchiver
    private let chatArchiver: BackupArchiveChatArchiver
    private let chatItemArchiver: BackupArchiveChatItemArchiver
    private let contactRecipientArchiver: BackupArchiveContactRecipientArchiver
    private let databaseChangeObserver: DatabaseChangeObserver
    private let dateProvider: DateProvider
    private let dateProviderMonotonic: DateProviderMonotonic
    private let db: any DB
    private let disappearingMessagesJob: OWSDisappearingMessagesJob
    private let distributionListRecipientArchiver: BackupArchiveDistributionListRecipientArchiver
    private let encryptedStreamProvider: BackupArchiveEncryptedProtoStreamProvider
    private let fullTextSearchIndexer: BackupArchiveFullTextSearchIndexer
    private let groupRecipientArchiver: BackupArchiveGroupRecipientArchiver
    private let incrementalTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator
    private let kvStore: KeyValueStore
    private let libsignalNet: LibSignalClient.Net
    private let localStorage: AccountKeyStore
    private let localRecipientArchiver: BackupArchiveLocalRecipientArchiver
    private let logger: PrefixedLogger
    private let messagePipelineSupervisor: MessagePipelineSupervisor
    private let oversizeTextArchiver: BackupArchiveInlinedOversizeTextArchiver
    private let plaintextStreamProvider: BackupArchivePlaintextProtoStreamProvider
    private let postFrameRestoreActionManager: BackupArchivePostFrameRestoreActionManager
    private let releaseNotesRecipientArchiver: BackupArchiveReleaseNotesRecipientArchiver
    private let remoteConfigManager: RemoteConfigManager
    private let stickerPackArchiver: BackupArchiveStickerPackArchiver
    private let tsAccountManager: TSAccountManager

    init(
        accountDataArchiver: BackupArchiveAccountDataArchiver,
        adHocCallArchiver: BackupArchiveAdHocCallArchiver,
        appVersion: AppVersion,
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentUploadManager: AttachmentUploadManager,
        avatarFetcher: BackupArchiveAvatarFetcher,
        backupArchiveErrorPresenter: BackupArchiveErrorPresenter,
        backupAttachmentCoordinator: BackupAttachmentCoordinator,
        backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
        backupNonceMetadataStore: BackupNonceMetadataStore,
        backupRequestManager: BackupRequestManager,
        backupSettingsStore: BackupSettingsStore,
        backupStickerPackDownloadStore: BackupStickerPackDownloadStore,
        callLinkRecipientArchiver: BackupArchiveCallLinkRecipientArchiver,
        chatArchiver: BackupArchiveChatArchiver,
        chatItemArchiver: BackupArchiveChatItemArchiver,
        contactRecipientArchiver: BackupArchiveContactRecipientArchiver,
        databaseChangeObserver: DatabaseChangeObserver,
        dateProvider: @escaping DateProvider,
        dateProviderMonotonic: @escaping DateProviderMonotonic,
        db: any DB,
        disappearingMessagesJob: OWSDisappearingMessagesJob,
        distributionListRecipientArchiver: BackupArchiveDistributionListRecipientArchiver,
        encryptedStreamProvider: BackupArchiveEncryptedProtoStreamProvider,
        fullTextSearchIndexer: BackupArchiveFullTextSearchIndexer,
        groupRecipientArchiver: BackupArchiveGroupRecipientArchiver,
        incrementalTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator,
        libsignalNet: LibSignalClient.Net,
        localStorage: AccountKeyStore,
        localRecipientArchiver: BackupArchiveLocalRecipientArchiver,
        messagePipelineSupervisor: MessagePipelineSupervisor,
        oversizeTextArchiver: BackupArchiveInlinedOversizeTextArchiver,
        plaintextStreamProvider: BackupArchivePlaintextProtoStreamProvider,
        postFrameRestoreActionManager: BackupArchivePostFrameRestoreActionManager,
        releaseNotesRecipientArchiver: BackupArchiveReleaseNotesRecipientArchiver,
        remoteConfigManager: RemoteConfigManager,
        stickerPackArchiver: BackupArchiveStickerPackArchiver,
        tsAccountManager: TSAccountManager,
    ) {
        self.accountDataArchiver = accountDataArchiver
        self.appVersion = appVersion
        self.attachmentDownloadManager = attachmentDownloadManager
        self.attachmentUploadManager = attachmentUploadManager
        self.avatarFetcher = avatarFetcher
        self.backupArchiveErrorPresenter = backupArchiveErrorPresenter
        self.backupAttachmentCoordinator = backupAttachmentCoordinator
        self.backupAttachmentUploadEraStore = backupAttachmentUploadEraStore
        self.backupNonceMetadataStore = backupNonceMetadataStore
        self.backupRequestManager = backupRequestManager
        self.backupSettingsStore = backupSettingsStore
        self.backupStickerPackDownloadStore = backupStickerPackDownloadStore
        self.callLinkRecipientArchiver = callLinkRecipientArchiver
        self.chatArchiver = chatArchiver
        self.chatItemArchiver = chatItemArchiver
        self.contactRecipientArchiver = contactRecipientArchiver
        self.databaseChangeObserver = databaseChangeObserver
        self.dateProvider = dateProvider
        self.dateProviderMonotonic = dateProviderMonotonic
        self.db = db
        self.disappearingMessagesJob = disappearingMessagesJob
        self.distributionListRecipientArchiver = distributionListRecipientArchiver
        self.encryptedStreamProvider = encryptedStreamProvider
        self.fullTextSearchIndexer = fullTextSearchIndexer
        self.groupRecipientArchiver = groupRecipientArchiver
        self.incrementalTSAttachmentMigrator = incrementalTSAttachmentMigrator
        self.kvStore = KeyValueStore(collection: Constants.keyValueStoreCollectionName)
        self.libsignalNet = libsignalNet
        self.localStorage = localStorage
        self.localRecipientArchiver = localRecipientArchiver
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.messagePipelineSupervisor = messagePipelineSupervisor
        self.oversizeTextArchiver = oversizeTextArchiver
        self.plaintextStreamProvider = plaintextStreamProvider
        self.postFrameRestoreActionManager = postFrameRestoreActionManager
        self.releaseNotesRecipientArchiver = releaseNotesRecipientArchiver
        self.remoteConfigManager = remoteConfigManager
        self.stickerPackArchiver = stickerPackArchiver
        self.adHocCallArchiver = adHocCallArchiver
        self.tsAccountManager = tsAccountManager
    }

    // MARK: - Remote backups

    public func downloadEncryptedBackup(
        backupKey: MessageRootBackupKey,
        backupAuth: BackupServiceAuth,
        progress: OWSProgressSink?
    ) async throws -> URL {
        let metadata = try await backupRequestManager.fetchBackupRequestMetadata(auth: backupAuth)
        let tmpFileUrl = try await attachmentDownloadManager.downloadBackup(
            metadata: metadata,
            progress: progress
        ).awaitable()

        // Once protos calm down, this can be enabled to warn/error on failed validation
        // try await validateBackup(localIdentifiers: localIdentifiers, fileUrl: tmpFileUrl)

        return tmpFileUrl
    }

    public func backupCdnInfo(
        backupKey: MessageRootBackupKey,
        backupAuth: BackupServiceAuth,
    ) async throws -> BackupCdnInfo {
        let metadata = try await backupRequestManager.fetchBackupRequestMetadata(auth: backupAuth)
        return try await attachmentDownloadManager.backupCdnInfo(metadata: metadata)
    }

    public func uploadEncryptedBackup(
        backupKey: MessageRootBackupKey,
        metadata: Upload.EncryptedBackupUploadMetadata,
        auth: ChatServiceAuth,
        progress: OWSProgressSink?
    ) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata> {
        guard db.read(block: { tsAccountManager.registrationState(tx: $0).isPrimaryDevice }) == true else {
            throw OWSAssertionError("Backing up not on a registered primary!")
        }

        let backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
            for: backupKey,
            localAci: backupKey.aci,
            auth: auth
        )
        let form: Upload.Form
        do {
            form = try await backupRequestManager.fetchBackupUploadForm(
                backupByteLength: metadata.encryptedDataLength,
                auth: backupAuth
            )
        } catch let error {
            switch (error as? BackupArchive.Response.BackupUploadFormError) {
            case .tooLarge:
                logger.warn("Backup too large! \(metadata.encryptedDataLength)")
            default:
                break
            }
            throw error
        }
        let result = try await attachmentUploadManager.uploadBackup(
            localUploadMetadata: metadata,
            form: form,
            progress: progress
        )

        await db.awaitableWrite { tx in
            let backupFileSizeBytes: UInt64
            let backupMediaSizeBytes: UInt64
            switch backupSettingsStore.backupPlan(tx: tx) {
            case .paid, .paidExpiringSoon, .paidAsTester:
                backupFileSizeBytes = UInt64(metadata.encryptedDataLength)
                backupMediaSizeBytes = metadata.attachmentByteSize
            case .free:
                backupFileSizeBytes = UInt64(metadata.encryptedDataLength)
                backupMediaSizeBytes = 0
            case .disabled, .disabling:
                owsFailDebug("Shouldn't generate backup when backups is disabled")
                backupFileSizeBytes = 0
                backupMediaSizeBytes = 0
            }

            backupSettingsStore.setLastBackupDetails(
                date: metadata.exportStartTimestamp,
                backupFileSizeBytes: backupFileSizeBytes,
                backupMediaSizeBytes: backupMediaSizeBytes,
                tx: tx,
            )

            if let nonceMetadata = metadata.nonceMetadata {
                backupNonceMetadataStore.setLastForwardSecrecyToken(
                    nonceMetadata.forwardSecrecyToken,
                    for: backupKey,
                    tx: tx
                )
                backupNonceMetadataStore.setNextSecretMetadata(
                    nonceMetadata.nextSecretMetadata,
                    for: backupKey,
                    tx: tx
                )
            }
        }

        return result
    }

    // MARK: - Export

    public func exportEncryptedBackup(
        localIdentifiers: LocalIdentifiers,
        backupPurpose: BackupExportPurpose,
        progress progressSink: OWSProgressSink?
    ) async throws -> Upload.EncryptedBackupUploadMetadata {
        let attachmentByteCounter = BackupArchiveAttachmentByteCounter()
        let startTimestamp = dateProvider()

        // Filter included content according to the purpose of this backup.
        let includedContentFilter = BackupArchive.IncludedContentFilter(
            backupPurpose: backupPurpose.libsignalPurpose
        )

        switch backupPurpose {
        case .remoteExport(let key, let chatAuth):
            // If an SVRB restore has been scheduled, do this restore before continuing
            // with the remote backup.  This ensures the local and remote state are
            // consistent and avoids the possibility of a backup being created that
            // can't be recovered using the material in SVRB.
            if db.read(block: { needsRestoreFromSVRBBeforeRemoteExport(tx: $0) }) {
                do {
                    try await fetchRemoteSVRBForwardSecrecyToken(key: key, auth: chatAuth)
                } catch SVRBError.unrecoverable {
                    // Not found, so consider a success and fallthrough
                    Logger.info("SVRB not found, skipping restore.")
                } catch {
                    Logger.warn("Encountered error restoring SVRB: \(error)")
                    throw error
                }

                await db.awaitableWrite {
                    kvStore.setBool(
                        false,
                        key: Constants.keyValueStoreNeedForwardSecrecyTokenFetchKey,
                        transaction: $0
                    )
                }
            }
        case .linkNsync:
            break
        }

        let encryptionMetadata = try await backupPurpose.deriveEncryptionMetadataWithSVRBIfNeeded(
            backupRequestManager: backupRequestManager,
            db: db,
            libsignalNet: libsignalNet,
            nonceStore: backupNonceMetadataStore
        )

        let metadata = try await _exportBackup(
            localIdentifiers: localIdentifiers,
            backupPurpose: backupPurpose.libsignalPurpose,
            startTimestamp: startTimestamp,
            includedContentFilter: includedContentFilter,
            progressSink: progressSink,
            attachmentByteCounter: attachmentByteCounter,
            benchTitle: "Export encrypted Backup",
            openOutputStreamBlock: { exportProgress, tx in
                return encryptedStreamProvider.openEncryptedOutputFileStream(
                    startTimestamp: startTimestamp,
                    encryptionMetadata: encryptionMetadata,
                    exportProgress: exportProgress,
                    attachmentByteCounter: attachmentByteCounter,
                    tx: tx
                )
            }
        )

        try await self.validateEncryptedBackup(
            fileUrl: metadata.fileUrl,
            backupEncryptionKey: encryptionMetadata.encryptionKey,
            backupPurpose: backupPurpose.libsignalPurpose
        )

        return metadata
    }

#if TESTABLE_BUILD
    public func exportPlaintextBackupForTests(
        localIdentifiers: LocalIdentifiers,
    ) async throws -> URL {
        let attachmentByteCounter = BackupArchiveAttachmentByteCounter()
        let startTimestamp = dateProvider()

        // For the integration tests, don't filter out any content. The premise
        // of the tests is to verify that round-tripping a Backup file is
        // idempotent. The device transfer purpose includes everything.
        let includedContentFilter = BackupArchive.IncludedContentFilter(
            backupPurpose: .deviceTransfer
        )

        return try await _exportBackup(
            localIdentifiers: localIdentifiers,
            backupPurpose: .remoteBackup,
            startTimestamp: startTimestamp,
            includedContentFilter: includedContentFilter,
            progressSink: nil,
            attachmentByteCounter: attachmentByteCounter,
            benchTitle: "Export plaintext Backup",
            openOutputStreamBlock: { exportProgress, tx in
                return plaintextStreamProvider.openPlaintextOutputFileStream(
                    exportProgress: exportProgress
                )
            }
        )
    }
#endif

    private func _exportBackup<OutputStreamMetadata>(
        localIdentifiers: LocalIdentifiers,
        backupPurpose: MessageBackupPurpose,
        startTimestamp: Date,
        includedContentFilter: BackupArchive.IncludedContentFilter,
        progressSink: OWSProgressSink?,
        attachmentByteCounter: BackupArchiveAttachmentByteCounter,
        benchTitle: String,
        openOutputStreamBlock: (
            BackupArchiveExportProgress?,
            DBReadTransaction
        ) -> BackupArchive.ProtoStream.OpenOutputStreamResult<OutputStreamMetadata>
    ) async throws -> OutputStreamMetadata {
        let migrateAttachmentsProgressSink: OWSProgressSink?
        let prepareOversizeTextAttachmentsProgressSink: OWSProgressSink?
        let exportProgress: BackupArchiveExportProgress?
        if let progressSink {
            migrateAttachmentsProgressSink = await progressSink.addChild(
                withLabel: "Export Backup: Migrate Attachments",
                unitCount: 5
            )
            prepareOversizeTextAttachmentsProgressSink = await progressSink.addChild(
                withLabel: "Export Backup: Oversize Text Attachments",
                unitCount: 5
            )
            exportProgress = try await .prepare(
                sink: await progressSink.addChild(
                    withLabel: "Export Backup: Export Frames",
                    unitCount: 90
                ),
                db: db
            )
        } else {
            migrateAttachmentsProgressSink = nil
            prepareOversizeTextAttachmentsProgressSink = nil
            exportProgress = nil
        }

        await migrateAttachmentsBeforeBackup(progress: migrateAttachmentsProgressSink)

        try await oversizeTextArchiver.populateTableIncrementally(progress: prepareOversizeTextAttachmentsProgressSink)

        // Before we export, we need to make sure we have an MRBK – the export
        // will refetch this, and throw if it's missing.
        _ = await db.awaitableWrite { tx in
            localStorage.getOrGenerateMediaRootBackupKey(tx: tx)
        }

        return try db.read { tx in
            let outputStreamMetadata = try BenchMemory(
                title: benchTitle,
                memorySamplerRatio: Constants.memorySamplerFrameRatio,
                logInProduction: true
            ) { memorySampler -> OutputStreamMetadata in
                let outputStream: BackupArchiveProtoOutputStream
                let outputStreamMetadataProvider: () throws -> OutputStreamMetadata
                switch openOutputStreamBlock(exportProgress, tx) {
                case .success(let _outputStream, let _outputStreamMetadataProvider):
                    outputStream = _outputStream
                    outputStreamMetadataProvider = _outputStreamMetadataProvider
                case .unableToOpenFileStream:
                    throw OWSAssertionError("Unable to open output file stream!")
                }

                try self._exportBackup(
                    outputStream: outputStream,
                    localIdentifiers: localIdentifiers,
                    backupPurpose: backupPurpose,
                    startTimestamp: startTimestamp,
                    attachmentByteCounter: attachmentByteCounter,
                    includedContentFilter: includedContentFilter,
                    currentAppVersion: appVersion.currentAppVersion,
                    firstAppVersion: appVersion.firstBackupAppVersion ?? appVersion.firstAppVersion,
                    memorySampler: memorySampler,
                    tx: tx
                )

                return try outputStreamMetadataProvider()
            }

            return outputStreamMetadata
        }
    }

    private func _exportBackup(
        outputStream stream: BackupArchiveProtoOutputStream,
        localIdentifiers: LocalIdentifiers,
        backupPurpose: MessageBackupPurpose,
        startTimestamp: Date,
        attachmentByteCounter: BackupArchiveAttachmentByteCounter,
        includedContentFilter: BackupArchive.IncludedContentFilter,
        currentAppVersion: String,
        firstAppVersion: String,
        memorySampler: MemorySampler,
        tx: DBReadTransaction
    ) throws {
        let bencher = BackupArchive.ArchiveBencher(
            dateProviderMonotonic: dateProviderMonotonic,
            memorySampler: memorySampler
        )

        let startTimestampMs = startTimestamp.ows_millisecondsSince1970
        let backupVersion = Constants.supportedBackupVersion
        let purposeString: String = switch backupPurpose {
        case .deviceTransfer: "LinkNSync"
        case .remoteBackup: "RemoteBackup"
        }

        // We already have a passed-in MRBK, but that came from outside this read tx so
        // refetch it to make sure. If it changed to a new value, use the new value, thats fine
        // (though unexpected). If it changed to _nil_ (should never happen on primaries), exit.
        guard let mediaRootBackupKey = localStorage.getMediaRootBackupKey(tx: tx) else {
            throw OWSAssertionError("MRBK unset as backup being created!")
        }

        var errors = [LoggableErrorAndProto]()
        let result = Result<Void, Error>(catching: {
            logger.info("Exporting for \(purposeString) with version \(backupVersion), timestamp \(startTimestampMs)")

            try autoreleasepool {
                try writeHeader(
                    stream: stream,
                    backupVersion: backupVersion,
                    backupTimeMs: startTimestampMs,
                    currentAppVersion: currentAppVersion,
                    firstAppVersion: firstAppVersion,
                    mediaRootBackupKey: mediaRootBackupKey,
                    tx: tx
                )
            }
            try Task.checkCancellation()

            let currentBackupAttachmentUploadEra = backupAttachmentUploadEraStore.currentUploadEra(tx: tx)

            let customChatColorContext = BackupArchive.CustomChatColorArchivingContext(
                bencher: bencher,
                attachmentByteCounter: attachmentByteCounter,
                currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
                includedContentFilter: includedContentFilter,
                startTimestampMs: startTimestampMs,
                tx: tx
            )
            try autoreleasepool {
                let accountDataResult = accountDataArchiver.archiveAccountData(
                    stream: stream,
                    context: customChatColorContext
                )
                switch accountDataResult {
                case .success:
                    break
                case .failure(let error):
                    errors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true))
                    throw OWSAssertionError("Failed to archive account data")
                }
            }
            try Task.checkCancellation()

            let localRecipientResult = localRecipientArchiver.archiveLocalRecipient(
                stream: stream,
                bencher: bencher,
                localIdentifiers: localIdentifiers,
                tx: tx
            )

            try Task.checkCancellation()

            let localRecipientId: BackupArchive.RecipientId
            switch localRecipientResult {
            case .success(let success):
                localRecipientId = success
            case .failure(let error):
                errors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true))
                throw OWSAssertionError("Failed to archive local recipient!")
            }

            guard let localSignalRecipientRowId = localRecipientArchiver.fetchLocalRecipientRowId(
                localIdentifiers: localIdentifiers,
                tx: tx
            ) else {
                throw OWSAssertionError("Failed to fetch local recipient row ID!")
            }

            let recipientArchivingContext = BackupArchive.RecipientArchivingContext(
                bencher: bencher,
                attachmentByteCounter: attachmentByteCounter,
                currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
                includedContentFilter: includedContentFilter,
                localIdentifiers: localIdentifiers,
                localRecipientId: localRecipientId,
                localSignalRecipientRowId: localSignalRecipientRowId,
                startTimestampMs: startTimestampMs,
                tx: tx
            )

            try autoreleasepool {
                switch releaseNotesRecipientArchiver.archiveReleaseNotesRecipient(
                    stream: stream,
                    context: recipientArchivingContext
                ) {
                case .success:
                    break
                case .failure(let error):
                    errors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true))
                    throw OWSAssertionError("Failed to archive release notes channel!")
                }
            }
            try Task.checkCancellation()

            switch try contactRecipientArchiver.archiveAllContactRecipients(
                stream: stream,
                context: recipientArchivingContext
            ) {
            case .success:
                break
            case .partialSuccess(let partialFailures):
                errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false) })
            case .completeFailure(let error):
                errors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true))
                throw BackupError()
            }

            switch try groupRecipientArchiver.archiveAllGroupRecipients(
                stream: stream,
                context: recipientArchivingContext
            ) {
            case .success:
                break
            case .partialSuccess(let partialFailures):
                errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false) })
            case .completeFailure(let error):
                errors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true))
                throw BackupError()
            }

            switch try distributionListRecipientArchiver.archiveAllDistributionListRecipients(
                stream: stream,
                context: recipientArchivingContext
            ) {
            case .success:
                break
            case .partialSuccess(let partialFailures):
                errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false) })
            case .completeFailure(let error):
                errors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true))
                throw BackupError()
            }

            switch try callLinkRecipientArchiver.archiveAllCallLinkRecipients(
                stream: stream,
                context: recipientArchivingContext
            ) {
            case .success:
                break
            case .partialSuccess(let partialFailures):
                errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false) })
            case .completeFailure(let error):
                errors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true))
                throw BackupError()
            }

            let chatArchivingContext = BackupArchive.ChatArchivingContext(
                bencher: bencher,
                attachmentByteCounter: attachmentByteCounter,
                currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
                customChatColorContext: customChatColorContext,
                includedContentFilter: includedContentFilter,
                recipientContext: recipientArchivingContext,
                startTimestampMs: startTimestampMs,
                tx: tx
            )
            let chatArchiveResult = try chatArchiver.archiveChats(
                stream: stream,
                context: chatArchivingContext
            )
            switch chatArchiveResult {
            case .success:
                break
            case .partialSuccess(let partialFailures):
                errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false) })
            case .completeFailure(let error):
                errors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true))
                throw BackupError()
            }

            let chatItemArchiveResult = try chatItemArchiver.archiveInteractions(
                stream: stream,
                context: chatArchivingContext
            )
            switch chatItemArchiveResult {
            case .success:
                break
            case .partialSuccess(let partialFailures):
                errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false) })
            case .completeFailure(let error):
                errors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true))
                throw BackupError()
            }

            let archivingContext = BackupArchive.ArchivingContext(
                bencher: bencher,
                attachmentByteCounter: attachmentByteCounter,
                currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
                includedContentFilter: includedContentFilter,
                startTimestampMs: startTimestampMs,
                tx: tx
            )
            let stickerPackArchiveResult = try stickerPackArchiver.archiveStickerPacks(
                stream: stream,
                context: archivingContext
            )
            switch stickerPackArchiveResult {
            case .success:
                break
            case .partialSuccess(let partialFailures):
                errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false) })
            case .completeFailure(let error):
                errors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true))
                throw BackupError()
            }

            let adHocCallArchiveResult = try adHocCallArchiver.archiveAdHocCalls(
                stream: stream,
                context: chatArchivingContext
            )
            switch adHocCallArchiveResult {
            case .success:
                break
            case .partialSuccess(let partialFailures):
                errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false) })
            case .completeFailure(let error):
                errors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true))
                throw BackupError()
            }

            try stream.closeFileStream()

            logger.info("Finished exporting backup")
            bencher.logResults()
        })
        processErrors(errors: errors, didFail: result.isSuccess.negated)
        return try result.get()
    }

    private func writeHeader(
        stream: BackupArchiveProtoOutputStream,
        backupVersion: UInt64,
        backupTimeMs: UInt64,
        currentAppVersion: String,
        firstAppVersion: String,
        mediaRootBackupKey: MediaRootBackupKey,
        tx: DBReadTransaction
    ) throws {
        var backupInfo = BackupProto_BackupInfo()
        backupInfo.version = backupVersion
        backupInfo.backupTimeMs = backupTimeMs
        backupInfo.currentAppVersion = currentAppVersion
        backupInfo.firstAppVersion = firstAppVersion

        backupInfo.mediaRootBackupKey = mediaRootBackupKey.serialize()

        switch stream.writeHeader(backupInfo) {
        case .success:
            break
        case .fileIOError(let error), .protoSerializationError(let error):
            throw error
        }
    }

    // MARK: - Import

    public func backupRestoreState(tx: DBReadTransaction) -> BackupRestoreState {
        let raw = kvStore.getInt(
            Constants.keyValueStoreRestoreStateKey,
            defaultValue: 0,
            transaction: tx
        )
        guard let value = BackupRestoreState(rawValue: raw) else {
            owsFailDebug("Unrecognized state!")
            return .none
        }
        return value
    }

    public func importEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        source: BackupImportSource,
        progress progressSink: OWSProgressSink?
    ) async throws {

        let backupEncryptionKey = try await source.deriveBackupEncryptionKeyWithSVRBIfNeeded(
            backupRequestManager: backupRequestManager,
            db: db,
            libsignalNet: libsignalNet,
            nonceStore: backupNonceMetadataStore
        )

        try await _importBackup(
            fileUrl: fileUrl,
            localIdentifiers: localIdentifiers,
            isPrimaryDevice: isPrimaryDevice,
            progressSink: progressSink,
            benchTitle: "Import encrypted Backup",
            backupPurpose: source.libsignalPurpose,
            openInputStreamBlock: { fileUrl, frameRestoreProgress, tx in
                return encryptedStreamProvider.openEncryptedInputFileStream(
                    fileUrl: fileUrl,
                    source: source,
                    backupEncryptionKey: backupEncryptionKey,
                    frameRestoreProgress: frameRestoreProgress,
                    tx: tx
                )
            }
        )
    }

#if TESTABLE_BUILD
    public func importPlaintextBackupForTests(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
    ) async throws {
        try await _importBackup(
            fileUrl: fileUrl,
            localIdentifiers: localIdentifiers,
            isPrimaryDevice: true,
            progressSink: nil,
            benchTitle: "Import plaintext Backup",
            backupPurpose: .remoteBackup,
            openInputStreamBlock: { fileUrl, frameRestoreProgress, _ in
                return plaintextStreamProvider.openPlaintextInputFileStream(
                    fileUrl: fileUrl,
                    frameRestoreProgress: frameRestoreProgress
                )
            }
        )
    }
#endif

    /// Everything in this method MUST be idempotent, as partial progress can be made
    /// before app termination, which will result in this getting called again.
    public func finalizeBackupImport(progress: OWSProgressSink?) async throws {
        let oversizedTextProgress: OWSProgressSink?
        if let progress {
            oversizedTextProgress = await progress.addChild(
                withLabel: "Import Backup: Process Oversized Text Attachments",
                unitCount: 5
            )
        } else {
            oversizedTextProgress = nil
        }

        try await oversizeTextArchiver.finishRestoringOversizedTextAttachments(
            progress: oversizedTextProgress
        )

        await db.awaitableWrite { tx in
            kvStore.setInt(
                BackupRestoreState.finalized.rawValue,
                key: Constants.keyValueStoreRestoreStateKey,
                transaction: tx
            )
        }
    }

    private func _importBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        progressSink: OWSProgressSink?,
        benchTitle: String,
        backupPurpose: MessageBackupPurpose,
        openInputStreamBlock: (
            URL,
            BackupArchiveImportFramesProgress?,
            DBReadTransaction
        ) -> BackupArchive.ProtoStream.OpenInputStreamResult
    ) async throws {
        let migrateAttachmentsProgressSink: OWSProgressSink?
        let frameRestoreProgress: BackupArchiveImportFramesProgress?
        let recreateIndexesProgress: BackupArchiveImportRecreateIndexesProgress?
        let finalizeProgress: OWSProgressSink?
        if let progressSink {
            migrateAttachmentsProgressSink = await progressSink.addChild(
                withLabel: "Import Backup: Migrate Attachments",
                unitCount: 5
            )
            frameRestoreProgress = try await .prepare(
                sink: await progressSink.addChild(
                    withLabel: "Import Backup: Import Frames",
                    unitCount: 78
                ),
                fileUrl: fileUrl
            )
            recreateIndexesProgress = await .prepare(
                sink: await progressSink.addChild(
                    withLabel: "Import Backup: Recreate Indexes",
                    unitCount: 12
                )
            )
            finalizeProgress  = await progressSink.addChild(
                withLabel: "Import Backup: Finalize",
                unitCount: 5
            )
        } else {
            migrateAttachmentsProgressSink = nil
            frameRestoreProgress = nil
            recreateIndexesProgress = nil
            finalizeProgress = nil
        }

        await migrateAttachmentsBeforeBackup(progress: migrateAttachmentsProgressSink)

        let backupInfo = try await db.awaitableWriteWithRollbackIfThrows { tx in
            return try BenchMemory(
                title: benchTitle,
                memorySamplerRatio: Constants.memorySamplerFrameRatio,
                logInProduction: true
            ) { memorySampler -> BackupProto_BackupInfo in
                return try self.databaseChangeObserver.disable(tx: tx) { tx in
                    let inputStream: BackupArchiveProtoInputStream
                    switch openInputStreamBlock(fileUrl, frameRestoreProgress, tx) {
                    case .success(let protoStream, _):
                        inputStream = protoStream
                    case .fileNotFound:
                        throw OWSAssertionError("File not found!")
                    case .unableToOpenFileStream:
                        throw OWSAssertionError("Unable to open input stream!")
                    case .hmacValidationFailedOnEncryptedFile:
                        throw OWSAssertionError("HMAC validation failed!")
                    }

                    let inputFileSize = try OWSFileSystem.fileSize(of: fileUrl)

                    return try self._importBackup(
                        inputStream: inputStream,
                        inputFileSize: inputFileSize,
                        localIdentifiers: localIdentifiers,
                        isPrimaryDevice: isPrimaryDevice,
                        backupPurpose: backupPurpose,
                        recreateIndexesProgress: recreateIndexesProgress,
                        memorySampler: memorySampler,
                        tx: tx
                    )
                }
            }
        }

        appVersion.didRestoreFromBackup(
            backupCurrentAppVersion: backupInfo.currentAppVersion.nilIfEmpty,
            backupFirstAppVersion: backupInfo.firstAppVersion.nilIfEmpty
        )

        try await self.finalizeBackupImport(progress: finalizeProgress)
    }

    private func _importBackup(
        inputStream stream: BackupArchiveProtoInputStream,
        inputFileSize: UInt64,
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        backupPurpose: MessageBackupPurpose,
        recreateIndexesProgress: BackupArchiveImportRecreateIndexesProgress?,
        memorySampler: MemorySampler,
        tx: DBWriteTransaction
    ) throws -> BackupProto_BackupInfo {
        let bencher = BackupArchive.RestoreBencher(
            dateProviderMonotonic: dateProviderMonotonic,
            memorySampler: memorySampler
        )

        switch backupRestoreState(tx: tx) {
        case .none:
            break
        case .unfinalized, .finalized:
            throw OWSAssertionError("Restoring from backup twice!")
        }

        let startTimestampMs = dateProvider().ows_millisecondsSince1970
        let attachmentByteCounter = BackupArchiveAttachmentByteCounter()

        let currentRemoteConfig = remoteConfigManager.currentConfig()

        // Drops all indexes on the `TSInteraction` table before doing the
        // import, which dramatically speeds up the import. We'll then recreate
        // all these indexes in bulk afterwards.
        let interactionIndexes = try bencher.benchPreFrameRestoreAction(.DropInteractionIndexes) {
            try dropAllIndexes(
                forTable: InteractionRecord.databaseTableName,
                tx: tx
            )
        }

        var frameErrors = [LoggableErrorAndProto]()
        let result = Result<BackupProto_BackupInfo, Error>(catching: {
            var hasMoreFrames = false
            var framesRestored: UInt64 = 0

            let backupInfo: BackupProto_BackupInfo
            switch stream.readHeader() {
            case .success(let header, let moreBytesAvailable):
                backupInfo = header
                hasMoreFrames = moreBytesAvailable
                framesRestored += 1
            case .invalidByteLengthDelimiter:
                throw OWSAssertionError("invalid byte length delimiter on header")
            case .emptyFinalFrame:
                throw OWSAssertionError("invalid empty header frame")
            case .protoDeserializationError(let error):
                // Fail if we fail to deserialize the header.
                frameErrors.append(LoggableErrorAndProto(
                    error: BackupArchive.RestoreFrameError.restoreFrameError(
                        .invalidProtoData(.missingBackupInfoHeader),
                        BackupArchive.BackupInfoId()
                    ),
                    wasFrameDropped: true
                ))
                throw error
            }

            logger.info("Importing with version \(backupInfo.version), timestamp \(backupInfo.backupTimeMs)")

            guard backupInfo.version == Constants.supportedBackupVersion else {
                frameErrors.append(LoggableErrorAndProto(
                    error: BackupArchive.RestoreFrameError.restoreFrameError(
                        .invalidProtoData(.unsupportedBackupInfoVersion),
                        BackupArchive.BackupInfoId()
                    ),
                    wasFrameDropped: true,
                    protoFrame: backupInfo
                ))
                throw BackupImportError.unsupportedVersion
            }
            do {
                let mrbk = try BackupKey(contents: backupInfo.mediaRootBackupKey)
                localStorage.setMediaRootBackupKey(MediaRootBackupKey(backupKey: mrbk), tx: tx)
            } catch {
                frameErrors.append(LoggableErrorAndProto(
                    error: BackupArchive.RestoreFrameError.restoreFrameError(
                        .invalidProtoData(.invalidMediaRootBackupKey),
                        BackupArchive.BackupInfoId()
                    ),
                    wasFrameDropped: true,
                    protoFrame: backupInfo
                ))
                throw error
            }

            /// Wraps all the various "contexts" we pass to downstream archivers.
            struct Contexts {
                let accountData: BackupArchive.AccountDataRestoringContext
                let chat: BackupArchive.ChatRestoringContext
                var chatItem: BackupArchive.ChatItemRestoringContext
                let customChatColor: BackupArchive.CustomChatColorRestoringContext
                let recipient: BackupArchive.RecipientRestoringContext
                let stickerPack: BackupArchive.RestoringContext

                init(
                    localIdentifiers: LocalIdentifiers,
                    startTimestampMs: UInt64,
                    attachmentByteCounter: BackupArchiveAttachmentByteCounter,
                    isPrimaryDevice: Bool,
                    currentRemoteConfig: RemoteConfig,
                    backupPurpose: MessageBackupPurpose,
                    tx: DBWriteTransaction
                ) {
                    accountData = BackupArchive.AccountDataRestoringContext(
                        startTimestampMs: startTimestampMs,
                        attachmentByteCounter: attachmentByteCounter,
                        isPrimaryDevice: isPrimaryDevice,
                        currentRemoteConfig: currentRemoteConfig,
                        backupPurpose: backupPurpose,
                        tx: tx
                    )
                    customChatColor = BackupArchive.CustomChatColorRestoringContext(
                        startTimestampMs: startTimestampMs,
                        attachmentByteCounter: attachmentByteCounter,
                        isPrimaryDevice: isPrimaryDevice,
                        accountDataContext: accountData,
                        tx: tx
                    )
                    recipient = BackupArchive.RecipientRestoringContext(
                        localIdentifiers: localIdentifiers,
                        startTimestampMs: startTimestampMs,
                        attachmentByteCounter: attachmentByteCounter,
                        isPrimaryDevice: isPrimaryDevice,
                        tx: tx
                    )
                    chat = BackupArchive.ChatRestoringContext(
                        customChatColorContext: customChatColor,
                        recipientContext: recipient,
                        startTimestampMs: startTimestampMs,
                        attachmentByteCounter: attachmentByteCounter,
                        isPrimaryDevice: isPrimaryDevice,
                        tx: tx
                    )
                    chatItem = BackupArchive.ChatItemRestoringContext(
                        chatContext: chat,
                        recipientContext: recipient,
                        startTimestampMs: startTimestampMs,
                        attachmentByteCounter: attachmentByteCounter,
                        isPrimaryDevice: isPrimaryDevice,
                        tx: tx
                    )
                    stickerPack = BackupArchive.RestoringContext(
                        startTimestampMs: startTimestampMs,
                        attachmentByteCounter: attachmentByteCounter,
                        isPrimaryDevice: isPrimaryDevice,
                        tx: tx
                    )
                }
            }
            let contexts = Contexts(
                localIdentifiers: localIdentifiers,
                startTimestampMs: startTimestampMs,
                attachmentByteCounter: attachmentByteCounter,
                isPrimaryDevice: isPrimaryDevice,
                currentRemoteConfig: currentRemoteConfig,
                backupPurpose: backupPurpose,
                tx: tx
            )

            while hasMoreFrames {
                try Task.checkCancellation()
                try autoreleasepool {
                    let frame: BackupProto_Frame?
                    switch stream.readFrame() {
                    case let .success(_frame, moreBytesAvailable):
                        frame = _frame
                        hasMoreFrames = moreBytesAvailable
                        framesRestored += 1
                    case .invalidByteLengthDelimiter:
                        throw OWSAssertionError("invalid byte length delimiter on header")
                    case .emptyFinalFrame:
                        frame = nil
                        hasMoreFrames = false
                    case .protoDeserializationError(let error):
                        // fail the whole thing if we fail to deserialize one frame
                        owsFailDebug("Failed to deserialize proto frame!")
                        if BuildFlags.Backups.restoreFailOnAnyError {
                            throw error
                        } else {
                            return
                        }
                    }

                    guard
                        let frame,
                        let frameItem = frame.item
                    else {
                        if hasMoreFrames {
                            frameErrors.append(LoggableErrorAndProto(
                                error: BackupArchive.UnrecognizedEnumError(
                                    enumType: BackupProto_Frame.OneOf_Item.self
                                ),
                                wasFrameDropped: true
                            ))
                        }
                        return
                    }

                    try bencher.processFrame { frameBencher in
                        defer {
                            frameBencher.didProcessFrame(frame)
                        }

                        switch frameItem {
                        case .recipient(let recipient):
                            let recipientResult: BackupArchive.RestoreFrameResult<BackupArchive.RecipientId>
                            switch recipient.destination {
                            case nil:
                                recipientResult = .unrecognizedEnum(BackupArchive.UnrecognizedEnumError(
                                    enumType: BackupProto_Recipient.OneOf_Destination.self
                                ))
                            case .self_p(let selfRecipientProto):
                                recipientResult = localRecipientArchiver.restoreSelfRecipient(
                                    selfRecipientProto,
                                    recipient: recipient,
                                    context: contexts.recipient
                                )
                            case .contact(let contactRecipientProto):
                                recipientResult = contactRecipientArchiver.restoreContactRecipientProto(
                                    contactRecipientProto,
                                    recipient: recipient,
                                    context: contexts.recipient
                                )
                            case .group(let groupRecipientProto):
                                recipientResult = groupRecipientArchiver.restoreGroupRecipientProto(
                                    groupRecipientProto,
                                    recipient: recipient,
                                    context: contexts.recipient
                                )
                            case .distributionList(let distributionListRecipientProto):
                                recipientResult = distributionListRecipientArchiver.restoreDistributionListRecipientProto(
                                    distributionListRecipientProto,
                                    recipient: recipient,
                                    context: contexts.recipient
                                )
                            case .releaseNotes(let releaseNotesRecipientProto):
                                recipientResult = releaseNotesRecipientArchiver.restoreReleaseNotesRecipientProto(
                                    releaseNotesRecipientProto,
                                    recipient: recipient,
                                    context: contexts.recipient
                                )
                            case .callLink(let callLinkRecipientProto):
                                recipientResult = callLinkRecipientArchiver.restoreCallLinkRecipientProto(
                                    callLinkRecipientProto,
                                    recipient: recipient,
                                    context: contexts.recipient
                                )
                            }

                            switch recipientResult {
                            case .success:
                                return
                            case .unrecognizedEnum(let error):
                                frameErrors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true, protoFrame: recipient))
                                return
                            case .partialRestore(let errors):
                                frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false, protoFrame: recipient) })
                            case .failure(let errors):
                                frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFrameDropped: true, protoFrame: recipient) })
                                if BuildFlags.Backups.restoreFailOnAnyError {
                                    throw BackupError()
                                }
                            }
                        case .chat(let chat):
                            let chatResult = chatArchiver.restore(
                                chat,
                                context: contexts.chat
                            )
                            switch chatResult {
                            case .success:
                                return
                            case .unrecognizedEnum(let error):
                                frameErrors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true, protoFrame: chat))
                                return
                            case .partialRestore(let errors):
                                frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false, protoFrame: chat) })
                            case .failure(let errors):
                                frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFrameDropped: true, protoFrame: chat) })
                                if BuildFlags.Backups.restoreFailOnAnyError {
                                    throw BackupError()
                                }
                            }
                        case .chatItem(let chatItem):
                            let chatItemResult = chatItemArchiver.restore(
                                chatItem,
                                context: contexts.chatItem
                            )
                            switch chatItemResult {
                            case .success:
                                return
                            case .unrecognizedEnum(let error):
                                frameErrors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true, protoFrame: chatItem))
                                return
                            case .partialRestore(let errors):
                                frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false, protoFrame: chatItem) })
                            case .failure(let errors):
                                frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFrameDropped: true, protoFrame: chatItem) })
                                if BuildFlags.Backups.restoreFailOnAnyError {
                                    throw BackupError()
                                }
                            }
                        case .account(let backupProtoAccountData):
                            let accountDataResult = accountDataArchiver.restore(
                                backupProtoAccountData,
                                context: contexts.accountData,
                                chatColorsContext: contexts.customChatColor,
                                chatItemContext: contexts.chatItem
                            )
                            switch accountDataResult {
                            case .success:
                                return
                            case .unrecognizedEnum(let error):
                                frameErrors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true, protoFrame: backupProtoAccountData))
                                return
                            case .partialRestore(let errors):
                                frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false, protoFrame: backupProtoAccountData) })
                            case .failure(let errors):
                                frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFrameDropped: true, protoFrame: backupProtoAccountData) })
                                // We always fail if we fail to import account data, even in prod.
                                throw BackupError()
                            }
                        case .stickerPack(let backupProtoStickerPack):
                            let stickerPackResult = stickerPackArchiver.restore(
                                backupProtoStickerPack,
                                context: contexts.stickerPack
                            )
                            switch stickerPackResult {
                            case .success:
                                return
                            case .unrecognizedEnum(let error):
                                frameErrors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true, protoFrame: backupProtoStickerPack))
                                return
                            case .partialRestore(let errors):
                                frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false, protoFrame: backupProtoStickerPack) })
                            case .failure(let errors):
                                frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFrameDropped: true, protoFrame: backupProtoStickerPack) })
                                if BuildFlags.Backups.restoreFailOnAnyError {
                                    throw BackupError()
                                }
                            }
                        case .adHocCall(let backupProtoAdHocCall):
                            let adHocCallResult = adHocCallArchiver.restore(
                                backupProtoAdHocCall,
                                context: contexts.chatItem
                            )
                            switch adHocCallResult {
                            case .success:
                                return
                            case .unrecognizedEnum(let error):
                                frameErrors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true, protoFrame: backupProtoAdHocCall))
                                return
                            case .partialRestore(let errors):
                                frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFrameDropped: false, protoFrame: backupProtoAdHocCall) })
                            case .failure(let errors):
                                frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFrameDropped: true, protoFrame: backupProtoAdHocCall) })
                                if BuildFlags.Backups.restoreFailOnAnyError {
                                    throw BackupError()
                                }
                            }
                        case .notificationProfile:
                            // Notification profiles are unsupported on iOS and
                            // we do not even round trip them per spec.
                            break
                        case .chatFolder:
                            // Chat folders are unsupported on iOS and
                            // we do not even round trip them per spec.
                            break
                        }
                    }
                }
            }

            stream.closeFileStream()

            // Now that we've imported successfully, we want to recreate the
            // the indexes we temporarily dropped.
            recreateIndexesProgress?.willStartIndexRecreation(totalFramesRestored: framesRestored)
            try bencher.benchPostFrameRestoreAction(.RecreateInteractionIndexes) {
                try createIndexes(
                    interactionIndexes,
                    onTable: InteractionRecord.databaseTableName,
                    tx: tx
                )
            }
            recreateIndexesProgress?.didFinishIndexRecreation()

            // Take any necessary post-frame-restore actions.
            try postFrameRestoreActionManager.performPostFrameRestoreActions(
                recipientActions: contexts.recipient.postFrameRestoreActions,
                chatActions: contexts.chat.postFrameRestoreActions,
                bencher: bencher,
                chatItemContext: contexts.chatItem
            )

            // Index threads synchronously, since that should be fast.
            bencher.benchPostFrameRestoreAction(.IndexThreads) {
                fullTextSearchIndexer.indexThreads(tx: tx)
            }

            // Schedule background message indexing, since that'll be slow.
            try fullTextSearchIndexer.scheduleMessagesJob(tx: tx)

            // Record that we've restored a Backup!
            kvStore.setInt(
                BackupRestoreState.unfinalized.rawValue,
                key: Constants.keyValueStoreRestoreStateKey,
                transaction: tx
            )

            // Populate "last Backup" details, since otherwise they'll be blank
            // and imply the user has no Backup.
            backupSettingsStore.setLastBackupDetails(
                date: Date(millisecondsSince1970: backupInfo.backupTimeMs),
                backupFileSizeBytes: inputFileSize,
                backupMediaSizeBytes: attachmentByteCounter.attachmentByteSize(),
                tx: tx,
            )

            tx.addSyncCompletion { [
                avatarFetcher,
                backupAttachmentCoordinator,
                disappearingMessagesJob
            ] in
                Task {
                    // Kick off avatar fetches enqueued during restore.
                    try await avatarFetcher.runIfNeeded()
                }

                Task {
                    // Kick off attachment downloads enqueued during restore.
                    try await backupAttachmentCoordinator.restoreAttachmentsIfNeeded()
                }

                // Start ticking down for disappearing messages.
                disappearingMessagesJob.startIfNecessary()
            }

            logger.info("Imported with version \(backupInfo.version), timestamp \(backupInfo.backupTimeMs)")
            logger.info("Backup app version: \(backupInfo.currentAppVersion.nilIfEmpty ?? "Missing!")")
            logger.info("Backup first app version: \(backupInfo.firstAppVersion.nilIfEmpty ?? "Missing!")")
            bencher.logResults()

            return backupInfo
        })

        processErrors(errors: frameErrors, didFail: result.isSuccess.negated)
        return try result.get()
    }

    // MARK: -

    private struct SQLiteIndexInfo {
        let tableName: String
        let sqlThatCreatedIndex: String
    }

    private func dropAllIndexes(
        forTable tableName: String,
        tx: DBWriteTransaction
    ) throws -> [SQLiteIndexInfo] {
        let allIndexesOnTable: [GRDB.IndexInfo] = try tx.database.indexes(on: tableName)

        var sqliteIndexInfos = [SQLiteIndexInfo]()

        for index in allIndexesOnTable {
            if index.name.contains("autoindex") {
                // Skip indexes automatically created by SQLite, such as on
                // primary keys.
                continue
            }

            guard let sqlThatCreatedIndex = try String.fetchOne(
                tx.database,
                sql: """
                    SELECT sql FROM sqlite_master
                    WHERE type = 'index'
                    AND name = '\(index.name)'
                """
            ) else {
                throw OWSAssertionError("Failed to get SQL for creating index \(index.name)!")
            }

            sqliteIndexInfos.append(SQLiteIndexInfo(
                tableName: tableName,
                sqlThatCreatedIndex: sqlThatCreatedIndex
            ))

            try tx.database.drop(index: index.name)
        }

        return sqliteIndexInfos
    }

    private func createIndexes(
        _ indexInfos: [SQLiteIndexInfo],
        onTable tableName: String,
        tx: DBWriteTransaction
    ) throws {
        owsPrecondition(indexInfos.allSatisfy { $0.tableName == tableName })

        for indexInfo in indexInfos {
            try tx.database.execute(sql: indexInfo.sqlThatCreatedIndex)
        }
    }

    // MARK: -

    private func processErrors(
        errors: [LoggableErrorAndProto],
        didFail: Bool
    ) {
        let collapsedErrors = BackupArchive.collapse(errors)
        var maxLogLevel = -1
        var wasFrameDropped = false
        collapsedErrors.forEach { collapsedError in
            collapsedError.log()
            maxLogLevel = max(maxLogLevel, collapsedError.logLevel.rawValue)
            if collapsedError.wasFrameDropped {
                wasFrameDropped = true
            }
        }
        if wasFrameDropped {
            // Log this specifically so we can do a naive exact text search in debug logs.
            logger.error("Dropped frame(s) on backup export or import!!!")
        }
        // Only present errors if some error rises above warning.
        // (But if one does, present _all_ errors).
        if maxLogLevel > BackupArchive.LogLevel.warning.rawValue {
            Task {
                await db.awaitableWrite { tx in
                    backupArchiveErrorPresenter.persistErrors(collapsedErrors, didFail: didFail, tx: tx)
                }
            }

        }
    }

    /// TSAttachments must be migrated to v2 Attachments before we can create or restore backups.
    /// Normally this migration happens in the background; force it to run and finish now.
    private func migrateAttachmentsBeforeBackup(progress: OWSProgressSink?) async {
        let didMigrateAnything = await incrementalTSAttachmentMigrator.runInMainAppUntilFinished(
            ignorePastFailures: true,
            progress: progress
        )

        if
            let progress,
            !didMigrateAnything
        {
            // Nothing was migrated, so progress wasn't updated. Complete it!
            let source = await progress.addSource(
                withLabel: "TSAttachmentMigrator had nothing to do",
                unitCount: 1
            )
            source.complete()
        }
    }

    private func validateEncryptedBackup(
        fileUrl: URL,
        backupEncryptionKey: MessageBackupKey,
        backupPurpose: MessageBackupPurpose
    ) async throws {
        let fileSize = (try? OWSFileSystem.fileSize(ofPath: fileUrl.path)) ?? 0

        do {
            let result = try validateMessageBackup(key: backupEncryptionKey, purpose: backupPurpose, length: fileSize) {
                return try FileHandle(forReadingFrom: fileUrl)
            }
            if result.fields.count > 0 {
                throw BackupValidationError.unknownFields(result.fields)
            }
        } catch {
            switch error {
            case let validationError as MessageBackupValidationError:
                await backupArchiveErrorPresenter.persistValidationError(validationError)
                logger.error("Backup validation failed \(validationError.errorMessage)")
                throw BackupValidationError.validationFailed(
                    message: validationError.errorMessage,
                    unknownFields: validationError.unknownFields.fields
                )
            case SignalError.ioError(let description):
                logger.error("Backup validation i/o error: \(description)")
                throw BackupValidationError.ioError(description)
            default:
                logger.error("Backup validation unknown error: \(error)")
                throw BackupValidationError.unknownError
            }
        }
    }

    // MARK: -

    public func scheduleRestoreFromSVRBBeforeNextExport(tx: DBWriteTransaction) {
        kvStore.setBool(
            true,
            key: Constants.keyValueStoreNeedForwardSecrecyTokenFetchKey,
            transaction: tx
        )
    }

    private func needsRestoreFromSVRBBeforeRemoteExport(tx: DBReadTransaction) -> Bool {
        kvStore.getBool(
            Constants.keyValueStoreNeedForwardSecrecyTokenFetchKey,
            defaultValue: false,
            transaction: tx
        )
    }

    private func fetchRemoteSVRBForwardSecrecyToken(
        key: MessageRootBackupKey,
        auth: ChatServiceAuth
    ) async throws {
        let backupServiceAuth = try await backupRequestManager.fetchBackupServiceAuthForRegistration(
            key: key,
            localAci: key.aci,
            chatServiceAuth: auth
        )

        let metadataHeader: BackupNonce.MetadataHeader
        do {
            metadataHeader = try await backupCdnInfo(
                backupKey: key,
                backupAuth: backupServiceAuth
            ).metadataHeader
        } catch let error as OWSHTTPError where error.responseStatusCode == 404 {
            // If no backup is found, treat this as unrecoverable
            throw SVRBError.unrecoverable
        }

        let nonceSource = BackupImportSource.NonceMetadataSource.svrB(header: metadataHeader, auth: auth)
        let source = BackupImportSource.remote(key: key, nonceSource: nonceSource)
        _ = try await source.deriveBackupEncryptionKeyWithSVRBIfNeeded(
            backupRequestManager: backupRequestManager,
            db: db,
            libsignalNet: libsignalNet,
            nonceStore: backupNonceMetadataStore
        )
    }
}
