//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class NotImplementedError: Error {}

public class CloudBackupManagerImpl: CloudBackupManager {

    private let chatArchiver: CloudBackupChatArchiver
    private let chatItemArchiver: CloudBackupChatItemArchiver
    private let dateProvider: DateProvider
    private let db: DB
    private let recipientArchiver: CloudBackupRecipientArchiver
    private let streamProvider: CloudBackupProtoStreamProvider
    private let tsAccountManager: TSAccountManager

    public init(
        chatArchiver: CloudBackupChatArchiver,
        chatItemArchiver: CloudBackupChatItemArchiver,
        dateProvider: @escaping DateProvider,
        db: DB,
        recipientArchiver: CloudBackupRecipientArchiver,
        streamProvider: CloudBackupProtoStreamProvider,
        tsAccountManager: TSAccountManager
    ) {
        self.chatArchiver = chatArchiver
        self.chatItemArchiver = chatItemArchiver
        self.dateProvider = dateProvider
        self.db = db
        self.recipientArchiver = recipientArchiver
        self.streamProvider = streamProvider
        self.tsAccountManager = tsAccountManager
    }

    public func createBackup() async throws -> URL {
        guard FeatureFlags.cloudBackupFileAlpha else {
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
        guard FeatureFlags.cloudBackupFileAlpha else {
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
        let stream: CloudBackupProtoOutputStream
        switch streamProvider.openOutputFileStream() {
        case .success(let streamResult):
            stream = streamResult
        case .unableToOpenFileStream:
            throw OWSAssertionError("Unable to open output stream")
        }

        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            throw OWSAssertionError("No local identifiers!")
        }
        let recipientArchivingContext = CloudBackup.RecipientArchivingContext(
            localIdentifiers: localIdentifiers
        )

        try writeHeader(stream: stream, tx: tx)

        let recipientArchiveResult = recipientArchiver.archiveRecipients(
            stream: stream,
            context: recipientArchivingContext,
            tx: tx
        )
        switch recipientArchiveResult {
        case .success:
            break
        case .partialSuccess(let partialFailures):
            // TODO: how many failures is too many?
            Logger.warn("Failed to serialize \(partialFailures.count) recipients")
        case .completeFailure(let error):
            throw error
        }

        let chatArchivingContext = CloudBackup.ChatArchivingContext(
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
            // TODO: how many failures is too many?
            Logger.warn("Failed to serialize \(partialFailures.count) chats")
        case .completeFailure(let error):
            throw error
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
            // TODO: how many failures is too many?
            Logger.warn("Failed to serialize \(partialFailures.count) chat items")
        case .completeFailure(let error):
            throw error
        }

        return stream.closeFileStream()
    }

    private func writeHeader(stream: CloudBackupProtoOutputStream, tx: DBWriteTransaction) throws {
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

    private func _importBackup(_ fileUrl: URL, tx: DBWriteTransaction) throws {
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            throw OWSAssertionError("No local identifiers!")
        }

        let stream: CloudBackupProtoInputStream
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

        let recipientContext = CloudBackup.RecipientRestoringContext(localIdentifiers: localIdentifiers)
        let chatContext = CloudBackup.ChatRestoringContext(
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
                // TODO: should we fail the whole thing if we fail to deserialize one frame?
                throw error
            }
            if let recipient = frame.recipient {
                let recipientResult = recipientArchiver.restore(
                    recipient,
                    context: recipientContext,
                    tx: tx
                )
                switch recipientResult {
                case .success:
                    continue
                case .partialRestore(let id, let errors):
                    try processRestoreFrameErrors(id: id, errors: errors, context: chatContext)
                case .failure(let id, let errors):
                    try processRestoreFrameErrors(id: id, errors: errors, context: chatContext)
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
                case .partialRestore(let id, let errors):
                    try processRestoreFrameErrors(id: id, errors: errors, context: chatContext)
                case .failure(let id, let errors):
                    try processRestoreFrameErrors(id: id, errors: errors, context: chatContext)
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
                case .partialRestore(let id, let errors):
                    try processRestoreFrameErrors(id: id, errors: errors, context: chatContext)
                case .failure(let id, let errors):
                    try processRestoreFrameErrors(id: id, errors: errors, context: chatContext)
                }
            }
        }

        return stream.closeFileStream()
    }

    private func processRestoreFrameErrors<IdType>(
        id: IdType,
        errors: [CloudBackup.RestoringFrameError],
        context: CloudBackup.ChatRestoringContext
    ) throws {
        try errors.forEach { error in
            // TODO: we shouldn't throw on every error, especially
            // those from successWithWarnings cases.
            switch error {
            case .databaseInsertionFailed(let dbError):
                throw dbError
            case .invalidProtoData:
                throw OWSAssertionError("Invalid proto data for id: \(id)")
            case .identifierNotFound(let referencedId):
                // TODO: aggregate these errors; at the end we should be able to say
                // some set of IDs were referenced but not found or failed to process.
                switch referencedId {
                case .chat(let chatId):
                    throw OWSAssertionError("Did not find chat id: \(chatId) referenced from: \(id)")
                case .recipient(let recipientId):
                    throw OWSAssertionError("Did not find recipient id: \(recipientId) referenced from: \(id)")
                }
            case .referencedDatabaseObjectNotFound(let referencedId):
                switch referencedId {
                case .thread(let threadUniqueId):
                    throw OWSAssertionError("Did not find thread: \(threadUniqueId) referenced from: \(id)")
                case .groupThread(let groupId):
                    throw OWSAssertionError("Did not find thread with group id: \(groupId) referenced from: \(id)")
                }
            case .unknownFrameType:
                throw OWSAssertionError("Found unrecognized frame type with id: \(id)")
            case .unimplemented:
                // Ignore unimplemented errors.
                break
            }
        }
    }
}
