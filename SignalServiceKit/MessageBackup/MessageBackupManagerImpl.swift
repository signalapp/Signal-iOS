//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

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
    }

    private class NotImplementedError: Error {}
    private class BackupError: Error {}
    private typealias LoggableErrorAndProto = MessageBackup.LoggableErrorAndProto

    private let accountDataArchiver: MessageBackupAccountDataArchiver
    private let appVersion: AppVersion
    private let attachmentDownloadManager: AttachmentDownloadManager
    private let attachmentUploadManager: AttachmentUploadManager
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
    private let db: any DB
    private let disappearingMessagesJob: OWSDisappearingMessagesJob
    private let distributionListRecipientArchiver: MessageBackupDistributionListRecipientArchiver
    private let encryptedStreamProvider: MessageBackupEncryptedProtoStreamProvider
    private let errorPresenter: MessageBackupErrorPresenter
    private let fullTextSearchIndexer: MessageBackupFullTextSearchIndexer
    private let groupRecipientArchiver: MessageBackupGroupRecipientArchiver
    private let incrementalTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator
    private let kvStore: KeyValueStore
    private let localRecipientArchiver: MessageBackupLocalRecipientArchiver
    private let messageBackupKeyMaterial: MessageBackupKeyMaterial
    private let messagePipelineSupervisor: MessagePipelineSupervisor
    private let mrbkStore: MediaRootBackupKeyStore
    private let plaintextStreamProvider: MessageBackupPlaintextProtoStreamProvider
    private let postFrameRestoreActionManager: MessageBackupPostFrameRestoreActionManager
    private let releaseNotesRecipientArchiver: MessageBackupReleaseNotesRecipientArchiver
    private let stickerPackArchiver: MessageBackupStickerPackArchiver
    private let adHocCallArchiver: MessageBackupAdHocCallArchiver

    public init(
        accountDataArchiver: MessageBackupAccountDataArchiver,
        appVersion: AppVersion,
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentUploadManager: AttachmentUploadManager,
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
        db: any DB,
        disappearingMessagesJob: OWSDisappearingMessagesJob,
        distributionListRecipientArchiver: MessageBackupDistributionListRecipientArchiver,
        encryptedStreamProvider: MessageBackupEncryptedProtoStreamProvider,
        errorPresenter: MessageBackupErrorPresenter,
        fullTextSearchIndexer: MessageBackupFullTextSearchIndexer,
        groupRecipientArchiver: MessageBackupGroupRecipientArchiver,
        incrementalTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator,
        localRecipientArchiver: MessageBackupLocalRecipientArchiver,
        messageBackupKeyMaterial: MessageBackupKeyMaterial,
        messagePipelineSupervisor: MessagePipelineSupervisor,
        mrbkStore: MediaRootBackupKeyStore,
        plaintextStreamProvider: MessageBackupPlaintextProtoStreamProvider,
        postFrameRestoreActionManager: MessageBackupPostFrameRestoreActionManager,
        releaseNotesRecipientArchiver: MessageBackupReleaseNotesRecipientArchiver,
        stickerPackArchiver: MessageBackupStickerPackArchiver,
        adHocCallArchiver: MessageBackupAdHocCallArchiver
    ) {
        self.accountDataArchiver = accountDataArchiver
        self.appVersion = appVersion
        self.attachmentDownloadManager = attachmentDownloadManager
        self.attachmentUploadManager = attachmentUploadManager
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
        self.db = db
        self.disappearingMessagesJob = disappearingMessagesJob
        self.distributionListRecipientArchiver = distributionListRecipientArchiver
        self.encryptedStreamProvider = encryptedStreamProvider
        self.errorPresenter = errorPresenter
        self.fullTextSearchIndexer = fullTextSearchIndexer
        self.groupRecipientArchiver = groupRecipientArchiver
        self.incrementalTSAttachmentMigrator = incrementalTSAttachmentMigrator
        self.kvStore = KeyValueStore(collection: Constants.keyValueStoreCollectionName)
        self.localRecipientArchiver = localRecipientArchiver
        self.messageBackupKeyMaterial = messageBackupKeyMaterial
        self.messagePipelineSupervisor = messagePipelineSupervisor
        self.mrbkStore = mrbkStore
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
        progress: OWSProgressSink?
    ) async throws -> Upload.EncryptedBackupUploadMetadata {
        guard
            FeatureFlags.messageBackupFileAlpha
            || FeatureFlags.linkAndSync
        else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        await migrateAttachmentsBeforeBackup()

        let handle = messagePipelineSupervisor.suspendMessageProcessing(for: .messageBackup)
        defer {
            handle.invalidate()
        }

        let progress = try await MessageBackupExportProgress.prepare(sink: progress, db: db)

        let currentAppVersion = appVersion.currentAppVersion
        let firstAppVersion = appVersion.firstBackupAppVersion ?? appVersion.firstAppVersion

        let result: Result<Upload.EncryptedBackupUploadMetadata, Error>
        result = await db.awaitableWriteWithTxCompletion { tx in
            do {
                return try Bench(
                    title: "Export encryped backup",
                    memorySamplerRatio: FeatureFlags.backupsMemorySamplerRatio,
                    logInProduction: false
                ) { memorySampler in
                    let outputStream: MessageBackupProtoOutputStream
                    let metadataProvider: MessageBackup.ProtoStream.EncryptionMetadataProvider
                    switch self.encryptedStreamProvider.openEncryptedOutputFileStream(
                        localAci: localIdentifiers.aci,
                        backupKey: backupKey,
                        progress: progress,
                        memorySampler: memorySampler,
                        tx: tx
                    ) {
                    case let .success(_outputStream, _metadataProvider):
                        outputStream = _outputStream
                        metadataProvider = _metadataProvider
                    case .unableToOpenFileStream:
                        throw OWSAssertionError("Unable to open output stream")
                    }

                    try self._exportBackup(
                        outputStream: outputStream,
                        localIdentifiers: localIdentifiers,
                        backupPurpose: backupPurpose,
                        currentAppVersion: currentAppVersion,
                        firstAppVersion: firstAppVersion,
                        tx: tx
                    )

                    let metadata = try metadataProvider()
                    return .commit(Result.success(metadata))
                }
            } catch let error {
                return .rollback(Result.failure(error))
            }
        }
        return try result.get()
    }

    public func exportPlaintextBackup(
        localIdentifiers: LocalIdentifiers,
        backupPurpose: MessageBackupPurpose,
        progress: OWSProgressSink?
    ) async throws -> URL {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        await migrateAttachmentsBeforeBackup()

        let handle = messagePipelineSupervisor.suspendMessageProcessing(for: .messageBackup)
        defer {
            handle.invalidate()
        }

        let progress = try await MessageBackupExportProgress.prepare(sink: progress, db: db)

        let currentAppVersion = appVersion.currentAppVersion
        let firstAppVersion = appVersion.firstBackupAppVersion ?? appVersion.firstAppVersion

        let result: Result<URL, Error>
        result = await db.awaitableWriteWithTxCompletion { tx in
            do {
                return try Bench(
                    title: "Export plaintext backup",
                    memorySamplerRatio: FeatureFlags.backupsMemorySamplerRatio,
                    logInProduction: false
                ) { memorySampler in
                    let url = try self.databaseChangeObserver.disable(tx: tx) { tx in
                        let outputStream: MessageBackupProtoOutputStream
                        let fileUrl: URL
                        switch self.plaintextStreamProvider.openPlaintextOutputFileStream(
                            progress: progress,
                            memorySampler: memorySampler
                        ) {
                        case .success(let _outputStream, let _fileUrl):
                            outputStream = _outputStream
                            fileUrl = _fileUrl
                        case .unableToOpenFileStream:
                            throw OWSAssertionError("Unable to open output file stream!")
                        }

                        try self._exportBackup(
                            outputStream: outputStream,
                            localIdentifiers: localIdentifiers,
                            backupPurpose: backupPurpose,
                            currentAppVersion: currentAppVersion,
                            firstAppVersion: firstAppVersion,
                            tx: tx
                        )

                        return fileUrl
                    }
                    return .commit(.success(url))
                }
            } catch let error {
                return .rollback(.failure(error))
            }
        }
        return try result.get()
    }

    private func _exportBackup(
        outputStream stream: MessageBackupProtoOutputStream,
        localIdentifiers: LocalIdentifiers,
        backupPurpose: MessageBackupPurpose,
        currentAppVersion: String,
        firstAppVersion: String,
        tx: DBWriteTransaction
    ) throws {
        let startTimeMs = Date().ows_millisecondsSince1970
        var errors = [LoggableErrorAndProto]()
        defer {
            self.processErrors(errors: errors, tx: tx)
        }

        try autoreleasepool {
            try writeHeader(
                stream: stream,
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
                errors.append(LoggableErrorAndProto(error: error, wasFatal: true))
                throw OWSAssertionError("Failed to archive account data")
            }
        }
        try Task.checkCancellation()

        let localRecipientResult = localRecipientArchiver.archiveLocalRecipient(
            stream: stream
        )

        try Task.checkCancellation()

        let localRecipientId: MessageBackup.RecipientId
        switch localRecipientResult {
        case .success(let success):
            localRecipientId = success
        case .failure(let error):
            errors.append(LoggableErrorAndProto(error: error, wasFatal: true))
            throw OWSAssertionError("Failed to archive local recipient!")
        }

        let recipientArchivingContext = MessageBackup.RecipientArchivingContext(
            backupPurpose: backupPurpose,
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
                errors.append(LoggableErrorAndProto(error: error, wasFatal: true))
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
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFatal: false) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error, wasFatal: true))
            throw BackupError()
        }

        switch try groupRecipientArchiver.archiveAllGroupRecipients(
            stream: stream,
            context: recipientArchivingContext
        ) {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFatal: false) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error, wasFatal: true))
            throw BackupError()
        }

        switch try distributionListRecipientArchiver.archiveAllDistributionListRecipients(
            stream: stream,
            context: recipientArchivingContext
        ) {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFatal: false) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error, wasFatal: true))
            throw BackupError()
        }

        switch try callLinkRecipientArchiver.archiveAllCallLinkRecipients(
            stream: stream,
            context: recipientArchivingContext
        ) {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFatal: false) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error, wasFatal: true))
            throw BackupError()
        }

        let chatArchivingContext = MessageBackup.ChatArchivingContext(
            backupPurpose: backupPurpose,
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
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFatal: false) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error, wasFatal: true))
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
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFatal: false) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error, wasFatal: true))
            throw BackupError()
        }

        let archivingContext = MessageBackup.ArchivingContext(
            backupPurpose: backupPurpose,
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
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFatal: false) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error, wasFatal: true))
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
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0, wasFatal: false) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error, wasFatal: true))
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

        let endTimeMs = Date().ows_millisecondsSince1970
        Logger.info("Exported \(stream.numberOfWrittenFrames) in \(endTimeMs - startTimeMs)ms")
    }

    private func writeHeader(
        stream: MessageBackupProtoOutputStream,
        currentAppVersion: String,
        firstAppVersion: String,
        tx: DBWriteTransaction
    ) throws {
        var backupInfo = BackupProto_BackupInfo()
        backupInfo.version = Constants.supportedBackupVersion
        backupInfo.backupTimeMs = dateProvider().ows_millisecondsSince1970

        backupInfo.mediaRootBackupKey = mrbkStore.getOrGenerateMediaRootBackupKey(tx: tx)

        backupInfo.currentAppVersion = currentAppVersion
        backupInfo.firstAppVersion = firstAppVersion

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
        progress: OWSProgressSink?
    ) async throws {
        guard FeatureFlags.messageBackupFileAlpha || FeatureFlags.linkAndSync else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        await migrateAttachmentsBeforeBackup()

        let handle = messagePipelineSupervisor.suspendMessageProcessing(for: .messageBackup)
        defer {
            handle.invalidate()
        }

        let progress = try await MessageBackupImportProgress.prepare(sink: progress, fileUrl: fileUrl)

        let result: Result<BackupProto_BackupInfo, Error>
        result = await db.awaitableWriteWithTxCompletion { tx in
            do {
                return try Bench(
                    title: "Import encrypted backup",
                    memorySamplerRatio: FeatureFlags.backupsMemorySamplerRatio,
                    logInProduction: false
                ) { memorySampler in
                    let backupInfo = try self.databaseChangeObserver.disable(tx: tx) { tx in
                        let inputStream: MessageBackupProtoInputStream
                        switch self.encryptedStreamProvider.openEncryptedInputFileStream(
                            fileUrl: fileUrl,
                            localAci: localIdentifiers.aci,
                            backupKey: backupKey,
                            progress: progress,
                            memorySampler: memorySampler,
                            tx: tx
                        ) {
                        case .success(let protoStream, _):
                            inputStream = protoStream
                        case .fileNotFound:
                            throw OWSAssertionError("File not found!")
                        case .unableToOpenFileStream:
                            throw OWSAssertionError("Unable to open input stream!")
                        case .hmacValidationFailedOnEncryptedFile:
                            throw OWSAssertionError("HMAC validation failed on encrypted file!")
                        }

                        return try self._importBackup(
                            inputStream: inputStream,
                            localIdentifiers: localIdentifiers,
                            tx: tx
                        )
                    }
                    return .commit(.success(backupInfo))
                }
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

    public func importPlaintextBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        progress: OWSProgressSink?
    ) async throws {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        await migrateAttachmentsBeforeBackup()

        let handle = messagePipelineSupervisor.suspendMessageProcessing(for: .messageBackup)
        defer {
            handle.invalidate()
        }

        let progress = try await MessageBackupImportProgress.prepare(sink: progress, fileUrl: fileUrl)

        let result: Result<BackupProto_BackupInfo, Error>
        result = await db.awaitableWriteWithTxCompletion { tx in
            do {
                return try Bench(
                    title: "Import plaintext backup",
                    memorySamplerRatio: FeatureFlags.backupsMemorySamplerRatio,
                    logInProduction: false
                ) { memorySampler in
                    let backupInfo = try self.databaseChangeObserver.disable(tx: tx) { tx in
                        let inputStream: MessageBackupProtoInputStream
                        switch self.plaintextStreamProvider.openPlaintextInputFileStream(
                            fileUrl: fileUrl,
                            progress: progress,
                            memorySampler: memorySampler
                        ) {
                        case .success(let protoStream, _):
                            inputStream = protoStream
                        case .fileNotFound:
                            throw OWSAssertionError("File not found!")
                        case .unableToOpenFileStream:
                            throw OWSAssertionError("Unable to open input stream!")
                        case .hmacValidationFailedOnEncryptedFile:
                            throw OWSAssertionError("HMAC validation failed: how did this happen for a plaintext backup?")
                        }

                        return try self._importBackup(
                            inputStream: inputStream,
                            localIdentifiers: localIdentifiers,
                            tx: tx
                        )
                    }
                    return .commit(.success(backupInfo))
                }
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
        tx: DBWriteTransaction
    ) throws -> BackupProto_BackupInfo {
        let startTimeMs = Date().ows_millisecondsSince1970

        guard !hasRestoredFromBackup(tx: tx) else {
            throw OWSAssertionError("Restoring from backup twice!")
        }

        var frameErrors = [LoggableErrorAndProto]()
        defer {
            self.processErrors(errors: frameErrors, tx: tx)
        }

        let backupInfo: BackupProto_BackupInfo
        var hasMoreFrames = false
        switch stream.readHeader() {
        case .success(let header, let moreBytesAvailable):
            backupInfo = header
            hasMoreFrames = moreBytesAvailable
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
                wasFatal: true
            ))
            throw error
        }

        Logger.info("Reading backup with version: \(backupInfo.version) backed up at \(backupInfo.backupTimeMs)")

        guard backupInfo.version == Constants.supportedBackupVersion else {
            frameErrors.append(LoggableErrorAndProto(
                error: MessageBackup.RestoreFrameError.restoreFrameError(
                    .invalidProtoData(.unsupportedBackupInfoVersion),
                    MessageBackup.BackupInfoId()
                ),
                wasFatal: true,
                protoFrame: backupInfo
            ))
            throw BackupImportError.unsupportedVersion
        }
        do {
            try mrbkStore.setMediaRootBackupKey(fromRestoredBackup: backupInfo, tx: tx)
        } catch {
            frameErrors.append(LoggableErrorAndProto(
                error: MessageBackup.RestoreFrameError.restoreFrameError(
                    .invalidProtoData(.invalidMediaRootBackupKey),
                    MessageBackup.BackupInfoId()
                ),
                wasFatal: true,
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
                case .invalidByteLengthDelimiter:
                    throw OWSAssertionError("invalid byte length delimiter on header")
                case .emptyFinalFrame:
                    frame = nil
                    hasMoreFrames = false
                case .protoDeserializationError(let error):
                    // fail the whole thing if we fail to deserialize one frame
                    owsFailDebug("Failed to deserialize proto frame!")
                    throw error
                }

                switch frame?.item {
                case .recipient(let recipient):
                    let recipientResult: MessageBackup.RestoreFrameResult<MessageBackup.RecipientId>
                    switch recipient.destination {
                    case nil:
                        recipientResult = .failure([.restoreFrameError(
                            .invalidProtoData(.recipientMissingDestination),
                            recipient.recipientId
                        )])
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
                    case .partialRestore(let errors):
                        frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFatal: false, protoFrame: recipient) })
                    case .failure(let errors):
                        frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFatal: true, protoFrame: recipient) })
                        throw BackupError()
                    }
                case .chat(let chat):
                    let chatResult = chatArchiver.restore(
                        chat,
                        context: contexts.chat
                    )
                    switch chatResult {
                    case .success:
                        return
                    case .partialRestore(let errors):
                        frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFatal: false, protoFrame: chat) })
                    case .failure(let errors):
                        frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFatal: true, protoFrame: chat) })
                        throw BackupError()
                    }
                case .chatItem(let chatItem):
                    let chatItemResult = chatItemArchiver.restore(
                        chatItem,
                        context: contexts.chatItem
                    )
                    switch chatItemResult {
                    case .success:
                        return
                    case .partialRestore(let errors):
                        frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFatal: false, protoFrame: chatItem) })
                    case .failure(let errors):
                        frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFatal: true, protoFrame: chatItem) })
                        throw BackupError()
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
                    case .partialRestore(let errors):
                        frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFatal: false, protoFrame: backupProtoAccountData) })
                    case .failure(let errors):
                        frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFatal: true, protoFrame: backupProtoAccountData) })
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
                    case .partialRestore(let errors):
                        frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFatal: false, protoFrame: backupProtoStickerPack) })
                    case .failure(let errors):
                        frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFatal: true, protoFrame: backupProtoStickerPack) })
                        throw BackupError()
                    }
                case .adHocCall(let backupProtoAdHocCall):
                    let adHocCallResult = adHocCallArchiver.restore(
                        backupProtoAdHocCall,
                        context: contexts.chatItem
                    )
                    switch adHocCallResult {
                    case .success:
                        return
                    case .partialRestore(let errors):
                        frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFatal: false, protoFrame: backupProtoAdHocCall) })
                    case .failure(let errors):
                        frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, wasFatal: true, protoFrame: backupProtoAdHocCall) })
                        throw BackupError()
                    }
                case .notificationProfile:
                    // Notification profiles are unsupported on iOS and
                    // we do not even round trip them per spec.
                    break
                case .chatFolder:
                    // Chat folders are unsupported on iOS and
                    // we do not even round trip them per spec.
                    break
                case nil:
                    if hasMoreFrames {
                        owsFailDebug("Frame missing item!")
                        frameErrors.append(LoggableErrorAndProto(
                            error: MessageBackup.RestoreFrameError.restoreFrameError(
                                .invalidProtoData(.frameMissingItem),
                                MessageBackup.EmptyFrameId.shared
                            ),
                            wasFatal: false
                        ))
                    }
                }
            }
        }

        stream.closeFileStream()

        /// Take any necessary post-frame-restore actions.
        try postFrameRestoreActionManager.performPostFrameRestoreActions(
            recipientActions: contexts.recipient.postFrameRestoreActions,
            chatActions: contexts.chat.postFrameRestoreActions,
            chatItemContext: contexts.chatItem
        )

        // Index threads synchronously
        fullTextSearchIndexer.indexThreads(tx: tx)
        // Schedule message indexing asynchronously
        try fullTextSearchIndexer.scheduleMessagesJob(tx: tx)

        tx.addAsyncCompletion(on: DispatchQueue.global()) { [backupAttachmentDownloadManager, disappearingMessagesJob] in
            Task {
                // Enqueue downloads for all the attachments.
                try await backupAttachmentDownloadManager.restoreAttachmentsIfNeeded()
            }
            // Start ticking down for disappearing messages.
            disappearingMessagesJob.startIfNecessary()
        }

        let endTimeMs = Date().ows_millisecondsSince1970
        Logger.info("Imported backup generated at \(backupInfo.backupTimeMs)")
        Logger.info("Backup version \(backupInfo.version)")
        Logger.info("Backup app version: \(backupInfo.currentAppVersion)")
        Logger.info("Backup first app version \(backupInfo.firstAppVersion)")
        Logger.info("Imported \(stream.numberOfReadFrames) in \(endTimeMs - startTimeMs)ms")

        kvStore.setBool(true, key: Constants.keyValueStoreHasRestoredBackupKey, transaction: tx)

        return backupInfo
    }

    // MARK: -

    private func processErrors(
        errors: [LoggableErrorAndProto],
        tx: DBWriteTransaction
    ) {
        let collapsedErrors = MessageBackup.collapse(errors)
        var maxLogLevel = -1
        collapsedErrors.forEach { collapsedError in
            collapsedError.log()
            maxLogLevel = max(maxLogLevel, collapsedError.logLevel.rawValue)
        }
        // Only present errors if some error rises above warning.
        // (But if one does, present _all_ errors).
        if maxLogLevel > MessageBackup.LogLevel.warning.rawValue {
            errorPresenter.persistErrors(collapsedErrors, tx: tx)
        }
    }

    /// TSAttachments must be migrated to v2 Attachments before we can create or restore backups.
    /// Normally this migration happens in the background; force it to run and finish now.
    private func migrateAttachmentsBeforeBackup() async {
        await incrementalTSAttachmentMigrator.runUntilFinished(ignorePastFailures: true)
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
