//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public extension BackupArchive {

    /// An identifier for a ``BackupProto_ChatItem`` backup frame.
    struct ChatItemId: BackupArchive.LoggableId, Hashable {
        let value: UInt64

        public init(backupProtoChatItem: BackupProto_ChatItem) {
            self.value = backupProtoChatItem.dateSent
        }

        public init(interaction: TSInteraction) {
            self.value = interaction.timestamp
        }

        // MARK: BackupArchive.LoggableId

        public var typeLogString: String { "BackupProto_ChatItem" }
        public var idLogString: String { "timestamp: \(value)" }
    }
}

// MARK: -

public class BackupArchiveChatItemArchiver: BackupArchiveProtoStreamWriter {
    typealias ChatItemId = BackupArchive.ChatItemId
    typealias ArchiveMultiFrameResult = BackupArchive.ArchiveMultiFrameResult<BackupArchive.InteractionUniqueId>
    typealias RestoreFrameResult = BackupArchive.RestoreFrameResult<ChatItemId>

    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>

    private let archivedPaymentStore: ArchivedPaymentStore
    private let attachmentsArchiver: BackupArchiveMessageAttachmentArchiver
    private let callRecordStore: CallRecordStore
    private let contactManager: BackupArchive.Shims.ContactManager
    private let editMessageStore: EditMessageStore
    private let groupCallRecordManager: GroupCallRecordManager
    private let groupUpdateItemBuilder: GroupUpdateItemBuilder
    private let individualCallRecordManager: IndividualCallRecordManager
    private let interactionStore: BackupArchiveInteractionStore
    private let oversizeTextArchiver: BackupArchiveInlinedOversizeTextArchiver
    private let pollArchiver: BackupArchivePollArchiver
    private let reactionStore: ReactionStore
    private let threadStore: BackupArchiveThreadStore
    private let reactionArchiver: BackupArchiveReactionArchiver
    private let pinnedMessageManager: PinnedMessageManager

    private lazy var contentsArchiver = BackupArchiveTSMessageContentsArchiver(
        interactionStore: interactionStore,
        archivedPaymentStore: archivedPaymentStore,
        attachmentsArchiver: attachmentsArchiver,
        oversizeTextArchiver: oversizeTextArchiver,
        reactionArchiver: reactionArchiver,
        pollArchiver: pollArchiver,
        pinnedMessageManager: pinnedMessageManager,
    )
    private lazy var incomingMessageArchiver = BackupArchiveTSIncomingMessageArchiver(
        contentsArchiver: contentsArchiver,
        editMessageStore: editMessageStore,
        interactionStore: interactionStore,
        pinnedMessageManager: pinnedMessageManager,
    )
    private lazy var outgoingMessageArchiver = BackupArchiveTSOutgoingMessageArchiver(
        contentsArchiver: contentsArchiver,
        editMessageStore: editMessageStore,
        interactionStore: interactionStore,
        pinnedMessageManager: pinnedMessageManager,
    )
    private lazy var chatUpdateMessageArchiver = BackupArchiveChatUpdateMessageArchiver(
        callRecordStore: callRecordStore,
        contactManager: contactManager,
        groupCallRecordManager: groupCallRecordManager,
        groupUpdateItemBuilder: groupUpdateItemBuilder,
        individualCallRecordManager: individualCallRecordManager,
        interactionStore: interactionStore,
    )

    init(
        archivedPaymentStore: ArchivedPaymentStore,
        attachmentsArchiver: BackupArchiveMessageAttachmentArchiver,
        callRecordStore: CallRecordStore,
        contactManager: BackupArchive.Shims.ContactManager,
        editMessageStore: EditMessageStore,
        groupCallRecordManager: GroupCallRecordManager,
        groupUpdateItemBuilder: GroupUpdateItemBuilder,
        individualCallRecordManager: IndividualCallRecordManager,
        interactionStore: BackupArchiveInteractionStore,
        oversizeTextArchiver: BackupArchiveInlinedOversizeTextArchiver,
        pollArchiver: BackupArchivePollArchiver,
        reactionStore: ReactionStore,
        threadStore: BackupArchiveThreadStore,
        reactionArchiver: BackupArchiveReactionArchiver,
        pinnedMessageManager: PinnedMessageManager,
    ) {
        self.archivedPaymentStore = archivedPaymentStore
        self.attachmentsArchiver = attachmentsArchiver
        self.callRecordStore = callRecordStore
        self.contactManager = contactManager
        self.editMessageStore = editMessageStore
        self.groupCallRecordManager = groupCallRecordManager
        self.groupUpdateItemBuilder = groupUpdateItemBuilder
        self.individualCallRecordManager = individualCallRecordManager
        self.interactionStore = interactionStore
        self.oversizeTextArchiver = oversizeTextArchiver
        self.pollArchiver = pollArchiver
        self.reactionStore = reactionStore
        self.threadStore = threadStore
        self.reactionArchiver = reactionArchiver
        self.pinnedMessageManager = pinnedMessageManager
    }

    // MARK: -

    /// Archive all ``TSInteraction``s (they map to ``BackupProto_ChatItem`` and ``BackupProto_Call``).
    ///
    /// - Returns: ``ArchiveMultiFrameResult.success`` if all frames were written without error, or either
    /// partial or complete failure otherwise.
    /// How to handle ``ArchiveMultiFrameResult.partialSuccess`` is up to the caller,
    /// but typically an error will be shown to the user, but the backup will be allowed to proceed.
    /// ``ArchiveMultiFrameResult.completeFailure``, on the other hand, will stop the entire backup,
    /// and should be used if some critical or category-wide failure occurs.
    func archiveInteractions(
        stream: BackupArchiveProtoOutputStream,
        context: BackupArchive.ChatArchivingContext,
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var completeFailureError: BackupArchive.FatalArchivingError?
        var partialFailures = [ArchiveFrameError]()

        func archiveInteraction(
            _ interactionRecord: InteractionRecord,
            _ frameBencher: BackupArchive.Bencher.FrameBencher,
        ) -> Bool {
            return autoreleasepool { () -> Bool in
                let interaction: TSInteraction
                do {
                    interaction = try TSInteraction.fromRecord(interactionRecord)
                } catch let error {
                    partialFailures.append(.archiveFrameError(
                        .invalidInteractionDatabaseRow(error),
                        BackupArchive.InteractionUniqueId(invalidInteractionRecord: interactionRecord),
                    ))
                    return true
                }

                let result = self.archiveInteraction(
                    interaction,
                    stream: stream,
                    frameBencher: frameBencher,
                    context: context,
                )
                switch result {
                case .success:
                    return true
                case .partialSuccess(let errors):
                    partialFailures.append(contentsOf: errors)
                    return true
                case .completeFailure(let error):
                    completeFailureError = error
                    return false
                }
            }
        }

        do {
            try context.bencher.wrapEnumeration(
                { tx, block in
                    let cursor = try InteractionRecord
                        .fetchCursor(tx.database)

                    while
                        let interactionRecord = try cursor.next(),
                        try block(interactionRecord)
                    {}
                },
                tx: context.tx,
            ) { interactionRecord, frameBencher in
                try Task.checkCancellation()
                return archiveInteraction(interactionRecord, frameBencher)
            }
        } catch let error as CancellationError {
            throw error
        } catch let error {
            // Errors thrown here are from the iterator's SQL query,
            // not the individual interaction handler.
            return .completeFailure(.fatalArchiveError(.interactionIteratorError(error)))
        }

        if let completeFailureError {
            return .completeFailure(completeFailureError)
        } else if partialFailures.isEmpty {
            return .success
        } else {
            return .partialSuccess(partialFailures)
        }
    }

    private func archiveInteraction(
        _ interaction: TSInteraction,
        stream: BackupArchiveProtoOutputStream,
        frameBencher: BackupArchive.Bencher.FrameBencher,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveMultiFrameResult {
        var partialErrors = [ArchiveFrameError]()

        let chatId = context[interaction.uniqueThreadIdentifier]
        let threadInfo = chatId.map { context[$0] } ?? nil

        if context.gv1ThreadIds.contains(interaction.uniqueThreadIdentifier) {
            /// We are knowingly dropping GV1 data from backups, so we'll skip
            /// archiving any interactions for GV1 threads without errors.
            return .success
        }

        guard let chatId, let threadInfo else {
            partialErrors.append(.archiveFrameError(
                .referencedThreadIdMissing(interaction.uniqueThreadIdentifier),
                interaction.uniqueInteractionId,
            ))
            return .partialSuccess(partialErrors)
        }

        let archiveInteractionResult: BackupArchive.ArchiveInteractionResult<BackupArchive.InteractionArchiveDetails>
        if
            let message = interaction as? TSMessage,
            message.isGroupStoryReply
        {
            // We skip group story reply messages, as stories
            // aren't backed up so neither should their replies.
            return .success
        } else if let incomingMessage = interaction as? TSIncomingMessage {
            archiveInteractionResult = incomingMessageArchiver.archiveIncomingMessage(
                incomingMessage,
                threadInfo: threadInfo,
                context: context,
            )
        } else if let outgoingMessage = interaction as? TSOutgoingMessage {
            archiveInteractionResult = outgoingMessageArchiver.archiveOutgoingMessage(
                outgoingMessage,
                threadInfo: threadInfo,
                context: context,
            )
        } else if let individualCallInteraction = interaction as? TSCall {
            archiveInteractionResult = chatUpdateMessageArchiver.archiveIndividualCall(
                individualCallInteraction,
                threadInfo: threadInfo,
                context: context,
            )
        } else if let groupCallInteraction = interaction as? OWSGroupCallMessage {
            archiveInteractionResult = chatUpdateMessageArchiver.archiveGroupCall(
                groupCallInteraction,
                threadInfo: threadInfo,
                context: context,
            )
        } else if let errorMessage = interaction as? TSErrorMessage {
            archiveInteractionResult = chatUpdateMessageArchiver.archiveErrorMessage(
                errorMessage,
                threadInfo: threadInfo,
                context: context,
            )
        } else if let infoMessage = interaction as? TSInfoMessage {
            archiveInteractionResult = chatUpdateMessageArchiver.archiveInfoMessage(
                infoMessage,
                threadInfo: threadInfo,
                context: context,
            )
        } else {
            /// Any interactions that landed us here will be legacy messages we
            /// no longer support and which have no corresponding type in the
            /// Backup, so we'll skip them and report it as a success.
            return .success
        }

        var details: BackupArchive.InteractionArchiveDetails
        switch archiveInteractionResult {
        case .success(let deets):
            details = deets
        case .partialFailure(let deets, let errors):
            details = deets
            partialErrors.append(contentsOf: errors)
        case .skippableInteraction:
            // Skip! Say it succeeded so we ignore it.
            return .success
        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
            return .partialSuccess(partialErrors)
        case .completeFailure(let error):
            return .completeFailure(error)
        }

        // We may skip archiving messages based on their expiration
        // (disappearing message) details.
        if
            context.includedContentFilter.shouldSkipMessageBasedOnExpiration(
                expireStartDate: details.expireStartDate,
                expiresInMs: details.expiresInMs,
                currentTimestamp: context.startTimestampMs,
            )
        {
            // Skip, but treat as a success.
            return .success
        }

        // A bug on iOS allowed us to create edits of voice notes that contained
        // text as well, which are not allowed in a Backup. Sanitize before
        // writing that disallowed content to the stream.
        sanitizeVoiceNotesWithText(details: &details)

        let error = Self.writeFrameToStream(
            stream,
            objectId: interaction.uniqueInteractionId,
            frameBencher: frameBencher,
        ) {
            let chatItem = buildChatItem(
                fromDetails: details,
                chatId: chatId,
            )

            var frame = BackupProto_Frame()
            frame.item = .chatItem(chatItem)
            return frame
        }

        if let error {
            partialErrors.append(error)
            return .partialSuccess(partialErrors)
        } else if partialErrors.isEmpty {
            return .success
        } else {
            return .partialSuccess(partialErrors)
        }
    }

    /// Strips the "voice message" flag from the attachments of all revisions
    /// of the given message, if any of those revisions include both a voice
    /// message and text.
    ///
    /// This works around an issue in which iOS allowed editing of voice
    /// messages such that they could get body text added, by converting those
    /// messages to "text messages with a non-voice-message audio attachment".
    private func sanitizeVoiceNotesWithText(
        details: inout BackupArchive.InteractionArchiveDetails,
    ) {
        let anyRevisionContainsVoiceNoteAndText = details.anyRevisionContainsChatItemType { chatItemType -> Bool in
            switch chatItemType {
            case .standardMessage(let standardMessageProto):
                let hasText = standardMessageProto.hasText
                let hasVoiceNote = standardMessageProto.attachments.contains {
                    $0.flag == .voiceMessage
                }

                return hasText && hasVoiceNote
            default:
                return false
            }
        }

        guard anyRevisionContainsVoiceNoteAndText else { return }

        details.mutateChatItemTypes { _chatItemType -> BackupArchive.InteractionArchiveDetails.ChatItemType in
            switch _chatItemType {
            case .standardMessage(var standardMessageProto):
                standardMessageProto.attachments = standardMessageProto.attachments.map { attachment in
                    if attachment.flag == .voiceMessage {
                        var _attachment = attachment
                        _attachment.flag = .none
                        return _attachment
                    }

                    return attachment
                }

                return .standardMessage(standardMessageProto)
            default:
                return _chatItemType
            }
        }
    }

    private func buildChatItem(
        fromDetails details: BackupArchive.InteractionArchiveDetails,
        chatId: BackupArchive.ChatId,
    ) -> BackupProto_ChatItem {
        var chatItem = BackupProto_ChatItem()
        chatItem.chatID = chatId.value
        chatItem.authorID = details.author.value
        chatItem.dateSent = details.dateCreated
        if let expiresInMs = details.expiresInMs, expiresInMs > 0 {
            if let expireStartDate = details.expireStartDate {
                chatItem.expireStartDate = expireStartDate
            }
            chatItem.expiresInMs = expiresInMs
        }
        chatItem.sms = details.isSmsPreviouslyRestoredFromBackup
        chatItem.item = details.chatItemType
        chatItem.directionalDetails = details.directionalDetails
        chatItem.revisions = details.pastRevisions.map { pastRevisionDetails in
            /// Recursively map our past revision details to `ChatItem`s of
            /// their own. (Their `pastRevisions` will all be empty.)
            return buildChatItem(
                fromDetails: pastRevisionDetails,
                chatId: chatId,
            )
        }

        if let pinMessageDetails = details.pinMessageDetails {
            var pinDetails = BackupProto_ChatItem.PinDetails()
            pinDetails.pinnedAtTimestamp = pinMessageDetails.pinnedAtTimestamp
            let expiryDetails: BackupProto_ChatItem.PinDetails.OneOf_PinExpiry
            if let expiry = pinMessageDetails.expiresAtTimestamp {
                expiryDetails = .pinExpiresAtTimestamp(expiry)
            } else {
                expiryDetails = .pinNeverExpires(true)
            }
            pinDetails.pinExpiry = expiryDetails
            chatItem.pinDetails = pinDetails
        }

        return chatItem
    }

    // MARK: -

    /// Restore a single ``BackupProto_ChatItem`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if all frames were read without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ chatItem: BackupProto_ChatItem,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreFrameResult {
        func restoreFrameError(
            _ error: BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>.ErrorType,
            line: UInt = #line,
        ) -> RestoreFrameResult {
            return .failure([.restoreFrameError(error, chatItem.id, line: line)])
        }

        switch context.recipientContext[chatItem.authorRecipientId] {
        case .releaseNotesChannel:
            // The release notes channel doesn't exist yet, so for the time
            // being we'll drop all chat items destined for it.
            //
            // TODO: [Backups] Implement restoring chat items into the release notes channel chat.
            return .success
        default:
            break
        }

        guard let thread = context.chatContext[chatItem.typedChatId] else {
            return restoreFrameError(.invalidProtoData(.chatIdNotFound(chatItem.typedChatId)))
        }

        let restoreInteractionResult: BackupArchive.RestoreInteractionResult<Void>
        switch chatItem.directionalDetails {
        case nil:
            return .unrecognizedEnum(BackupArchive.UnrecognizedEnumError(
                enumType: BackupProto_ChatItem.OneOf_DirectionalDetails.self,
            ))
        case .incoming:
            restoreInteractionResult = incomingMessageArchiver.restoreIncomingChatItem(
                chatItem,
                chatThread: thread,
                context: context,
            )
        case .outgoing:
            restoreInteractionResult = outgoingMessageArchiver.restoreChatItem(
                chatItem,
                chatThread: thread,
                context: context,
            )
        case .directionless:
            switch chatItem.item {
            case nil:
                return .unrecognizedEnum(BackupArchive.UnrecognizedEnumError(
                    enumType: BackupProto_ChatItem.OneOf_Item.self,
                ))
            case
                .standardMessage,
                .contactMessage,
                .giftBadge,
                .viewOnceMessage,
                .paymentNotification,
                .remoteDeletedMessage,
                .stickerMessage,
                .directStoryReplyMessage,
                .poll:
                return restoreFrameError(.invalidProtoData(.directionlessChatItemNotUpdateMessage))
            case .updateMessage:
                restoreInteractionResult = chatUpdateMessageArchiver.restoreChatItem(
                    chatItem,
                    chatThread: thread,
                    context: context,
                )
            }
        }

        switch restoreInteractionResult {
        case .success:
            return .success
        case .unrecognizedEnum(let error):
            return .unrecognizedEnum(error)
        case .partialRestore(_, let errors):
            return .partialRestore(errors)
        case .messageFailure(let errors):
            return .failure(errors)
        }
    }
}
