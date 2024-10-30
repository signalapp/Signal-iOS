//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public enum BackupValidationError: Error {
    case unknownFields([String])
    case validationFailed(message: String, unknownFields: [String])
    case ioError(String)
    case unknownError
}

public class MessageBackupManagerImpl: MessageBackupManager {
    private enum Constants {
        static let keyValueStoreCollectionName = "MessageBackupManager"
        static let keyValueStoreHasReservedBackupKey = "HasReservedBackupKey"

        static let supportedBackupVersion: UInt64 = 1
    }

    private class NotImplementedError: Error {}
    private class BackupError: Error {}
    private typealias LoggableErrorAndProto = MessageBackup.LoggableErrorAndProto

    private let accountDataArchiver: MessageBackupAccountDataArchiver
    private let attachmentDownloadManager: AttachmentDownloadManager
    private let attachmentUploadManager: AttachmentUploadManager
    private let backupAttachmentDownloadManager: BackupAttachmentDownloadManager
    private let backupAttachmentUploadManager: BackupAttachmentUploadManager
    private let backupRequestManager: MessageBackupRequestManager
    private let backupStickerPackDownloadStore: BackupStickerPackDownloadStore
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
    private let mrbkStore: MediaRootBackupKeyStore
    private let plaintextStreamProvider: MessageBackupPlaintextProtoStreamProvider
    private let postFrameRestoreActionManager: MessageBackupPostFrameRestoreActionManager
    private let releaseNotesRecipientArchiver: MessageBackupReleaseNotesRecipientArchiver
    private let stickerPackArchiver: MessageBackupStickerPackArchiver

    public init(
        accountDataArchiver: MessageBackupAccountDataArchiver,
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentUploadManager: AttachmentUploadManager,
        backupAttachmentDownloadManager: BackupAttachmentDownloadManager,
        backupAttachmentUploadManager: BackupAttachmentUploadManager,
        backupRequestManager: MessageBackupRequestManager,
        backupStickerPackDownloadStore: BackupStickerPackDownloadStore,
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
        kvStoreFactory: KeyValueStoreFactory,
        localRecipientArchiver: MessageBackupLocalRecipientArchiver,
        messageBackupKeyMaterial: MessageBackupKeyMaterial,
        mrbkStore: MediaRootBackupKeyStore,
        plaintextStreamProvider: MessageBackupPlaintextProtoStreamProvider,
        postFrameRestoreActionManager: MessageBackupPostFrameRestoreActionManager,
        releaseNotesRecipientArchiver: MessageBackupReleaseNotesRecipientArchiver,
        stickerPackArchiver: MessageBackupStickerPackArchiver
    ) {
        self.accountDataArchiver = accountDataArchiver
        self.attachmentDownloadManager = attachmentDownloadManager
        self.attachmentUploadManager = attachmentUploadManager
        self.backupAttachmentDownloadManager = backupAttachmentDownloadManager
        self.backupAttachmentUploadManager = backupAttachmentUploadManager
        self.backupRequestManager = backupRequestManager
        self.backupStickerPackDownloadStore = backupStickerPackDownloadStore
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
        self.kvStore = kvStoreFactory.keyValueStore(collection: Constants.keyValueStoreCollectionName)
        self.localRecipientArchiver = localRecipientArchiver
        self.messageBackupKeyMaterial = messageBackupKeyMaterial
        self.mrbkStore = mrbkStore
        self.plaintextStreamProvider = plaintextStreamProvider
        self.postFrameRestoreActionManager = postFrameRestoreActionManager
        self.releaseNotesRecipientArchiver = releaseNotesRecipientArchiver
        self.stickerPackArchiver = stickerPackArchiver
    }

    // MARK: - Remote backups

    /// Initialize Message Backups by reserving a backup ID and registering a public key used to sign backup auth credentials.
    /// These registration calls are safe to call multiple times, but to avoid unecessary network calls, the app will remember if
    /// backups have been successfully registered on this device and will no-op in this case.
    private func reserveAndRegister(localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws {
        guard db.read(block: { tx in
            return kvStore.getBool(Constants.keyValueStoreHasReservedBackupKey, transaction: tx) ?? false
        }).negated else {
            return
        }

        // Both reserveBackupId and registerBackupKeys can be called multiple times, so if
        // we think the backupId needs to be registered, register the public key at the same time.

        try await backupRequestManager.reserveBackupId(localAci: localIdentifiers.aci, auth: auth)

        let backupAuth = try await backupRequestManager.fetchBackupServiceAuth(localAci: localIdentifiers.aci, auth: auth)

        try await backupRequestManager.registerBackupKeys(auth: backupAuth)

        // Remember this device has registered for backups
        await db.awaitableWrite { [weak self] tx in
            self?.kvStore.setBool(true, key: Constants.keyValueStoreHasReservedBackupKey, transaction: tx)
        }
    }

    public func downloadEncryptedBackup(localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws -> URL {
        let backupAuth = try await backupRequestManager.fetchBackupServiceAuth(localAci: localIdentifiers.aci, auth: auth)
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
        let backupAuth = try await backupRequestManager.fetchBackupServiceAuth(localAci: localIdentifiers.aci, auth: auth)
        let form = try await backupRequestManager.fetchBackupUploadForm(auth: backupAuth)
        return try await attachmentUploadManager.uploadBackup(localUploadMetadata: metadata, form: form)
    }

    // MARK: - Export

    public func exportEncryptedBackup(
        localIdentifiers: LocalIdentifiers,
        mode: MessageBackup.EncryptionMode
    ) async throws -> Upload.EncryptedBackupUploadMetadata {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        await migrateAttachmentsBeforeBackup()

        let result: Result<Upload.EncryptedBackupUploadMetadata, Error>
        result = await db.awaitableWriteWithTxCompletion { tx in
            do {
                let outputStream: MessageBackupProtoOutputStream
                let metadataProvider: MessageBackup.ProtoStream.EncryptionMetadataProvider
                switch self.encryptedStreamProvider.openEncryptedOutputFileStream(
                    localAci: localIdentifiers.aci,
                    mode: mode,
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
                    tx: tx
                )

                let metadata = try metadataProvider()
                return .commit(Result.success(metadata))
            } catch let error {
                return .rollback(Result.failure(error))
            }
        }
        return try result.get()
    }

    public func exportPlaintextBackup(
        localIdentifiers: LocalIdentifiers
    ) async throws -> URL {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        await migrateAttachmentsBeforeBackup()

        let result: Result<URL, Error>
        result = await db.awaitableWriteWithTxCompletion { tx in
            do {
                let url = try self.databaseChangeObserver.disable(tx: tx) { tx in
                    let outputStream: MessageBackupProtoOutputStream
                    let fileUrl: URL
                    switch self.plaintextStreamProvider.openPlaintextOutputFileStream() {
                    case .success(let _outputStream, let _fileUrl):
                        outputStream = _outputStream
                        fileUrl = _fileUrl
                    case .unableToOpenFileStream:
                        throw OWSAssertionError("Unable to open output file stream!")
                    }

                    try self._exportBackup(
                        outputStream: outputStream,
                        localIdentifiers: localIdentifiers,
                        tx: tx
                    )

                    return fileUrl
                }
                return .commit(.success(url))
            } catch let error {
                return .rollback(.failure(error))
            }
        }
        return try result.get()
    }

    private func _exportBackup(
        outputStream stream: MessageBackupProtoOutputStream,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) throws {
        let startTimeMs = Date().ows_millisecondsSince1970
        var errors = [LoggableErrorAndProto]()
        defer {
            self.processErrors(errors: errors, tx: tx)
        }

        try writeHeader(stream: stream, tx: tx)

        let currentBackupAttachmentUploadEra: String?
        if MessageBackupMessageAttachmentArchiver.isFreeTierBackup() {
            currentBackupAttachmentUploadEra = nil
        } else {
            currentBackupAttachmentUploadEra = try MessageBackupMessageAttachmentArchiver.currentUploadEra()
        }

        let customChatColorContext = MessageBackup.CustomChatColorArchivingContext(
            currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
            backupAttachmentUploadManager: backupAttachmentUploadManager,
            tx: tx
        )
        let accountDataResult = accountDataArchiver.archiveAccountData(
            stream: stream,
            context: customChatColorContext
        )
        switch accountDataResult {
        case .success:
            break
        case .failure(let error):
            errors.append(LoggableErrorAndProto(error: error))
            throw OWSAssertionError("Failed to archive account data")
        }

        let localRecipientResult = localRecipientArchiver.archiveLocalRecipient(
            stream: stream
        )
        let localRecipientId: MessageBackup.RecipientId
        switch localRecipientResult {
        case .success(let success):
            localRecipientId = success
        case .failure(let error):
            errors.append(LoggableErrorAndProto(error: error))
            throw OWSAssertionError("Failed to archive local recipient!")
        }

        let recipientArchivingContext = MessageBackup.RecipientArchivingContext(
            currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
            backupAttachmentUploadManager: backupAttachmentUploadManager,
            localIdentifiers: localIdentifiers,
            localRecipientId: localRecipientId,
            tx: tx
        )

        switch releaseNotesRecipientArchiver.archiveReleaseNotesRecipient(
            stream: stream,
            context: recipientArchivingContext
        ) {
        case .success:
            break
        case .failure(let error):
            errors.append(LoggableErrorAndProto(error: error))
            throw OWSAssertionError("Failed to archive release notes channel!")
        }

        switch contactRecipientArchiver.archiveAllContactRecipients(
            stream: stream,
            context: recipientArchivingContext
        ) {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error))
            throw BackupError()
        }

        switch groupRecipientArchiver.archiveAllGroupRecipients(
            stream: stream,
            context: recipientArchivingContext
        ) {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error))
            throw BackupError()
        }

        switch distributionListRecipientArchiver.archiveAllDistributionListRecipients(
            stream: stream,
            context: recipientArchivingContext
        ) {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error))
            throw BackupError()
        }

        // TODO: [Backups] Archive call link recipients.

        let chatArchivingContext = MessageBackup.ChatArchivingContext(
            currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
            backupAttachmentUploadManager: backupAttachmentUploadManager,
            customChatColorContext: customChatColorContext,
            recipientContext: recipientArchivingContext,
            tx: tx
        )
        let chatArchiveResult = chatArchiver.archiveChats(
            stream: stream,
            context: chatArchivingContext
        )
        switch chatArchiveResult {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error))
            throw BackupError()
        }

        let chatItemArchiveResult = chatItemArchiver.archiveInteractions(
            stream: stream,
            context: chatArchivingContext
        )
        switch chatItemArchiveResult {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error))
            throw BackupError()
        }

        let archivingContext = MessageBackup.ArchivingContext(
            currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
            backupAttachmentUploadManager: backupAttachmentUploadManager,
            tx: tx
        )
        let stickerPackArchiveResult = stickerPackArchiver.archiveStickerPacks(
            stream: stream,
            context: archivingContext
        )
        switch stickerPackArchiveResult {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            errors.append(contentsOf: partialFailures.map { LoggableErrorAndProto(error: $0) })
        case .completeFailure(let error):
            errors.append(LoggableErrorAndProto(error: error))
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

    private func writeHeader(stream: MessageBackupProtoOutputStream, tx: DBWriteTransaction) throws {
        var backupInfo = BackupProto_BackupInfo()
        backupInfo.version = Constants.supportedBackupVersion
        backupInfo.backupTimeMs = dateProvider().ows_millisecondsSince1970

        backupInfo.mediaRootBackupKey = mrbkStore.getOrGenerateMediaRootBackupKey(tx: tx)

        switch stream.writeHeader(backupInfo) {
        case .success:
            break
        case .fileIOError(let error), .protoSerializationError(let error):
            throw error
        }
    }

    // MARK: - Import

    public func importEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        mode: MessageBackup.EncryptionMode
    ) async throws {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        await migrateAttachmentsBeforeBackup()

        let result: Result<Void, Error>
        result = await db.awaitableWriteWithTxCompletion { tx in
            do {
                try self.databaseChangeObserver.disable(tx: tx) { tx in
                    let inputStream: MessageBackupProtoInputStream
                    switch self.encryptedStreamProvider.openEncryptedInputFileStream(
                        fileUrl: fileUrl,
                        localAci: localIdentifiers.aci,
                        mode: mode,
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

                    try self._importBackup(
                        inputStream: inputStream,
                        localIdentifiers: localIdentifiers,
                        tx: tx
                    )
                }
                return .commit(.success(()))
            } catch let error {
                return .rollback(.failure(error))
            }
        }
        return try result.get()
    }

    public func importPlaintextBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers
    ) async throws {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        await migrateAttachmentsBeforeBackup()

        let result: Result<Void, Error>
        result = await db.awaitableWriteWithTxCompletion { tx in
            do {
                try self.databaseChangeObserver.disable(tx: tx) { tx in
                    let inputStream: MessageBackupProtoInputStream
                    switch self.plaintextStreamProvider.openPlaintextInputFileStream(
                        fileUrl: fileUrl
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

                    try self._importBackup(
                        inputStream: inputStream,
                        localIdentifiers: localIdentifiers,
                        tx: tx
                    )
                }
                return .commit(.success(()))
            } catch let error {
                return .rollback(.failure(error))
            }
        }
        return try result.get()
    }

    private func _importBackup(
        inputStream stream: MessageBackupProtoInputStream,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) throws {
        let startTimeMs = Date().ows_millisecondsSince1970

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
            frameErrors.append(LoggableErrorAndProto(error: MessageBackup.RestoreFrameError.restoreFrameError(
                .invalidProtoData(.missingBackupInfoHeader),
                MessageBackup.BackupInfoId()
            )))
            throw error
        }

        Logger.info("Reading backup with version: \(backupInfo.version) backed up at \(backupInfo.backupTimeMs)")

        guard backupInfo.version == Constants.supportedBackupVersion else {
            frameErrors.append(LoggableErrorAndProto(
                error: MessageBackup.RestoreFrameError.restoreFrameError(
                    .invalidProtoData(.unsupportedBackupInfoVersion),
                    MessageBackup.BackupInfoId()
                ),
                protoFrame: backupInfo
            ))
            throw BackupError()
        }
        do {
            try mrbkStore.setMediaRootBackupKey(fromRestoredBackup: backupInfo, tx: tx)
        } catch {
            frameErrors.append(LoggableErrorAndProto(
                error: MessageBackup.RestoreFrameError.restoreFrameError(
                    .invalidProtoData(.invalidMediaRootBackupKey),
                    MessageBackup.BackupInfoId()
                ),
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
                case .callLink(_):
                    // TODO: [Backups] Restore call link recipients.
                    recipientResult = .failure([.restoreFrameError(.unimplemented, recipient.recipientId)])
                }

                switch recipientResult {
                case .success:
                    continue
                case .partialRestore(let errors):
                    frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, protoFrame: recipient) })
                case .failure(let errors):
                    frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, protoFrame: recipient) })
                    throw BackupError()
                }
            case .chat(let chat):
                let chatResult = chatArchiver.restore(
                    chat,
                    context: contexts.chat
                )
                switch chatResult {
                case .success:
                    continue
                case .partialRestore(let errors):
                    frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, protoFrame: chat) })
                case .failure(let errors):
                    frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, protoFrame: chat) })
                    throw BackupError()
                }
            case .chatItem(let chatItem):
                let chatItemResult = chatItemArchiver.restore(
                    chatItem,
                    context: contexts.chatItem
                )
                switch chatItemResult {
                case .success:
                    continue
                case .partialRestore(let errors):
                    frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, protoFrame: chatItem) })
                case .failure(let errors):
                    frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, protoFrame: chatItem) })
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
                    continue
                case .partialRestore(let errors):
                    frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, protoFrame: backupProtoAccountData) })
                case .failure(let errors):
                    frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, protoFrame: backupProtoAccountData) })
                    throw BackupError()
                }
            case .stickerPack(let backupProtoStickerPack):
                let stickerPackResult = stickerPackArchiver.restore(
                    backupProtoStickerPack,
                    context: MessageBackup.RestoringContext(tx: tx)
                )
                switch stickerPackResult {
                case .success:
                    continue
                case .partialRestore(let errors):
                    frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, protoFrame: backupProtoStickerPack) })
                case .failure(let errors):
                    frameErrors.append(contentsOf: errors.map { LoggableErrorAndProto(error: $0, protoFrame: backupProtoStickerPack) })
                    throw BackupError()
                }
            case .adHocCall(let backupProtoAdHocCall):
                // TODO: [Backups] Restore ad-hoc calls.
                frameErrors.append(LoggableErrorAndProto(error: MessageBackup.RestoreFrameError.restoreFrameError(
                    .unimplemented,
                    MessageBackup.AdHocCallId(
                        backupProtoAdHocCall.callID,
                        recipientId: backupProtoAdHocCall.recipientID
                    )
                )))
            case nil:
                if hasMoreFrames {
                    owsFailDebug("Frame missing item!")
                    frameErrors.append(LoggableErrorAndProto(error: MessageBackup.RestoreFrameError.restoreFrameError(
                        .invalidProtoData(.frameMissingItem),
                        MessageBackup.EmptyFrameId.shared
                    )))
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
        Logger.info("Imported \(stream.numberOfReadFrames) in \(endTimeMs - startTimeMs)ms")
    }

    // MARK: -

    private func processErrors(
        errors: [LoggableErrorAndProto],
        tx: DBWriteTransaction
    ) {
        let collapsedErrors = MessageBackup.collapse(errors)
        collapsedErrors.forEach { $0.log() }
        errorPresenter.persistErrors(collapsedErrors, tx: tx)
    }

    /// TSAttachments must be migrated to v2 Attachments before we can create or restore backups.
    /// Normally this migration happens in the background; force it to run and finish now.
    private func migrateAttachmentsBeforeBackup() async {
        await incrementalTSAttachmentMigrator.runUntilFinished()
    }

    public func validateEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        mode: MessageBackup.EncryptionMode
    ) async throws {
        let key = try db.read { tx in
            return try messageBackupKeyMaterial.messageBackupKey(localAci: localIdentifiers.aci, mode: mode, tx: tx)
        }
        let fileSize = OWSFileSystem.fileSize(ofPath: fileUrl.path)?.uint64Value ?? 0

        do {
            let result = try validateMessageBackup(key: key, purpose: .remoteBackup, length: fileSize) {
                return try FileHandle(forReadingFrom: fileUrl)
            }
            if result.fields.count > 0 {
                throw BackupValidationError.unknownFields(result.fields)
            }
        } catch {
            switch error {
            case let validationError as MessageBackupValidationError:
                throw BackupValidationError.validationFailed(
                    message: validationError.errorMessage,
                    unknownFields: validationError.unknownFields.fields
                )
            case SignalError.ioError(let description):
                throw BackupValidationError.ioError(description)
            default:
                throw BackupValidationError.unknownError
            }
        }
    }
}
