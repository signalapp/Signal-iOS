//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class NotImplementedError: Error {}

public class CloudBackupManagerImpl: CloudBackupManager {

    private let chatArchiver: CloudBackupChatArchiver
    private let dateProvider: DateProvider
    private let db: DB
    private let dmConfigurationStore: DisappearingMessagesConfigurationStore
    private let recipientArchiver: CloudBackupRecipientArchiver
    private let streamProvider: CloudBackupProtoStreamProvider
    private let tsAccountManager: TSAccountManager
    private let tsInteractionFetcher: CloudBackup.Shims.TSInteractionFetcher
    private let tsThreadFetcher: CloudBackup.Shims.TSThreadFetcher

    public init(
        chatArchiver: CloudBackupChatArchiver,
        dateProvider: @escaping DateProvider,
        db: DB,
        dmConfigurationStore: DisappearingMessagesConfigurationStore,
        recipientArchiver: CloudBackupRecipientArchiver,
        streamProvider: CloudBackupProtoStreamProvider,
        tsAccountManager: TSAccountManager,
        tsInteractionFetcher: CloudBackup.Shims.TSInteractionFetcher,
        tsThreadFetcher: CloudBackup.Shims.TSThreadFetcher
    ) {
        self.chatArchiver = chatArchiver
        self.dateProvider = dateProvider
        self.db = db
        self.dmConfigurationStore = dmConfigurationStore
        self.recipientArchiver = recipientArchiver
        self.streamProvider = streamProvider
        self.tsAccountManager = tsAccountManager
        self.tsInteractionFetcher = tsInteractionFetcher
        self.tsThreadFetcher = tsThreadFetcher
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
        try writeMessages(
            recipientContext: recipientArchivingContext,
            chatContext: chatArchivingContext,
            stream: stream,
            tx: tx
        )

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

    private func writeMessages(
        recipientContext: CloudBackup.RecipientArchivingContext,
        chatContext: CloudBackup.ChatArchivingContext,
        stream: CloudBackupProtoOutputStream,
        tx: DBReadTransaction
    ) throws {
        guard let localAddress = tsAccountManager.localIdentifiers(tx: tx)?.aciAddress else {
            owsFailDebug("No local address!")
            return
        }

        var firstError: Error?

        tsInteractionFetcher.enumerateAllTextOnlyMessages(tx: tx) { message in
            do {
                if message.wasRemotelyDeleted {
                    // TODO: handle remotely deleted messages
                    return
                }
                guard let chatId = chatContext[message.uniqueThreadIdentifier] else {
                    owsFailDebug("Message missing chat")
                    return
                }
                let authorAddress = (message as? TSIncomingMessage)?.authorAddress ?? localAddress
                guard let authorId = recipientContext[authorAddress] else {
                    owsFailDebug("missing author id!")
                    return
                }

                let chatItemBuilder = BackupProtoChatItem.builder(
                    chatID: chatId.value,
                    authorID: authorId.value,
                    dateSent: message.timestamp,
                    sms: false
                )
                // TODO: don't include messages expiring within 24hr
                if message.expireStartedAt > 0 {
                    chatItemBuilder.setExpireStartMs(message.expireStartedAt)
                }
                if message.expiresAt > 0 {
                    chatItemBuilder.setExpiresInMs(message.expiresAt)
                }
                switch message.editState {
                case .latestRevisionRead, .latestRevisionUnread, .none:
                    break
                case .pastRevision:
                    // TODO: include message edits
                    return
                }

                if let incomingMessage = message as? TSIncomingMessage {
                    let incomingMessageProtoBuilder = BackupProtoChatItemIncomingMessageDetails.builder(
                        dateReceived: incomingMessage.receivedAtTimestamp,
                        dateServerSent: incomingMessage.serverDeliveryTimestamp,
                        read: incomingMessage.wasRead,
                        sealedSender: incomingMessage.wasReceivedByUD.negated
                    )
                    let incomingMessageProto = try incomingMessageProtoBuilder.build()
                    chatItemBuilder.setIncoming(incomingMessageProto)
                } else if let outgoingMessage = message as? TSOutgoingMessage {
                    let outgoingMessageProtoBuilder = BackupProtoChatItemOutgoingMessageDetails.builder()

                    try outgoingMessage.recipientAddressStates?.keys.forEach { address in
                        guard let sendState = outgoingMessage.recipientState(for: address) else {
                            return
                        }
                        guard let recipientId = recipientContext[address] else {
                            owsFailDebug("Missing recipient for message!")
                            return
                        }
                        var isNetworkFailure = false
                        var isIdentityKeyMismatchFailure = false
                        let protoDeliveryStatus: BackupProtoSendStatusStatus
                        let statusTimestamp: UInt64
                        switch sendState.state {
                        case OWSOutgoingMessageRecipientState.sent:
                            if let readTimestamp = sendState.readTimestamp {
                                protoDeliveryStatus = .read
                                statusTimestamp = readTimestamp.uint64Value
                            } else if let viewedTimestamp = sendState.viewedTimestamp {
                                protoDeliveryStatus = .viewed
                                statusTimestamp = viewedTimestamp.uint64Value
                            } else if let deliveryTimestamp = sendState.deliveryTimestamp {
                                protoDeliveryStatus = .delivered
                                statusTimestamp = deliveryTimestamp.uint64Value
                            } else {
                                protoDeliveryStatus = .sent
                                statusTimestamp = message.timestamp
                            }
                        case OWSOutgoingMessageRecipientState.failed:
                            // TODO: identify specific errors. for now call everything network.
                            isNetworkFailure = true
                            isIdentityKeyMismatchFailure = false
                            protoDeliveryStatus = .failed
                            statusTimestamp = message.timestamp
                        case OWSOutgoingMessageRecipientState.sending, OWSOutgoingMessageRecipientState.pending:
                            protoDeliveryStatus = .pending
                            statusTimestamp = message.timestamp
                        case OWSOutgoingMessageRecipientState.skipped:
                            protoDeliveryStatus = .skipped
                            statusTimestamp = message.timestamp
                        }

                        let sendStatusBuilder: BackupProtoSendStatusBuilder = BackupProtoSendStatus.builder(
                            recipientID: recipientId.value,
                            networkFailure: isNetworkFailure,
                            identityKeyMismatch: isIdentityKeyMismatchFailure,
                            sealedSender: sendState.wasSentByUD.negated,
                            timestamp: statusTimestamp
                        )
                        sendStatusBuilder.setDeliveryStatus(protoDeliveryStatus)
                        let sendStatus = try sendStatusBuilder.build()
                        outgoingMessageProtoBuilder.addSendStatus(sendStatus)
                    }

                    let outgoingMessageProto = try outgoingMessageProtoBuilder.build()
                    chatItemBuilder.setOutgoing(outgoingMessageProto)
                }

                guard let body = message.body else {
                    // TODO: handle non simple text messages.
                    return
                }

                let standardMessageBuilder = BackupProtoStandardMessage.builder()
                let textBuilder = BackupProtoText.builder(body: body)
                for bodyRange in message.bodyRanges?.toProtoBodyRanges() ?? [] {
                    let bodyRangeProtoBuilder = BackupProtoBodyRange.builder()
                    bodyRangeProtoBuilder.setStart(bodyRange.start)
                    bodyRangeProtoBuilder.setLength(bodyRange.length)
                    if
                        let rawMentionAci = bodyRange.mentionAci,
                        let mentionUuid = UUID(uuidString: rawMentionAci)
                    {
                        bodyRangeProtoBuilder.setMentionAci(Aci(fromUUID: mentionUuid).serviceIdBinary.asData)
                    } else if let style = bodyRange.style {
                        switch style {
                        case .none:
                            bodyRangeProtoBuilder.setStyle(.none)
                        case .bold:
                            bodyRangeProtoBuilder.setStyle(.bold)
                        case .italic:
                            bodyRangeProtoBuilder.setStyle(.italic)
                        case .spoiler:
                            bodyRangeProtoBuilder.setStyle(.spoiler)
                        case .strikethrough:
                            bodyRangeProtoBuilder.setStyle(.strikethrough)
                        case .monospace:
                            bodyRangeProtoBuilder.setStyle(.monospace)
                        }
                    }
                    let bodyRangeProto = try bodyRangeProtoBuilder.build()
                    textBuilder.addBodyRanges(bodyRangeProto)
                }
                let textProto = try textBuilder.build()
                standardMessageBuilder.setText(textProto)

                // TODO: reactions

                let standardMessageProto = try standardMessageBuilder.build()
                chatItemBuilder.setStandardMessage(standardMessageProto)
                let chatItemProto = try chatItemBuilder.build()
                let frameBuilder = BackupProtoFrame.builder()
                frameBuilder.setChatItem(chatItemProto)
                let frame = try frameBuilder.build()
                switch stream.writeFrame(frame) {
                case .success:
                    break
                case .fileIOError(let error), .protoSerializationError(let error):
                    throw error
                }

            } catch let error {
                firstError = firstError ?? error
            }
        }

        if let firstError {
            throw firstError
        }
    }

    private func _importBackup(_ fileUrl: URL, tx: DBWriteTransaction) throws {
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

        let recipientContext = CloudBackup.RecipientRestoringContext()
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
                case .failure(_, let error):
                    // TODO: maybe track which IDs failed to attribute later failures
                    // that reference this ID.
                    switch error {
                    case .databaseInsertionFailed(let dbError):
                        throw dbError
                    case .invalidProtoData:
                        throw OWSAssertionError("Invalid proto data!")
                    case .identifierNotFound, .referencedDatabaseObjectNotFound:
                        throw OWSAssertionError("Recipients are the root objects, should be impossible!")
                    case .unknownFrameType:
                        throw OWSAssertionError("Found unrecognized frame type")
                    }
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
                case .failure(_, let error):
                    // TODO: maybe track which IDs failed to attribute later failures
                    // that reference this ID.
                    switch error {
                    case .databaseInsertionFailed(let dbError):
                        throw dbError
                    case .invalidProtoData:
                        throw OWSAssertionError("Invalid proto data!")
                    case .identifierNotFound, .referencedDatabaseObjectNotFound:
                        // TODO: can we attribute the failure to a recipient proto
                        // that had an error? (vs one that just wasn't present at all)
                        throw OWSAssertionError("Referenced object doesn't exist!")
                    case .unknownFrameType:
                        throw OWSAssertionError("Found unrecognized frame type")
                    }
                }
            } else if let chatItem = frame.chatItem {
                try handleReadChatItem(
                    chatItem: chatItem,
                    recipientContext: recipientContext,
                    chatContext: chatContext,
                    tx: tx
                )
            }
        }

        return stream.closeFileStream()
    }

    private func handleReadChatItem(
        chatItem: BackupProtoChatItem,
        recipientContext: CloudBackup.RecipientRestoringContext,
        chatContext: CloudBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) throws {
        guard let standardMessage = chatItem.standardMessage else {
            // TODO: handle other message types
            return
        }

        guard
            let threadUniqueId = chatContext[chatItem.chatId],
            let thread = tsThreadFetcher.fetch(threadUniqueId: threadUniqueId.value, tx: tx)
        else {
            owsFailDebug("Missing thread for message!")
            return
        }

        let bodyRanges: MessageBodyRanges?
        if let bodyRangesProto = standardMessage.text?.bodyRanges, !bodyRangesProto.isEmpty {

            var bodyMentions = [NSRange: Aci]()
            var bodyStyles = [NSRangedValue<MessageBodyRanges.SingleStyle>]()
            for bodyRange in bodyRangesProto {
                let range = NSRange(location: Int(bodyRange.start), length: Int(bodyRange.length))
                if
                    let rawMentionAci = bodyRange.mentionAci,
                    let mentionAci = try? Aci.parseFrom(serviceIdBinary: rawMentionAci)
                {
                    bodyMentions[range] = mentionAci
                } else if bodyRange.hasStyle {
                    let swiftStyle: MessageBodyRanges.SingleStyle
                    switch bodyRange.style {
                    case .some(.none), nil:
                        continue
                    case .bold:
                        swiftStyle = .bold
                    case .italic:
                        swiftStyle = .italic
                    case .monospace:
                        swiftStyle = .monospace
                    case .spoiler:
                        swiftStyle = .spoiler
                    case .strikethrough:
                        swiftStyle = .strikethrough
                    }
                    bodyStyles.append(.init(swiftStyle, range: range))
                }
            }
            bodyRanges = .init(mentions: bodyMentions, styles: bodyStyles)
        } else {
            bodyRanges = nil
        }

        if let incomingMessage = chatItem.incoming {

            let authorAci: Aci
            switch recipientContext[chatItem.authorRecipientId] {
            case .contact(let aci, _, _):
                guard let aci else {
                    fallthrough
                }
                authorAci = aci
            default:
                // Messages can only come from Acis.
                owsFailDebug("Missing author for message!")
                return
            }

            let messageBuilder = TSIncomingMessageBuilder.builder(
                thread: thread,
                timestamp: incomingMessage.dateReceived,
                authorAci: authorAci,
                // TODO: this needs to be added to the proto
                sourceDeviceId: 1,
                messageBody: standardMessage.text?.body,
                bodyRanges: bodyRanges,
                attachmentIds: nil,
                // TODO: handle edit states
                editState: .none,
                // TODO: expose + set expire start time
                expiresInSeconds: UInt32(chatItem.expiresInMs),
                quotedMessage: nil,
                contactShare: nil,
                linkPreview: nil,
                messageSticker: nil,
                serverTimestamp: nil,
                serverDeliveryTimestamp: chatItem.dateSent,
                serverGuid: nil,
                wasReceivedByUD: incomingMessage.sealedSender.negated,
                isViewOnceMessage: false,
                storyAuthorAci: nil,
                storyTimestamp: nil,
                storyReactionEmoji: nil,
                giftBadge: nil,
                paymentNotification: nil
            )
            let message = messageBuilder.build()
            tsInteractionFetcher.insert(message, tx: tx)

        } else if let outgoingMessage = chatItem.outgoing {

            let messageBuilder = TSOutgoingMessageBuilder.builder(
                thread: thread,
                timestamp: chatItem.dateSent,
                messageBody: standardMessage.text?.body,
                bodyRanges: bodyRanges,
                attachmentIds: nil,
                // TODO: is this seconds or ms?
                expiresInSeconds: UInt32(chatItem.expiresInMs),
                expireStartedAt: chatItem.expireStartMs,
                isVoiceMessage: false,
                groupMetaMessage: .unspecified,
                quotedMessage: nil,
                contactShare: nil,
                linkPreview: nil,
                messageSticker: nil,
                isViewOnceMessage: false,
                changeActionsProtoData: nil,
                additionalRecipients: nil,
                skippedRecipients: nil,
                storyAuthorAci: nil,
                storyTimestamp: nil,
                storyReactionEmoji: nil,
                giftBadge: nil
            )

            let message = tsInteractionFetcher.insertMessageWithBuilder(messageBuilder, tx: tx)

            for sendStatus in outgoingMessage.sendStatus {
                let recipient: ServiceId
                switch recipientContext[chatItem.authorRecipientId] {
                case .contact(let aci, let pni, _):
                    guard let serviceId: ServiceId = aci ?? pni else {
                        fallthrough
                    }
                    recipient = serviceId
                default:
                    // Recipients can only be Acis or Pnis.
                    // TODO: what about e164s?
                    continue
                }

                if let deliveryStatus = sendStatus.deliveryStatus {
                    tsInteractionFetcher.update(
                        message,
                        withRecipient: recipient,
                        status: deliveryStatus,
                        timestamp: sendStatus.timestamp,
                        wasSentByUD: sendStatus.sealedSender.negated,
                        tx: tx
                    )
                }
            }

            // TODO: mark the message as sent and whatnot.
        }
    }
}

fileprivate extension CloudBackup.RecipientArchivingContext {

    subscript(address: SignalServiceAddress) -> CloudBackup.RecipientId? {
        // swiftlint:disable:next implicit_getter
        get {
            if
                let aci = address.serviceId as? Aci,
                let id = self[.contactAci(aci)]
            {
                return id
            } else if
                let pni = address.serviceId as? Pni,
                let id = self[.contactPni(pni)]
            {
                return id
            } else if
                let e164 = address.e164,
                let id = self[.contactE164(e164)]
            {
                return id
            } else {
                return nil
            }
        }
    }
}
