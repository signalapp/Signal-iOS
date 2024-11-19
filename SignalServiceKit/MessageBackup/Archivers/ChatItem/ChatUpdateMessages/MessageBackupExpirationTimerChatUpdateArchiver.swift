//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// An archiver for expiration timer chat updates in contact threads.
///
/// - Important
/// This class only handles expiration timer updates for 1:1 threads. Updates in
/// group threads use ``MessageBackupGroupUpdateMessageArchiver``, rely on
/// "group update metadata" being present on the info message, and use a
/// different `BackupProto` type.
final class MessageBackupExpirationTimerChatUpdateArchiver {
    typealias Details = MessageBackup.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = MessageBackup.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = MessageBackup.RestoreInteractionResult<Void>

    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let contactManager: MessageBackup.Shims.ContactManager
    private let groupUpdateArchiver: MessageBackupGroupUpdateMessageArchiver
    private let interactionStore: MessageBackupInteractionStore

    init(
        contactManager: MessageBackup.Shims.ContactManager,
        groupUpdateArchiver: MessageBackupGroupUpdateMessageArchiver,
        interactionStore: MessageBackupInteractionStore
    ) {
        self.contactManager = contactManager
        self.groupUpdateArchiver = groupUpdateArchiver
        self.interactionStore = interactionStore
    }

    // MARK: -

    func archiveExpirationTimerChatUpdate(
        infoMessage: TSInfoMessage,
        threadInfo: MessageBackup.ChatArchivingContext.CachedThreadInfo,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {
        func messageFailure(
            _ errorType: ArchiveFrameError.ErrorType,
            line: UInt = #line
        ) -> ArchiveChatUpdateMessageResult {
            return .messageFailure([.archiveFrameError(
                errorType,
                infoMessage.uniqueInteractionId,
                line: line
            )])
        }

        guard let dmUpdateInfoMessage = infoMessage as? OWSDisappearingConfigurationUpdateInfoMessage else {
            return messageFailure(.disappearingMessageConfigUpdateNotExpectedSDSRecordType)
        }

        // If the "remote name" is `nil`, the author is the local user.
        let wasAuthoredByLocalUser = dmUpdateInfoMessage.createdByRemoteName == nil

        let chatUpdateExpiresInMs: UInt64
        if dmUpdateInfoMessage.configurationIsEnabled {
            chatUpdateExpiresInMs = UInt64(dmUpdateInfoMessage.configurationDurationSeconds) * kSecondInMs
        } else {
            chatUpdateExpiresInMs = 0
        }

        let recipientAddress: MessageBackup.ContactAddress?
        switch threadInfo {
        case .contactThread(let contactAddress):
            recipientAddress = contactAddress
        case .groupThread:
            // This may have been a DM timer update in a gv1 group that became a gv2 group;
            // we can't tell anymore if this group was ever gv1 so just assume so
            // and swizzle this to a gv2 timer update for backup purposes.
            return swizzleGV1ExpirationTimerChatUpdateToGV2Update(
                dmUpdateInfoMessage: dmUpdateInfoMessage,
                wasAuthoredByLocalUser: wasAuthoredByLocalUser,
                updatedExpiresInMs: chatUpdateExpiresInMs,
                context: context
            )
        }

        let chatUpdateAuthorRecipientId: MessageBackup.RecipientId
        if wasAuthoredByLocalUser {
            chatUpdateAuthorRecipientId = context.recipientContext.localRecipientId
        } else {
            guard let recipientAddress else {
                return messageFailure(.disappearingMessageConfigUpdateMissingAuthor)
            }
            guard let recipientId = context.recipientContext[.contact(recipientAddress)] else {
                return messageFailure(.referencedRecipientIdMissing(.contact(recipientAddress)))
            }

            chatUpdateAuthorRecipientId = recipientId
        }

        var expirationTimerChatUpdate = BackupProto_ExpirationTimerChatUpdate()
        expirationTimerChatUpdate.expiresInMs = chatUpdateExpiresInMs

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .expirationTimerChange(expirationTimerChatUpdate)

        let interactionArchiveDetails = Details(
            author: chatUpdateAuthorRecipientId,
            directionalDetails: .directionless(BackupProto_ChatItem.DirectionlessMessageDetails()),
            dateCreated: infoMessage.timestamp,
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdateMessage),
            isSmsPreviouslyRestoredFromBackup: false
        )

        return .success(interactionArchiveDetails)
    }

    /// Its possible to have had a gv1 group that had an expiration timer
    /// update, then migrate the group to gv2. We need to swizzle that
    /// OWSDisappearingConfigurationUpdateInfoMessage into a group update proto.
    private func swizzleGV1ExpirationTimerChatUpdateToGV2Update(
        dmUpdateInfoMessage: OWSDisappearingConfigurationUpdateInfoMessage,
        wasAuthoredByLocalUser: Bool,
        updatedExpiresInMs: UInt64,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {

        let swizzledGroupUpdateItem: TSInfoMessage.PersistableGroupUpdateItem
        if dmUpdateInfoMessage.configurationIsEnabled {
            swizzledGroupUpdateItem = wasAuthoredByLocalUser
                ? .disappearingMessagesEnabledByLocalUser(durationMs: updatedExpiresInMs)
                : .disappearingMessagesEnabledByUnknownUser(durationMs: updatedExpiresInMs)
        } else {
            swizzledGroupUpdateItem = wasAuthoredByLocalUser
                ? .disappearingMessagesDisabledByLocalUser
                : .disappearingMessagesDisabledByUnknownUser
        }

        return groupUpdateArchiver.archiveGroupUpdateItems(
            [swizzledGroupUpdateItem],
            for: dmUpdateInfoMessage,
            context: context
        )
    }

    // MARK: -

    func restoreExpirationTimerChatUpdate(
        _ expirationTimerChatUpdate: BackupProto_ExpirationTimerChatUpdate,
        chatItem: BackupProto_ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreChatUpdateMessageResult {
        func invalidProtoData(
            _ error: RestoreFrameError.ErrorType.InvalidProtoDataError,
            line: UInt = #line
        ) -> RestoreChatUpdateMessageResult {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(error),
                chatItem.id,
                line: line
            )])
        }

        let contactThread: TSContactThread
        switch chatThread.threadType {
        case .contact(let _contactThread):
            contactThread = _contactThread
        case .groupV2:
            return invalidProtoData(.expirationTimerUpdateNotInContactThread)
        }

        guard let expiresInSeconds: UInt32 = .msToSecs(expirationTimerChatUpdate.expiresInMs) else {
            return invalidProtoData(.expirationTimerOverflowedLocalType)
        }

        let createdByRemoteName: String?
        switch context.recipientContext[chatItem.authorRecipientId] {
        case nil:
            return invalidProtoData(.recipientIdNotFound(chatItem.authorRecipientId))
        case .localAddress:
            createdByRemoteName = nil
        default:
            createdByRemoteName = contactManager.displayName(contactThread.contactAddress, tx: context.tx)
        }

        let dmUpdateInfoMessage = OWSDisappearingConfigurationUpdateInfoMessage(
            contactThread: contactThread,
            timestamp: chatItem.dateSent,
            isConfigurationEnabled: expiresInSeconds > 0,
            configurationDurationSeconds: UInt32(clamping: expiresInSeconds), // Safe to clamp, we checked for overflow above
            createdByRemoteName: createdByRemoteName
        )

        guard let directionalDetails = chatItem.directionalDetails else {
            return invalidProtoData(.chatItemMissingDirectionalDetails)
        }

        do {
            try interactionStore.insert(
                dmUpdateInfoMessage,
                in: chatThread,
                chatId: chatItem.typedChatId,
                directionalDetails: directionalDetails,
                context: context
            )
        } catch let error {
            return .messageFailure([.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
        }

        return .success(())
    }
}
