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
    private class BackupVersionNotSupportedError: Error {}

    private let accountDataArchiver: MessageBackupAccountDataArchiver
    private let attachmentDownloadManager: AttachmentDownloadManager
    private let attachmentUploadManager: AttachmentUploadManager
    private let backupRequestManager: MessageBackupRequestManager
    private let chatArchiver: MessageBackupChatArchiver
    private let chatItemArchiver: MessageBackupChatItemArchiver
    private let contactRecipientArchiver: MessageBackupContactRecipientArchiver
    private let dateProvider: DateProvider
    private let db: DB
    private let distributionListRecipientArchiver: MessageBackupDistributionListRecipientArchiver
    private let groupRecipientArchiver: MessageBackupGroupRecipientArchiver
    private let incrementalTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator
    private let kvStore: KeyValueStore
    private let localRecipientArchiver: MessageBackupLocalRecipientArchiver
    private let messageBackupKeyMaterial: MessageBackupKeyMaterial
    private let releaseNotesRecipientArchiver: MessageBackupReleaseNotesRecipientArchiver
    private let streamProvider: MessageBackupProtoStreamProvider

    public init(
        accountDataArchiver: MessageBackupAccountDataArchiver,
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentUploadManager: AttachmentUploadManager,
        backupRequestManager: MessageBackupRequestManager,
        chatArchiver: MessageBackupChatArchiver,
        chatItemArchiver: MessageBackupChatItemArchiver,
        contactRecipientArchiver: MessageBackupContactRecipientArchiver,
        dateProvider: @escaping DateProvider,
        db: DB,
        distributionListRecipientArchiver: MessageBackupDistributionListRecipientArchiver,
        groupRecipientArchiver: MessageBackupGroupRecipientArchiver,
        incrementalTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator,
        kvStoreFactory: KeyValueStoreFactory,
        localRecipientArchiver: MessageBackupLocalRecipientArchiver,
        messageBackupKeyMaterial: MessageBackupKeyMaterial,
        releaseNotesRecipientArchiver: MessageBackupReleaseNotesRecipientArchiver,
        streamProvider: MessageBackupProtoStreamProvider
    ) {
        self.accountDataArchiver = accountDataArchiver
        self.attachmentDownloadManager = attachmentDownloadManager
        self.attachmentUploadManager = attachmentUploadManager
        self.backupRequestManager = backupRequestManager
        self.chatArchiver = chatArchiver
        self.chatItemArchiver = chatItemArchiver
        self.contactRecipientArchiver = contactRecipientArchiver
        self.dateProvider = dateProvider
        self.db = db
        self.distributionListRecipientArchiver = distributionListRecipientArchiver
        self.groupRecipientArchiver = groupRecipientArchiver
        self.incrementalTSAttachmentMigrator = incrementalTSAttachmentMigrator
        self.kvStore = kvStoreFactory.keyValueStore(collection: Constants.keyValueStoreCollectionName)
        self.localRecipientArchiver = localRecipientArchiver
        self.messageBackupKeyMaterial = messageBackupKeyMaterial
        self.releaseNotesRecipientArchiver = releaseNotesRecipientArchiver
        self.streamProvider = streamProvider
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
        let info = try await backupRequestManager.fetchBackupInfo(auth: backupAuth)
        let credentials = try await backupRequestManager.fetchCDNReadCredentials(cdn: info.cdn, auth: backupAuth)
        let tmpFileUrl = try await attachmentDownloadManager.downloadBackup(
            metadata: info,
            authHeaders: credentials.headers
        ).awaitable()

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
        localIdentifiers: LocalIdentifiers
    ) async throws -> Upload.EncryptedBackupUploadMetadata {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        await migrateAttachmentsBeforeBackup()

        return try await db.awaitableWrite { tx in
            let outputStream: MessageBackupProtoOutputStream
            let metadataProvider: MessageBackup.ProtoStream.EncryptionMetadataProvider
            switch self.streamProvider.openEncryptedOutputFileStream(
                localAci: localIdentifiers.aci,
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

            return try metadataProvider()
        }
    }

    public func exportPlaintextBackup(
        localIdentifiers: LocalIdentifiers
    ) async throws -> URL {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        await migrateAttachmentsBeforeBackup()

        return try await db.awaitableWrite { tx in
            let outputStream: MessageBackupProtoOutputStream
            let fileUrl: URL
            switch self.streamProvider.openPlaintextOutputFileStream() {
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
    }

    private func _exportBackup(
        outputStream stream: MessageBackupProtoOutputStream,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) throws {
        try writeHeader(stream: stream, tx: tx)

        let accountDataResult = accountDataArchiver.archiveAccountData(stream: stream, tx: tx)
        switch accountDataResult {
        case .success:
            break
        case .failure(let error):
            MessageBackup.log([error])
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
            MessageBackup.log([error])
            throw OWSAssertionError("Failed to archive local recipient!")
        }

        let recipientArchivingContext = MessageBackup.RecipientArchivingContext(
            localIdentifiers: localIdentifiers,
            localRecipientId: localRecipientId
        )

        switch contactRecipientArchiver.archiveAllContactRecipients(
            stream: stream,
            context: recipientArchivingContext,
            tx: tx
        ) {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            try processArchiveFrameErrors(errors: partialFailures)
        case .completeFailure(let error):
            try processFatalArchivingError(error: error)
        }

        switch groupRecipientArchiver.archiveAllGroupRecipients(
            stream: stream,
            context: recipientArchivingContext,
            tx: tx
        ) {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            try processArchiveFrameErrors(errors: partialFailures)
        case .completeFailure(let error):
            try processFatalArchivingError(error: error)
        }

        switch distributionListRecipientArchiver.archiveAllDistributionListRecipients(
            stream: stream,
            context: recipientArchivingContext,
            tx: tx
        ) {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            try processArchiveFrameErrors(errors: partialFailures)
        case .completeFailure(let error):
            try processFatalArchivingError(error: error)
        }

        switch releaseNotesRecipientArchiver.archiveReleaseNotesRecipient(
            stream: stream,
            context: recipientArchivingContext,
            tx: tx
        ) {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            try processArchiveFrameErrors(errors: partialFailures)
        case .completeFailure(let error):
            try processFatalArchivingError(error: error)
        }

        // TODO: [Backups] Archive call link recipients.

        let chatArchivingContext = MessageBackup.ChatArchivingContext(
            recipientContext: recipientArchivingContext
        )
        let chatArchiveResult = chatArchiver.archiveChats(
            stream: stream,
            context: chatArchivingContext,
            tx: tx
        )
        switch chatArchiveResult {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            try processArchiveFrameErrors(errors: partialFailures)
        case .completeFailure(let error):
            try processFatalArchivingError(error: error)
        }

        let chatItemArchiveResult = chatItemArchiver.archiveInteractions(
            stream: stream,
            context: chatArchivingContext,
            tx: tx
        )
        switch chatItemArchiveResult {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            try processArchiveFrameErrors(errors: partialFailures)
        case .completeFailure(let error):
            try processFatalArchivingError(error: error)
        }

        try stream.closeFileStream()
    }

    private func writeHeader(stream: MessageBackupProtoOutputStream, tx: DBWriteTransaction) throws {
        var backupInfo = BackupProto_BackupInfo()
        backupInfo.version = Constants.supportedBackupVersion
        backupInfo.backupTimeMs = dateProvider().ows_millisecondsSince1970

        switch stream.writeHeader(backupInfo) {
        case .success:
            break
        case .fileIOError(let error), .protoSerializationError(let error):
            throw error
        }
    }

    private func processArchiveFrameErrors<IdType>(
        errors: [MessageBackup.ArchiveFrameError<IdType>]
    ) throws {
        MessageBackup.log(errors)
        // At time of writing, we want to fail for every single error.
        if errors.isEmpty.negated {
            throw BackupError()
        }
    }

    private func processFatalArchivingError(
        error: MessageBackup.FatalArchivingError
    ) throws {
        MessageBackup.log([error])
        throw BackupError()
    }

    // MARK: - Import

    public func importEncryptedBackup(fileUrl: URL, localIdentifiers: LocalIdentifiers) async throws {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }

        await migrateAttachmentsBeforeBackup()

        try await db.awaitableWrite { tx in
            let inputStream: MessageBackupProtoInputStream
            switch self.streamProvider.openEncryptedInputFileStream(
                fileUrl: fileUrl,
                localAci: localIdentifiers.aci,
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

        try await db.awaitableWrite { tx in
            let inputStream: MessageBackupProtoInputStream
            switch self.streamProvider.openPlaintextInputFileStream(
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
    }

    private func _importBackup(
        inputStream stream: MessageBackupProtoInputStream,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) throws {

        let backupInfo: BackupProto_BackupInfo
        var hasMoreFrames = false
        switch stream.readHeader() {
        case .success(let header, let moreBytesAvailable):
            backupInfo = header
            hasMoreFrames = moreBytesAvailable
        case .invalidByteLengthDelimiter:
            throw OWSAssertionError("invalid byte length delimiter on header")
        case .protoDeserializationError(let error):
            // Fail if we fail to deserialize the header.
            throw error
        }

        Logger.info("Reading backup with version: \(backupInfo.version) backed up at \(backupInfo.backupTimeMs)")

        guard backupInfo.version == Constants.supportedBackupVersion else {
            throw BackupVersionNotSupportedError()
        }

        let recipientContext = MessageBackup.RecipientRestoringContext(localIdentifiers: localIdentifiers)
        let chatContext = MessageBackup.ChatRestoringContext(
            recipientContext: recipientContext
        )

        while hasMoreFrames {
            let frame: BackupProto_Frame
            switch stream.readFrame() {
            case let .success(_frame, moreBytesAvailable):
                frame = _frame
                hasMoreFrames = moreBytesAvailable
            case .invalidByteLengthDelimiter:
                throw OWSAssertionError("invalid byte length delimiter on header")
            case .protoDeserializationError(let error):
                // fail the whole thing if we fail to deserialize one frame
                owsFailDebug("Failed to deserialize proto frame!")
                throw error
            }

            switch frame.item {
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
                        context: recipientContext,
                        tx: tx
                    )
                case .contact(let contactRecipientProto):
                    recipientResult = contactRecipientArchiver.restoreContactRecipientProto(
                        contactRecipientProto,
                        recipient: recipient,
                        context: recipientContext,
                        tx: tx
                    )
                case .group(let groupRecipientProto):
                    recipientResult = groupRecipientArchiver.restoreGroupRecipientProto(
                        groupRecipientProto,
                        recipient: recipient,
                        context: recipientContext,
                        tx: tx
                    )
                case .distributionList(let distributionListRecipientProto):
                    recipientResult = distributionListRecipientArchiver.restoreDistributionListRecipientProto(
                        distributionListRecipientProto,
                        recipient: recipient,
                        context: recipientContext,
                        tx: tx
                    )
                case .releaseNotes(let releaseNotesRecipientProto):
                    recipientResult = releaseNotesRecipientArchiver.restoreReleaseNotesRecipientProto(
                        releaseNotesRecipientProto,
                        recipient: recipient,
                        context: recipientContext,
                        tx: tx
                    )
                case .callLink(let callLinkRecipientProto):
                    // TODO: [Backups] Restore call link recipients.
                    recipientResult = .failure([.restoreFrameError(.unimplemented, recipient.recipientId)])
                }

                switch recipientResult {
                case .success:
                    continue
                case .partialRestore(let errors):
                    try processRestoreFrameErrors(errors: errors)
                case .failure(let errors):
                    try processRestoreFrameErrors(errors: errors)
                }
            case .chat(let chat):
                let chatResult = chatArchiver.restore(
                    chat,
                    context: chatContext,
                    tx: tx
                )
                switch chatResult {
                case .success:
                    continue
                case .partialRestore(let errors):
                    try processRestoreFrameErrors(errors: errors)
                case .failure(let errors):
                    try processRestoreFrameErrors(errors: errors)
                }
            case .chatItem(let chatItem):
                let chatItemResult = chatItemArchiver.restore(
                    chatItem,
                    context: chatContext,
                    tx: tx
                )
                switch chatItemResult {
                case .success:
                    continue
                case .partialRestore(let errors):
                    try processRestoreFrameErrors(errors: errors)
                case .failure(let errors):
                    try processRestoreFrameErrors(errors: errors)
                }
            case .account(let backupProtoAccountData):
                let accountDataResult = accountDataArchiver.restore(backupProtoAccountData, tx: tx)
                switch accountDataResult {
                case .success:
                    continue
                case .partialRestore(let errors):
                    try processRestoreFrameErrors(errors: errors)
                case .failure(let errors):
                    try processRestoreFrameErrors(errors: errors)
                }
            case .stickerPack(let backupProtoStickerPack):
                // TODO: [Backups] Restore sticker packs.
                try processRestoreFrameErrors(errors: [.restoreFrameError(
                    .unimplemented,
                    MessageBackup.StickerPackId(backupProtoStickerPack.packID)
                )])
            case .adHocCall(let backupProtoAdHocCall):
                // TODO: [Backups] Restore ad-hoc calls.
                try processRestoreFrameErrors(errors: [.restoreFrameError(
                    .unimplemented,
                    MessageBackup.AdHocCallId(
                        backupProtoAdHocCall.callID,
                        recipientId: backupProtoAdHocCall.recipientID
                    )
                )])
            case nil:
                owsFailDebug("Frame missing item!")
                try processRestoreFrameErrors(errors: [.restoreFrameError(
                    .invalidProtoData(.frameMissingItem),
                    MessageBackup.EmptyFrameId.shared
                )])
            }
        }

        stream.closeFileStream()
    }

    private func processRestoreFrameErrors<IdType>(errors: [MessageBackup.RestoreFrameError<IdType>]) throws {
        MessageBackup.log(errors)
        // At time of writing, we want to fail for every single error.
        if errors.isEmpty.negated {
            throw BackupError()
        }
    }

    // MARK: -

    /// TSAttachments must be migrated to v2 Attachments before we can create or restore backups.
    /// Normally this migration happens in the background; force it to run and finish now.
    private func migrateAttachmentsBeforeBackup() async {
        // We have to enable the flags; tapping a backup option
        // immediately opts you in.
        AttachmentFeatureFlags.enableV2ForMessages()

        await incrementalTSAttachmentMigrator.runUntilFinished()
    }

    public func validateEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers
    ) async throws {
        let key = try db.read { tx in
            return try messageBackupKeyMaterial.messageBackupKey(localAci: localIdentifiers.aci, tx: tx)
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
