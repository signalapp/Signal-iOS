//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class NotImplementedError: Error {}
public class BackupError: Error {}

public class MessageBackupManagerImpl: MessageBackupManager {

    private let chatArchiver: MessageBackupChatArchiver
    private let chatItemArchiver: MessageBackupChatItemArchiver
    private let dateProvider: DateProvider
    private let db: DB
    private let localRecipientArchiver: MessageBackupLocalRecipientArchiver
    private let recipientArchiver: MessageBackupRecipientArchiver
    private let streamProvider: MessageBackupProtoStreamProvider
    private let tsAccountManager: TSAccountManager

    public init(
        chatArchiver: MessageBackupChatArchiver,
        chatItemArchiver: MessageBackupChatItemArchiver,
        dateProvider: @escaping DateProvider,
        db: DB,
        localRecipientArchiver: MessageBackupLocalRecipientArchiver,
        recipientArchiver: MessageBackupRecipientArchiver,
        streamProvider: MessageBackupProtoStreamProvider,
        tsAccountManager: TSAccountManager
    ) {
        self.chatArchiver = chatArchiver
        self.chatItemArchiver = chatItemArchiver
        self.dateProvider = dateProvider
        self.db = db
        self.localRecipientArchiver = localRecipientArchiver
        self.recipientArchiver = recipientArchiver
        self.streamProvider = streamProvider
        self.tsAccountManager = tsAccountManager
    }

    public func createBackup() async throws -> URL {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }
        return try await db.awaitableWrite { tx in
            // The mother of all write transactions. Eventually we want to use
            // a read tx, and use explicit locking to prevent other things from
            // happening in the meantime (e.g. message processing) but for now
            // hold the single write lock and call it a day.
            return try self._createBackup(tx: tx)
        }
    }

    public func importBackup(fileUrl: URL) async throws {
        guard FeatureFlags.messageBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }
        try await db.awaitableWrite { tx in
            // This has to open one big write transaction; the alternative is
            // to chunk them into separate writes. Nothing else should be happening
            // in the app anyway.
            do {
                try self._importBackup(fileUrl, tx: tx)
            } catch let error {
                owsFailDebug("Failed! \(error)")
                throw error
            }
        }
    }

    private func _createBackup(tx: DBWriteTransaction) throws -> URL {
        let stream: MessageBackupProtoOutputStream
        switch streamProvider.openOutputFileStream() {
        case .success(let streamResult):
            stream = streamResult
        case .unableToOpenFileStream:
            throw OWSAssertionError("Unable to open output stream")
        }

        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            throw OWSAssertionError("No local identifiers!")
        }

        try writeHeader(stream: stream, tx: tx)

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

        return stream.closeFileStream()
    }

    private func writeHeader(stream: MessageBackupProtoOutputStream, tx: DBWriteTransaction) throws {
        let backupInfo = try BackupProtoBackupInfo.builder(
            version: 1,
            backupTimeMs: dateProvider().ows_millisecondsSince1970
        ).build()
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

    private func _importBackup(_ fileUrl: URL, tx: DBWriteTransaction) throws {
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            throw OWSAssertionError("No local identifiers!")
        }

        let stream: MessageBackupProtoInputStream
        switch streamProvider.openInputFileStream(fileURL: fileUrl) {
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

        let backupInfo: BackupProtoBackupInfo
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
            let frame: BackupProtoFrame
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
            if let recipient = frame.recipient {
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
            } else if let chat = frame.chat {
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
            } else if let chatItem = frame.chatItem {
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
