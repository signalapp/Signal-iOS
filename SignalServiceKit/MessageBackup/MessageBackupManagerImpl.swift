//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class NotImplementedError: Error {}
public class BackupError: Error {}

public class MessageBackupManagerImpl: MessageBackupManager {

    private let accountDataArchiver: MessageBackupAccountDataArchiver
    private let backupRequestManager: MessageBackupRequestManager
    private let chatArchiver: MessageBackupChatArchiver
    private let chatItemArchiver: MessageBackupChatItemArchiver
    private let dateProvider: DateProvider
    private let db: DB
    private let localRecipientArchiver: MessageBackupLocalRecipientArchiver
    private let recipientArchiver: MessageBackupRecipientArchiver
    private let streamProvider: MessageBackupProtoStreamProvider

    public init(
        accountDataArchiver: MessageBackupAccountDataArchiver,
        backupRequestManager: MessageBackupRequestManager,
        chatArchiver: MessageBackupChatArchiver,
        chatItemArchiver: MessageBackupChatItemArchiver,
        dateProvider: @escaping DateProvider,
        db: DB,
        localRecipientArchiver: MessageBackupLocalRecipientArchiver,
        recipientArchiver: MessageBackupRecipientArchiver,
        streamProvider: MessageBackupProtoStreamProvider
    ) {
        self.accountDataArchiver = accountDataArchiver
        self.backupRequestManager = backupRequestManager
        self.chatArchiver = chatArchiver
        self.chatItemArchiver = chatItemArchiver
        self.dateProvider = dateProvider
        self.db = db
        self.localRecipientArchiver = localRecipientArchiver
        self.recipientArchiver = recipientArchiver
        self.streamProvider = streamProvider
    }

    public func createBackup(localIdentifiers: LocalIdentifiers) async throws -> URL {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }
        return try await db.awaitableWrite { tx in
            // The mother of all write transactions. Eventually we want to use
            // a read tx, and use explicit locking to prevent other things from
            // happening in the meantime (e.g. message processing) but for now
            // hold the single write lock and call it a day.
            return try self._createBackup(localIdentifiers: localIdentifiers, tx: tx)
        }
    }

    public func importBackup(localIdentifiers: LocalIdentifiers, fileUrl: URL) async throws {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }
        try await db.awaitableWrite { tx in
            // This has to open one big write transaction; the alternative is
            // to chunk them into separate writes. Nothing else should be happening
            // in the app anyway.
            do {
                try self._importBackup(localIdentifiers: localIdentifiers, fileUrl: fileUrl, tx: tx)
            } catch let error {
                owsFailDebug("Failed! \(error)")
                throw error
            }
        }
    }

    private func _createBackup(
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) throws -> URL {
        let stream: MessageBackupProtoOutputStream
        let metadataProvider: MessageBackup.MetadataProvider
        switch streamProvider.openOutputFileStream(localAci: localIdentifiers.aci, tx: tx) {
        case let .success(streamResult, metadataProviderResult):
            stream = streamResult
            metadataProvider = metadataProviderResult
        case .unableToOpenFileStream:
            throw OWSAssertionError("Unable to open output stream")
        }

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

        let recipientArchiveResult = recipientArchiver.archiveRecipients(
            stream: stream,
            context: recipientArchivingContext,
            tx: tx
        )
        switch recipientArchiveResult {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            try processArchiveFrameErrors(errors: partialFailures)
        case .completeFailure(let error):
            try processFatalArchivingError(error: error)
        }

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
        return try metadataProvider().fileUrl
    }

    private func writeHeader(stream: MessageBackupProtoOutputStream, tx: DBWriteTransaction) throws {
        let backupInfo = BackupProto.BackupInfo(
            version: 1,
            backupTimeMs: dateProvider().ows_millisecondsSince1970
        )
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

    private func _importBackup(
        localIdentifiers: LocalIdentifiers,
        fileUrl: URL,
        tx: DBWriteTransaction
    ) throws {

        let stream: MessageBackupProtoInputStream
        switch streamProvider.openInputFileStream(localAci: localIdentifiers.aci, fileURL: fileUrl, tx: tx) {
        case .success(let streamResult):
            stream = streamResult
        case .fileNotFound:
            throw OWSAssertionError("file not found!")
        case .unableToOpenFileStream:
            throw OWSAssertionError("unable to open input stream")
        }

        defer {
            stream.closeFileStream()
        }

        let backupInfo: BackupProto.BackupInfo
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

        let recipientContext = MessageBackup.RecipientRestoringContext(localIdentifiers: localIdentifiers)
        let chatContext = MessageBackup.ChatRestoringContext(
            recipientContext: recipientContext
        )

        while hasMoreFrames {
            let frame: BackupProto.Frame
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
                if type(of: localRecipientArchiver).canRestore(recipient) {
                    recipientResult = localRecipientArchiver.restore(
                        recipient,
                        context: recipientContext,
                        tx: tx
                    )
                } else {
                    recipientResult = recipientArchiver.restore(
                        recipient,
                        context: recipientContext,
                        tx: tx
                    )
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
            case .call(let backupProtoCall):
                // TODO: Not yet implemented.
                try processRestoreFrameErrors(errors: [.restoreFrameError(
                    .unimplemented,
                    MessageBackup.CallId(
                        callId: backupProtoCall.callId,
                        conversationRecipientId: MessageBackup.RecipientId(
                            integerLiteral: backupProtoCall.conversationRecipientId
                        )
                    ))
                ])
            case .stickerPack(let backupProtoStickerPack):
                // TODO: Not yet implemented.
                try processRestoreFrameErrors(errors: [.restoreFrameError(
                    .unimplemented,
                    MessageBackup.StickerPackId(backupProtoStickerPack.id)
                )])
            case nil:
                owsFailDebug("Frame missing item!")
                try processRestoreFrameErrors(errors: [.restoreFrameError(
                    .invalidProtoData(.frameMissingItem),
                    MessageBackup.EmptyFrameId.shared
                )])
            }
        }

        return stream.closeFileStream()
    }

    private func processRestoreFrameErrors<IdType>(
        errors: [MessageBackup.RestoreFrameError<IdType>]
    ) throws {
        MessageBackup.log(errors)
        // At time of writing, we want to fail for every single error.
        if errors.isEmpty.negated {
            throw BackupError()
        }
    }
}
