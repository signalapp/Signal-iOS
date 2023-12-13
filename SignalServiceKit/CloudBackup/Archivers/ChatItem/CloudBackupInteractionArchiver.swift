//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension CloudBackup {

    /// We use the timestamp (``BackupProtoChatItem.dateSent``) to identify chat items.
    public typealias ChatItemId = UInt64

    internal enum ChatItemMessageType {
        case standard(BackupProtoStandardMessage)
        case contact(BackupProtoContactMessage)
        case voice(BackupProtoVoiceMessage)
        case sticker(BackupProtoStickerMessage)
        case remotelyDeleted(BackupProtoRemoteDeletedMessage)
        case chatUpdate(BackupProtoUpdateMessage)

        init?(_ chatItem: BackupProtoChatItem) {
            if let standardMessage = chatItem.standardMessage {
                self = .standard(standardMessage)
            } else if let contactMessage = chatItem.contactMessage {
                self = .contact(contactMessage)
            } else if let voiceMessage = chatItem.voiceMessage {
                self = .voice(voiceMessage)
            } else if let stickerMessage = chatItem.stickerMessage {
                self = .sticker(stickerMessage)
            } else if let remoteDeletedMessage = chatItem.remoteDeletedMessage {
                self = .remotelyDeleted(remoteDeletedMessage)
            } else if let updateMessage = chatItem.updateMessage {
                self = .chatUpdate(updateMessage)
            } else {
                owsFailDebug("Unknown chat item type!")
                return nil
            }
        }
    }

    internal struct InteractionArchiveDetails {
        enum DirectionalDetails {
            case incoming(BackupProtoChatItemIncomingMessageDetails)
            case outgoing(BackupProtoChatItemOutgoingMessageDetails)
            // TODO: do we need to modify the proto schema for local
            // messages that are neither incoming nor outgoing?
            // Or do we just call them outgoing, with no recipients?
        }

        let author: RecipientId
        let directionalDetails: DirectionalDetails
        let expireStartDate: UInt64?
        let expiresInMs: UInt64?
        // TODO: edit revisions
        let revisions: [BackupProtoChatItem] = []
        // TODO: sms
        let isSms: Bool = false
        let type: ChatItemMessageType
    }

    internal enum ArchiveInteractionResult<Component> {
        typealias Error = CloudBackupChatItemArchiver.ArchiveMultiFrameResult.Error

        case success(Component)

        // MARK: Skips

        /// This is a past revision that was since edited; can be safely skipped, as its
        /// contents will be represented in the latest revision.
        case isPastRevision
        // TODO: we should just not interate over story messages down in the SQL query.
        // we don't back these up cuz they expire within 24 hours anyway.
        case isStoryMessage
        // TODO: remove this once we flesh out implementation for all interactions.
        case notYetImplemented

        // MARK: Errors

        /// Some portion of the interaction failed to archive, but we can still archive the rest of it.
        /// e.g. some recipient details are missing, so we archive without that recipient.
        case partialFailure(Component, [Error])
        /// The entire message failed and should be skipped.
        /// Other messages are unaffected.
        case messageFailure([Error])
        /// Catastrophic failure, which should stop _all_ message archiving.
        case completeFailure(Swift.Error)
    }
}

internal protocol CloudBackupInteractionArchiver: CloudBackupProtoArchiver {

    typealias Details = CloudBackup.InteractionArchiveDetails

    static func canArchiveInteraction(_ interaction: TSInteraction) -> Bool

    func archiveInteraction(
        _ interaction: TSInteraction,
        context: CloudBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> CloudBackup.ArchiveInteractionResult<Details>

    typealias RestoreFrameResult = CloudBackup.RestoreFrameResult<CloudBackup.ChatItemId>

    static func canRestoreChatItem(_ chatItem: BackupProtoChatItem) -> Bool

    func restoreChatItem(
        _ chatItem: BackupProtoChatItem,
        thread: TSThread,
        context: CloudBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult
}

extension BackupProtoChatItem {

    var messageType: CloudBackup.ChatItemMessageType? {
        return .init(self)
    }
}
