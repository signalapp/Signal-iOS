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

public class MessageBackupManagerImpl: MessageBackupManager {
    private enum Constants {
        static let keyValueStoreCollectionName = "MessageBackupManager"
        static let keyValueStoreHasReservedBackupKey = "HasReservedBackupKey"
        static let keyValueStoreHasReservedMediaBackupKey = "HasReservedMediaBackupKey"
        static let keyValueStoreHasRestoredBackupKey = "HasRestoredBackup"

        static let supportedBackupVersion: UInt64 = 1

        /// The ratio of frames processed for which to sample memory.
        static let memorySamplerFrameRatio: Float = FeatureFlags.messageBackupDetailedBenchLogging ? 0.001 : 0
    }

    private class NotImplementedError: Error {}
    private class BackupError: Error {}
    private typealias LoggableErrorAndProto = MessageBackup.LoggableErrorAndProto

    private let accountDataArchiver: MessageBackupAccountDataArchiver
    private let adHocCallArchiver: MessageBackupAdHocCallArchiver
    private let appVersion: AppVersion
    private let attachmentDownloadManager: AttachmentDownloadManager
    private let attachmentUploadManager: AttachmentUploadManager
    private let avatarFetcher: MessageBackupAvatarFetcher
    private let backupAttachmentDownloadManager: BackupAttachmentDownloadManager
    private let backupAttachmentUploadManager: BackupAttachmentUploadManager
    private let backupRequestManager: MessageBackupRequestManager
    private let backupStickerPackDownloadStore: BackupStickerPackDownloadStore
    private let callLinkRecipientArchiver: MessageBackupCallLinkRecipientArchiver
    private let chatArchiver: MessageBackupChatArchiver
    private let chatItemArchiver: MessageBackupChatItemArchiver
    private let contactRecipientArchiver: MessageBackupContactRecipientArchiver
    private let databaseChangeObserver: DatabaseChangeObserver
    private let dateProvider: DateProvider
    private let dateProviderMonotonic: DateProviderMonotonic
    private let db: any DB
    private let dbFileSizeProvider: DBFileSizeProvider
    private let disappearingMessagesJob: OWSDisappearingMessagesJob
    private let distributionListRecipientArchiver: MessageBackupDistributionListRecipientArchiver
    private let encryptedStreamProvider: MessageBackupEncryptedProtoStreamProvider
    private let errorPresenter: MessageBackupErrorPresenter
    private let fullTextSearchIndexer: MessageBackupFullTextSearchIndexer
    private let groupRecipientArchiver: MessageBackupGroupRecipientArchiver
    private let incrementalTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator
    private let kvStore: KeyValueStore
    private let localStorage: AccountKeyStore
    private let localRecipientArchiver: MessageBackupLocalRecipientArchiver
    private let messageBackupKeyMaterial: MessageBackupKeyMaterial
    private let messagePipelineSupervisor: MessagePipelineSupervisor
    private let plaintextStreamProvider: MessageBackupPlaintextProtoStreamProvider
    private let postFrameRestoreActionManager: MessageBackupPostFrameRestoreActionManager
    private let releaseNotesRecipientArchiver: MessageBackupReleaseNotesRecipientArchiver
    private let stickerPackArchiver: MessageBackupStickerPackArchiver

    public init(
        accountDataArchiver: MessageBackupAccountDataArchiver,
        adHocCallArchiver: MessageBackupAdHocCallArchiver,
        appVersion: AppVersion,
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentUploadManager: AttachmentUploadManager,
        avatarFetcher: MessageBackupAvatarFetcher,
        backupAttachmentDownloadManager: BackupAttachmentDownloadManager,
        backupAttachmentUploadManager: BackupAttachmentUploadManager,
        backupRequestManager: MessageBackupRequestManager,
        backupStickerPackDownloadStore: BackupStickerPackDownloadStore,
        callLinkRecipientArchiver: MessageBackupCallLinkRecipientArchiver,
        chatArchiver: MessageBackupChatArchiver,
        chatItemArchiver: MessageBackupChatItemArchiver,
        contactRecipientArchiver: MessageBackupContactRecipientArchiver,
        databaseChangeObserver: DatabaseChangeObserver,
        dateProvider: @escaping DateProvider,
        dateProviderMonotonic: @escaping DateProviderMonotonic,
        db: any DB,
        dbFileSizeProvider: DBFileSizeProvider,
        disappearingMessagesJob: OWSDisappearingMessagesJob,
        distributionListRecipientArchiver: MessageBackupDistributionListRecipientArchiver,
        encryptedStreamProvider: MessageBackupEncryptedProtoStreamProvider,
        errorPresenter: MessageBackupErrorPresenter,
        fullTextSearchIndexer: MessageBackupFullTextSearchIndexer,
        groupRecipientArchiver: MessageBackupGroupRecipientArchiver,
        incrementalTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator,
        localStorage: AccountKeyStore,
        localRecipientArchiver: MessageBackupLocalRecipientArchiver,
        messageBackupKeyMaterial: MessageBackupKeyMaterial,
        messagePipelineSupervisor: MessagePipelineSupervisor,
        plaintextStreamProvider: MessageBackupPlaintextProtoStreamProvider,
        postFrameRestoreActionManager: MessageBackupPostFrameRestoreActionManager,
        releaseNotesRecipientArchiver: MessageBackupReleaseNotesRecipientArchiver,
        stickerPackArchiver: MessageBackupStickerPackArchiver
    ) {
        self.accountDataArchiver = accountDataArchiver
        self.appVersion = appVersion
        self.attachmentDownloadManager = attachmentDownloadManager
        self.attachmentUploadManager = attachmentUploadManager
        self.avatarFetcher = avatarFetcher
        self.backupAttachmentDownloadManager = backupAttachmentDownloadManager
        self.backupAttachmentUploadManager = backupAttachmentUploadManager
        self.backupRequestManager = backupRequestManager
        self.backupStickerPackDownloadStore = backupStickerPackDownloadStore
        self.callLinkRecipientArchiver = callLinkRecipientArchiver
        self.chatArchiver = chatArchiver
        self.chatItemArchiver = chatItemArchiver
        self.contactRecipientArchiver = contactRecipientArchiver
        self.databaseChangeObserver = databaseChangeObserver
        self.dateProvider = dateProvider
        self.dateProviderMonotonic = dateProviderMonotonic
        self.db = db
        self.dbFileSizeProvider = dbFileSizeProvider
        self.disappearingMessagesJob = disappearingMessagesJob
        self.distributionListRecipientArchiver = distributionListRecipientArchiver
        self.encryptedStreamProvider = encryptedStreamProvider
        self.errorPresenter = errorPresenter
        self.fullTextSearchIndexer = fullTextSearchIndexer
        self.groupRecipientArchiver = groupRecipientArchiver
        self.incrementalTSAttachmentMigrator = incrementalTSAttachmentMigrator
        self.kvStore = KeyValueStore(collection: Constants.keyValueStoreCollectionName)
        self.localStorage = localStorage
        self.localRecipientArchiver = localRecipientArchiver
        self.messageBackupKeyMaterial = messageBackupKeyMaterial
        self.messagePipelineSupervisor = messagePipelineSupervisor
        self.plaintextStreamProvider = plaintextStreamProvider
        self.postFrameRestoreActionManager = postFrameRestoreActionManager
        self.releaseNotesRecipientArchiver = releaseNotesRecipientArchiver
        self.stickerPackArchiver = stickerPackArchiver
        self.adHocCallArchiver = adHocCallArchiver
    }

    // MARK: - Remote backups

    /// Initialize Message Backups by reserving a backup ID and registering a public key used to sign backup auth credentials.
    /// These registration calls are safe to call multiple times, but to avoid unecessary network calls, the app will remember if
    /// backups have been successfully registered on this device and will no-op in this case.
    private func reserveAndRegister(localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws {
        let (hasReservedBackupKey, hasReservedMediaBackupKey) = db.read { tx in
            return (
                kvStore.getBool(Constants.keyValueStoreHasReservedBackupKey, transaction: tx) ?? false,
                kvStore.getBool(Constants.keyValueStoreHasReservedMediaBackupKey, transaction: tx) ?? false
            )
        }

        if hasReservedBackupKey && hasReservedMediaBackupKey {
            return
        }

        // Both reserveBackupId and registerBackupKeys can be called multiple times, so if
        // we think the backupId needs to be registered, register the public key at the same time.
        let localAci = localIdentifiers.aci
        try await backupRequestManager.reserveBackupId(localAci: localAci, auth: auth)
        try await backupRequestManager.registerBackupKeys(localAci: localAci, auth: auth)

        // Remember this device has registered for backups
        await db.awaitableWrite { [weak self] tx in
            self?.kvStore.setBool(true, key: Constants.keyValueStoreHasReservedBackupKey, transaction: tx)
            self?.kvStore.setBool(true, key: Constants.keyValueStoreHasReservedMediaBackupKey, transaction: tx)
        }
    }

    public func downloadEncryptedBackup(localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws -> URL {
        let backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
            for: .messages,
            localAci: localIdentifiers.aci,
            auth: auth
        )
        let metadata = try await backupRequestManager.fetchBackupRequestMetadata(auth: backupAuth)
        let tmpFileUrl = try await attachmentDownloadManager.downloadBackup(metadata: metadata).awaitable()

        // Once protos calm down, this can be enabled to warn/error on failed validation
        // try await validateBackup(localIdentifiers: localIdentifiers, fileUrl: tmpFileUrl)

        return tmpFileUrl
    }

    public func uploadEncryptedBackup(
        metadata: Upload.EncryptedBackupUploadMetadata,
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata> {
        // This will return early if this device has already registered the backup ID.
        try await reserveAndRegister(localIdentifiers: localIdentifiers, auth: auth)
        let backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
            for: .messages,
            localAci: localIdentifiers.aci,
            auth: auth
        )
        let form = try await backupRequestManager.fetchBackupUploadForm(auth: backupAuth)
        return try await attachmentUploadManager.uploadBackup(localUploadMetadata: metadata, form: form)
    }

    // MARK: - Export

    public func exportEncryptedBackup(
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey,
        backupPurpose: MessageBackupPurpose,
        progress progressSink: OWSProgressSink?
    ) async throws -> Upload.EncryptedBackupUploadMetadata {
        guard
            FeatureFlags.messageBackupFileAlpha
                || FeatureFlags.linkAndSyncPrimaryExport
        else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        return try await _exportBackup<Upload.EncryptedBackupUploadMetadata>(
            localIdentifiers: localIdentifiers,
            backupPurpose: backupPurpose,
            progressSink: progressSink,
            benchTitle: "Export encrypted Backup",
            openOutputStreamBlock: { exportProgress, tx in
                return encryptedStreamProvider.openEncryptedOutputFileStream(
                    localAci: localIdentifiers.aci,
                    backupKey: backupKey,
                    exportProgress: exportProgress,
                    tx: tx
                )
            }
        )
    }

    public func exportPlaintextBackup(
        localIdentifiers: LocalIdentifiers,
        backupPurpose: MessageBackupPurpose,
        progress progressSink: OWSProgressSink?
    ) async throws -> URL {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        return try await _exportBackup<URL>(
            localIdentifiers: localIdentifiers,
            backupPurpose: backupPurpose,
            progressSink: progressSink,
            benchTitle: "Export plaintext Backup",
            openOutputStreamBlock: { exportProgress, tx in
                return plaintextStreamProvider.openPlaintextOutputFileStream(
                    exportProgress: exportProgress
                )
            }
        )
    }

    private func _exportBackup<OutputStreamMetadata>(
        localIdentifiers: LocalIdentifiers,
        backupPurpose: MessageBackupPurpose,
        progressSink: OWSProgressSink?,
        benchTitle: String,
        openOutputStreamBlock: (
            MessageBackupExportProgress?,
            DBReadTransaction
        ) -> MessageBackup.ProtoStream.OpenOutputStreamResult<OutputStreamMetadata>
    ) async throws -> OutputStreamMetadata {
        let migrateAttachmentsProgressSink: OWSProgressSink?
        let exportProgress: MessageBackupExportProgress?
        if let progressSink {
            migrateAttachmentsProgressSink = await progressSink.addChild(
                withLabel: "Export Backup: Migrate Attachments",
                unitCount: 5
            )
            exportProgress = try await .prepare(
                sink: await progressSink.addChild(
                    withLabel: "Export Backup: Export Frames",
                    unitCount: 95
                ),
                db: db
            )
        } else {
            migrateAttachmentsProgressSink = nil
            exportProgress = nil
        }

        let messageProcessingSuspensionHandle = messagePipelineSupervisor.suspendMessageProcessing(for: .messageBackup)
        defer {
            messageProcessingSuspensionHandle.invalidate()
        }

        await migrateAttachmentsBeforeBackup(progress: migrateAttachmentsProgressSink)

        let result: Result<OutputStreamMetadata, Error> = await db.awaitableWriteWithTxCompletion { tx in
            return self.databaseChangeObserver.disable(tx: tx, during: { tx in
                do {
                    let outputStreamMetadata = try BenchMemory(
                        title: benchTitle,
                        memorySamplerRatio: Constants.memorySamplerFrameRatio,
                        logInProduction: true
                    ) { memorySampler -> OutputStreamMetadata in
                        let outputStream: MessageBackupProtoOutputStream
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
                            currentAppVersion: appVersion.currentAppVersion,
                            firstAppVersion: appVersion.firstBackupAppVersion ?? appVersion.firstAppVersion,
                            memorySampler: memorySampler,
                            tx: tx
                        )

                        return try outputStreamMetadataProvider()
                    }

                    return .commit(.success(outputStreamMetadata))
                } catch let error {
                    return .rollback(.failure(error))
                }
            })
        }

        return try result.get()
    }

    private func _exportBackup(
        outputStream stream: MessageBackupProtoOutputStream,
        localIdentifiers: LocalIdentifiers,
        backupPurpose: MessageBackupPurpose,
        currentAppVersion: String,
        firstAppVersion: String,
        memorySampler: MemorySampler,
        tx: DBWriteTransaction
    ) throws {
        let bencher = MessageBackup.ArchiveBencher(
            dateProviderMonotonic: dateProviderMonotonic,
            memorySampler: memorySampler
        )

        let startTimestamp = dateProvider().ows_millisecondsSince1970
        let backupVersion = Constants.supportedBackupVersion
        let purposeString: String = switch backupPurpose {
        case .deviceTransfer: "LinkNSync"
        case .remoteBackup: "RemoteBackup"
        }

        var errors = [LoggableErrorAndProto]()
        let result = Result<Void, Error>(catching: {
            Logger.info("Exporting for \(purposeString) with version \(backupVersion), timestamp \(startTimestamp)")

            try autoreleasepool {
                try writeHeader(
                    stream: stream,
                    backupVersion: backupVersion,
                    backupTimeMs: startTimestamp,
                    currentAppVersion: currentAppVersion,
                    firstAppVersion: firstAppVersion,
                    tx: tx
                )
            }
            try Task.checkCancellation()

            let currentBackupAttachmentUploadEra: String?
            if MessageBackupMessageAttachmentArchiver.isFreeTierBackup() {
                currentBackupAttachmentUploadEra = nil
            } else {
                currentBackupAttachmentUploadEra = try MessageBackupMessageAttachmentArchiver.currentUploadEra()
            }

            let customChatColorContext = MessageBackup.CustomChatColorArchivingContext(
                backupPurpose: backupPurpose,
                bencher: bencher,
                currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
                backupAttachmentUploadManager: backupAttachmentUploadManager,
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
                bencher: bencher
            )

            try Task.checkCancellation()

            let localRecipientId: MessageBackup.RecipientId
            switch localRecipientResult {
            case .success(let success):
                localRecipientId = success
            case .failure(let error):
                errors.append(LoggableErrorAndProto(error: error, wasFrameDropped: true))
                throw OWSAssertionError("Failed to archive local recipient!")
            }

            let recipientArchivingContext = MessageBackup.RecipientArchivingContext(
                backupPurpose: backupPurpose,
                bencher: bencher,
                currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
                backupAttachmentUploadManager: backupAttachmentUploadManager,
                localIdentifiers: localIdentifiers,
                localRecipientId: localRecipientId,
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

            let chatArchivingContext = MessageBackup.ChatArchivingContext(
                backupPurpose: backupPurpose,
                bencher: bencher,
                currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
                backupAttachmentUploadManager: backupAttachmentUploadManager,
                customChatColorContext: customChatColorContext,
                recipientContext: recipientArchivingContext,
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

            let archivingContext = MessageBackup.ArchivingContext(
                backupPurpose: backupPurpose,
                bencher: bencher,
                currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
                backupAttachmentUploadManager: backupAttachmentUploadManager,
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

            tx.addAsyncCompletion(on: DispatchQueue.global()) { [backupAttachmentUploadManager] in
                Task {
                    // TODO: [Backups] this needs to talk to the banner at the top of the chat
                    // list to show progress.
                    try await backupAttachmentUploadManager.backUpAllAttachments()
                }
            }

            Logger.info("Finished exporting backup")
            bencher.logResults()
        })
        processErrors(errors: errors, didFail: result.isSuccess.negated, tx: tx)
        return try result.get()
    }

    private func writeHeader(
        stream: MessageBackupProtoOutputStream,
        backupVersion: UInt64,
        backupTimeMs: UInt64,
        currentAppVersion: String,
        firstAppVersion: String,
        tx: DBWriteTransaction
    ) throws {
        var backupInfo = BackupProto_BackupInfo()
        backupInfo.version = backupVersion
        backupInfo.backupTimeMs = backupTimeMs
        backupInfo.currentAppVersion = currentAppVersion
        backupInfo.firstAppVersion = firstAppVersion

        backupInfo.mediaRootBackupKey = localStorage.getOrGenerateMediaRootBackupKey(tx: tx).serialize().asData

        switch stream.writeHeader(backupInfo) {
        case .success:
            break
        case .fileIOError(let error), .protoSerializationError(let error):
            throw error
        }
    }

    // MARK: - Import

    public func hasRestoredFromBackup(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(
            Constants.keyValueStoreHasRestoredBackupKey,
            defaultValue: false,
            transaction: tx
        )
    }

    public func importEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey,
        progress progressSink: OWSProgressSink?
    ) async throws {
        guard FeatureFlags.messageBackupFileAlpha || FeatureFlags.linkAndSyncLinkedImport else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        try await _importBackup(
            fileUrl: fileUrl,
            localIdentifiers: localIdentifiers,
            progressSink: progressSink,
            benchTitle: "Import encrypted Backup",
            openInputStreamBlock: { fileUrl, frameRestoreProgress, tx in
                return encryptedStreamProvider.openEncryptedInputFileStream(
                    fileUrl: fileUrl,
                    localAci: localIdentifiers.aci,
                    backupKey: backupKey,
                    frameRestoreProgress: frameRestoreProgress,
                    tx: tx
                )
            }
        )
    }

    public func importPlaintextBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        progress progressSink: OWSProgressSink?
    ) async throws {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        try await _importBackup(
            fileUrl: fileUrl,
            localIdentifiers: localIdentifiers,
            progressSink: progressSink,
            benchTitle: "Import plaintext Backup",
            openInputStreamBlock: { fileUrl, frameRestoreProgress, _ in
                return plaintextStreamProvider.openPlaintextInputFileStream(
                    fileUrl: fileUrl,
                    frameRestoreProgress: frameRestoreProgress
                )
            }
        )
    }

    private func _importBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        progressSink: OWSProgressSink?,
        benchTitle: String,
        openInputStreamBlock: (
            URL,
            MessageBackupImportFrameRestoreProgress?,
            DBReadTransaction
        ) -> MessageBackup.ProtoStream.OpenInputStreamResult
    ) async throws {
        let migrateAttachmentsProgressSink: OWSProgressSink?
        let frameRestoreProgress: MessageBackupImportFrameRestoreProgress?
        let recreateIndexesProgress: MessageBackupImportRecreateIndexesProgress?
        if let progressSink {
            migrateAttachmentsProgressSink = await progressSink.addChild(
                withLabel: "Import Backup: Migrate Attachments",
                unitCount: 5
            )
            frameRestoreProgress = try await .prepare(
                sink: await progressSink.addChild(
                    withLabel: "Import Backup: Import Frames",
                    unitCount: 80
                ),
                fileUrl: fileUrl
            )
            recreateIndexesProgress = await .prepare(
                sink: await progressSink.addChild(
                    withLabel: "Import Backup: Recreate Indexes",
                    unitCount: 15
                )
            )
        } else {
            migrateAttachmentsProgressSink = nil
            frameRestoreProgress = nil
            recreateIndexesProgress = nil
        }

        let messageProcessingSuspensionHandle = messagePipelineSupervisor.suspendMessageProcessing(for: .messageBackup)
        defer {
            messageProcessingSuspensionHandle.invalidate()
        }

        await migrateAttachmentsBeforeBackup(progress: migrateAttachmentsProgressSink)

        let result: Result<BackupProto_BackupInfo, Error> = await db.awaitableWriteWithTxCompletion { tx in
            do {
                let backupInfo = try BenchMemory(
                    title: benchTitle,
                    memorySamplerRatio: Constants.memorySamplerFrameRatio,
                    logInProduction: true
                ) { memorySampler -> BackupProto_BackupInfo in
                    return try self.databaseChangeObserver.disable(tx: tx) { tx in
                        let inputStream: MessageBackupProtoInputStream
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

                        return try self._importBackup(
                            inputStream: inputStream,
                            localIdentifiers: localIdentifiers,
                            recreateIndexesProgress: recreateIndexesProgress,
                            memorySampler: memorySampler,
                            tx: tx
                        )
                    }
                }

                return .commit(.success(backupInfo))
            } catch let error {
                return .rollback(.failure(error))
            }
        }

        let backupInfo = try result.get()

        appVersion.didRestoreFromBackup(
            backupCurrentAppVersion: backupInfo.currentAppVersion.nilIfEmpty,
            backupFirstAppVersion: backupInfo.firstAppVersion.nilIfEmpty
        )
    }

    private func _importBackup(
        inputStream stream: MessageBackupProtoInputStream,
        localIdentifiers: LocalIdentifiers,
        recreateIndexesProgress: MessageBackupImportRecreateIndexesProgress?,
        memorySampler: MemorySampler,
        tx: DBWriteTransaction
    ) throws -> BackupProto_BackupInfo {
        let bencher = MessageBackup.RestoreBencher(
            dateProviderMonotonic: dateProviderMonotonic,
            dbFileSizeProvider: dbFileSizeProvider,
            memorySampler: memorySampler
        )

        guard !hasRestoredFromBackup(tx: tx) else {
            throw OWSAssertionError("Restoring from backup twice!")
        }

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
                    error: MessageBackup.RestoreFrameError.restoreFrameError(
                        .invalidProtoData(.missingBackupInfoHeader),
                        MessageBackup.BackupInfoId()
                    ),
                    wasFrameDropped: true
                ))
                throw error
            }

            Logger.info("Importing with version \(backupInfo.version), timestamp \(backupInfo.backupTimeMs)")

            guard backupInfo.version == Constants.supportedBackupVersion else {
                frameErrors.append(LoggableErrorAndProto(
                    error: MessageBackup.RestoreFrameError.restoreFrameError(
                        .invalidProtoData(.unsupportedBackupInfoVersion),
                        MessageBackup.BackupInfoId()
                    ),
                    wasFrameDropped: true,
                    protoFrame: backupInfo
                ))
                throw BackupImportError.unsupportedVersion
            }
            do {
                localStorage.setMediaRootBackupKey(try BackupKey(contents: Array(backupInfo.mediaRootBackupKey)), tx: tx)
            } catch {
                frameErrors.append(LoggableErrorAndProto(
                    error: MessageBackup.RestoreFrameError.restoreFrameError(
                        .invalidProtoData(.invalidMediaRootBackupKey),
                        MessageBackup.BackupInfoId()
                    ),
                    wasFrameDropped: true,
                    protoFrame: backupInfo
                ))
                throw error
            }

            /// Wraps all the various "contexts" we pass to downstream archivers.
            struct Contexts {
                let chat: MessageBackup.ChatRestoringContext
                var chatItem: MessageBackup.ChatItemRestoringContext
                let customChatColor: MessageBackup.CustomChatColorRestoringContext
                let recipient: MessageBackup.RecipientRestoringContext

                var all: [MessageBackup.RestoringContext] {
                    [chat, chatItem, customChatColor, recipient]
                }

                init(localIdentifiers: LocalIdentifiers, tx: DBWriteTransaction) {
                    customChatColor = MessageBackup.CustomChatColorRestoringContext(tx: tx)
                    recipient = MessageBackup.RecipientRestoringContext(
                        localIdentifiers: localIdentifiers,
                        tx: tx
                    )
                    chat = MessageBackup.ChatRestoringContext(
                        customChatColorContext: customChatColor,
                        recipientContext: recipient,
                        tx: tx
                    )
                    chatItem = MessageBackup.ChatItemRestoringContext(
                        recipientContext: recipient,
                        chatContext: chat,
                        tx: tx
                    )
                }
            }
            let contexts = Contexts(localIdentifiers: localIdentifiers, tx: tx)

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
                        if FeatureFlags.messageBackupRestoreFailOnAnyError {
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
                                error: MessageBackup.UnrecognizedEnumError(
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
                            let recipientResult: MessageBackup.RestoreFrameResult<MessageBackup.RecipientId>
                            switch recipient.destination {
                            case nil:
                                recipientResult = .unrecognizedEnum(MessageBackup.UnrecognizedEnumError(
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
                                if FeatureFlags.messageBackupRestoreFailOnAnyError {
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
                                if FeatureFlags.messageBackupRestoreFailOnAnyError {
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
                                if FeatureFlags.messageBackupRestoreFailOnAnyError {
                                    throw BackupError()
                                }
                            }
                        case .account(let backupProtoAccountData):
                            let accountDataResult = accountDataArchiver.restore(
                                backupProtoAccountData,
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
                                context: MessageBackup.RestoringContext(tx: tx)
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
                                if FeatureFlags.messageBackupRestoreFailOnAnyError {
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
                                if FeatureFlags.messageBackupRestoreFailOnAnyError {
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
            kvStore.setBool(true, key: Constants.keyValueStoreHasRestoredBackupKey, transaction: tx)

            tx.addAsyncCompletion(on: DispatchQueue.global()) { [
                avatarFetcher,
                backupAttachmentDownloadManager,
                disappearingMessagesJob
            ] in
                Task {
                    // Kick off avatar fetches enqueued during restore.
                    try await avatarFetcher.runIfNeeded()
                }

                Task {
                    // Kick off attachment downloads enqueued during restore.
                    try await backupAttachmentDownloadManager.restoreAttachmentsIfNeeded()
                }

                // Start ticking down for disappearing messages.
                disappearingMessagesJob.startIfNecessary()
            }

            Logger.info("Imported with version \(backupInfo.version), timestamp \(backupInfo.backupTimeMs)")
            Logger.info("Backup app version: \(backupInfo.currentAppVersion.nilIfEmpty ?? "Missing!")")
            Logger.info("Backup first app version: \(backupInfo.firstAppVersion.nilIfEmpty ?? "Missing!")")
            bencher.logResults()

            return backupInfo
        })

        processErrors(errors: frameErrors, didFail: result.isSuccess.negated, tx: tx)
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
        didFail: Bool,
        tx: DBWriteTransaction
    ) {
        let collapsedErrors = MessageBackup.collapse(errors)
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
            Logger.error("Dropped frame(s) on backup export or import!!!")
        }
        // Only present errors if some error rises above warning.
        // (But if one does, present _all_ errors).
        if maxLogLevel > MessageBackup.LogLevel.warning.rawValue {
            errorPresenter.persistErrors(collapsedErrors, didFail: didFail, tx: tx)
        }
    }

    /// TSAttachments must be migrated to v2 Attachments before we can create or restore backups.
    /// Normally this migration happens in the background; force it to run and finish now.
    private func migrateAttachmentsBeforeBackup(progress: OWSProgressSink?) async {
        let didMigrateAnything = await incrementalTSAttachmentMigrator.runUntilFinished(
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

    public func validateEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey,
        backupPurpose: MessageBackupPurpose
    ) async throws {
        let key = try backupKey.asMessageBackupKey(for: localIdentifiers.aci)
        let fileSize = OWSFileSystem.fileSize(ofPath: fileUrl.path)?.uint64Value ?? 0

        do {
            let result = try validateMessageBackup(key: key, purpose: backupPurpose, length: fileSize) {
                return try FileHandle(forReadingFrom: fileUrl)
            }
            if result.fields.count > 0 {
                throw BackupValidationError.unknownFields(result.fields)
            }
        } catch {
            switch error {
            case let validationError as MessageBackupValidationError:
                await errorPresenter.persistValidationError(validationError)
                Logger.error("Backup validation failed \(validationError.errorMessage)")
                throw BackupValidationError.validationFailed(
                    message: validationError.errorMessage,
                    unknownFields: validationError.unknownFields.fields
                )
            case SignalError.ioError(let description):
                Logger.error("Backup validation i/o error: \(description)")
                throw BackupValidationError.ioError(description)
            default:
                Logger.error("Backup validation unknown error: \(error)")
                throw BackupValidationError.unknownError
            }
        }
    }
}
