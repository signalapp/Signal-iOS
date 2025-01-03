//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

final class MessageBackupSimpleChatUpdateArchiver {
    typealias Details = MessageBackup.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = MessageBackup.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = MessageBackup.RestoreInteractionResult<Void>

    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let logger: MessageBackupLogger = .shared

    private let interactionStore: MessageBackupInteractionStore

    init(interactionStore: MessageBackupInteractionStore) {
        self.interactionStore = interactionStore
    }

    // MARK: -

    func archiveSimpleChatUpdate(
        infoMessage: TSInfoMessage,
        threadInfo: MessageBackup.ChatArchivingContext.CachedThreadInfo,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {
        func messageFailure(
            _ error: ArchiveFrameError.ErrorType,
            line: UInt = #line
        ) -> ArchiveChatUpdateMessageResult {
            return .messageFailure([.archiveFrameError(
                error,
                infoMessage.uniqueInteractionId,
                line: line
            )])
        }

        /// To whom we should attribute this update.
        enum UpdateAuthor {
            /// A recipient ID computed while computing the update type. Useful
            /// if the update might appear in either a 1:1 or group thread.
            case precomputedRecipientId(MessageBackup.RecipientId)
            /// The contact whose 1:1 thread this update appears in. This
            /// produces a failure if the update was in fact in a group.
            case containingContactThread
            /// The local user.
            case localUser
        }

        let updateAuthor: UpdateAuthor
        let updateType: BackupProto_SimpleChatUpdate.TypeEnum

        switch infoMessage.messageType {
        case
                .userNotRegistered,
                .typeUnsupportedMessage,
                .typeGroupQuit,
                .addToContactsOffer,
                .addUserToProfileWhitelistOffer,
                .addGroupToProfileWhitelistOffer,
                .syncedThread:
            // Skipped legacy types
            fallthrough
        case .recipientHidden:
            // Specifically-skipped and specially-handled type
            fallthrough
        case
                .typeGroupUpdate,
                .typeDisappearingMessagesUpdate,
                .profileUpdate,
                .threadMerge,
                .sessionSwitchover,
                .learnedProfileName:
            // Non-simple chat update types
            return .completeFailure(.fatalArchiveError(
                .developerError(OWSAssertionError("Unexpected info message type: \(infoMessage.messageType)"))
            ))
        case .verificationStateChange:
            guard let verificationStateChangeMessage = infoMessage as? OWSVerificationStateChangeMessage else {
                return messageFailure(.verificationStateChangeNotExpectedSDSRecordType)
            }

            /// This type of info message historically put the user who had the
            /// verification-state change in the `recipientAddress` field.
            guard let recipientAddress = verificationStateChangeMessage.recipientAddress.asSingleServiceIdBackupAddress() else {
                return messageFailure(.verificationStateUpdateInteractionMissingAuthor)
            }

            guard let recipientId = context.recipientContext[.contact(recipientAddress)] else {
                return messageFailure(.referencedRecipientIdMissing(.contact(recipientAddress)))
            }

            updateAuthor = .precomputedRecipientId(recipientId)

            switch verificationStateChangeMessage.verificationState {
            case .default, .defaultAcknowledged, .noLongerVerified:
                updateType = .identityDefault
            case .verified:
                updateType = .identityVerified
            }
        case .phoneNumberChange:
            guard let changedNumberUserAci = infoMessage.phoneNumberChangeInfo()?.aci else {
                return messageFailure(.phoneNumberChangeInteractionMissingAuthor)
            }

            let recipientAddress = MessageBackup.ContactAddress(aci: changedNumberUserAci)
            guard let recipientId = context.recipientContext[.contact(recipientAddress)] else {
                return messageFailure(.referencedRecipientIdMissing(.contact(recipientAddress)))
            }

            updateAuthor = .precomputedRecipientId(recipientId)
            updateType = .changeNumber
        case .paymentsActivationRequest:
            switch infoMessage.paymentsActivationRequestAuthor(localIdentifiers: context.recipientContext.localIdentifiers) {
            case nil:
                return messageFailure(.paymentActivationRequestInteractionMissingAuthor)
            case .localUser:
                updateAuthor = .localUser
            case .otherUser(let aci):
                let authorAddress = MessageBackup.ContactAddress(aci: aci)
                guard let authorRecipientId = context.recipientContext[.contact(authorAddress)] else {
                    return messageFailure(.referencedRecipientIdMissing(.contact(authorAddress)))
                }

                updateAuthor = .precomputedRecipientId(authorRecipientId)
            }

            updateType = .paymentActivationRequest
        case .paymentsActivated:
            switch infoMessage.paymentsActivatedAuthor(localIdentifiers: context.recipientContext.localIdentifiers) {
            case nil:
                return messageFailure(.paymentsActivatedInteractionMissingAuthor)
            case .localUser:
                updateAuthor = .localUser
            case .otherUser(let aci):
                let authorAddress = MessageBackup.ContactAddress(aci: aci)
                guard let authorRecipientId = context.recipientContext[.contact(authorAddress)] else {
                    return messageFailure(.referencedRecipientIdMissing(.contact(authorAddress)))
                }

                updateAuthor = .precomputedRecipientId(authorRecipientId)
            }

            updateType = .paymentsActivated
        case .unknownProtocolVersion:
            guard let unknownProtocolVersionMessage = infoMessage as? OWSUnknownProtocolVersionMessage else {
                return messageFailure(.unknownProtocolVersionNotExpectedSDSRecordType)
            }

            /// This type of info message historically put the user who sent the
            /// unknown-protocol message in the `sender` field, or `nil` if it
            /// was ourselves.
            if let senderAddress = unknownProtocolVersionMessage.sender?.asSingleServiceIdBackupAddress() {
                guard let recipientId = context.recipientContext[.contact(senderAddress)] else {
                    return messageFailure(.referencedRecipientIdMissing(.contact(senderAddress)))
                }

                updateAuthor = .precomputedRecipientId(recipientId)
            } else {
                // This would be because we got a sync transcript of a message
                // with an unknown protocol version.
                updateAuthor = .localUser
            }

            updateType = .unsupportedProtocolMessage
        case .typeRemoteUserEndedSession:
            // Only inserted for 1:1 threads.
            updateAuthor = .containingContactThread
            updateType = .endSession
        case .typeLocalUserEndedSession:
            updateAuthor = .localUser
            updateType = .endSession
        case .userJoinedSignal:
            // Only inserted for 1:1 threads.
            updateAuthor = .containingContactThread
            updateType = .joinedSignal
        case .reportedSpam:
            // The reported-spam info message doesn't contain any info as to
            // what message we reported spam. Regardless, we were the one to
            // take this action, so we're the author.
            updateAuthor = .localUser
            updateType = .reportedSpam
        case .blockedOtherUser, .blockedGroup:
            // We blocked, so we're the author.
            //
            // These messages are the same in a Backup, and disambiguated at
            // restore-time by the type of chat thread they're in.
            updateAuthor = .localUser
            updateType = .blocked
        case .unblockedOtherUser, .unblockedGroup:
            // We unblocked, so we're the author.
            //
            // These messages are the same in a Backup, and disambiguated at
            // restore-time by the type of chat thread they're in.
            updateAuthor = .localUser
            updateType = .unblocked
        case .acceptedMessageRequest:
            // We accepted, so we're the author.
            updateAuthor = .localUser
            updateType = .messageRequestAccepted
        }

        let updateAuthorRecipientId: MessageBackup.RecipientId
        switch updateAuthor {
        case .precomputedRecipientId(let recipientId):
            updateAuthorRecipientId = recipientId
        case .containingContactThread:
            switch threadInfo {
            case .groupThread:
                return messageFailure(.simpleChatUpdateMessageNotInContactThread)
            case .contactThread(let authorAddress):
                guard let authorAddress else {
                    return messageFailure(.simpleChatUpdateMessageNotInContactThread)
                }
                guard let authorRecipientId = context.recipientContext[.contact(authorAddress)] else {
                    return messageFailure(.referencedRecipientIdMissing(.contact(authorAddress)))
                }
                updateAuthorRecipientId = authorRecipientId
            }
        case .localUser:
            updateAuthorRecipientId = context.recipientContext.localRecipientId
        }

        var simpleChatUpdate = BackupProto_SimpleChatUpdate()
        simpleChatUpdate.type = updateType

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .simpleUpdate(simpleChatUpdate)

        let interactionArchiveDetails = Details(
            author: updateAuthorRecipientId,
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

    func archiveSimpleChatUpdate(
        errorMessage: TSErrorMessage,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {
        func messageFailure(
            _ error: ArchiveFrameError.ErrorType,
            line: UInt = #line
        ) -> ArchiveChatUpdateMessageResult {
            return .messageFailure([.archiveFrameError(
                error,
                errorMessage.uniqueInteractionId,
                line: line
            )])
        }

        /// To whom we should attribute this update.
        enum UpdateAuthor {
            case localUser
            case remoteUser(MessageBackup.ContactAddress)
        }

        let updateAuthor: UpdateAuthor
        let updateType: BackupProto_SimpleChatUpdate.TypeEnum

        switch errorMessage.errorType {
        case .noSession:
            return .skippableChatUpdate(.legacyErrorMessage(.noSession))
        case .wrongTrustedIdentityKey:
            return .skippableChatUpdate(.legacyErrorMessage(.wrongTrustedIdentityKey))
        case .invalidKeyException:
            return .skippableChatUpdate(.legacyErrorMessage(.invalidKeyException))
        case .missingKeyId:
            return .skippableChatUpdate(.legacyErrorMessage(.missingKeyId))
        case .invalidMessage:
            return .skippableChatUpdate(.legacyErrorMessage(.invalidMessage))
        case .duplicateMessage:
            return .skippableChatUpdate(.legacyErrorMessage(.duplicateMessage))
        case .invalidVersion:
            return .skippableChatUpdate(.legacyErrorMessage(.invalidVersion))
        case .unknownContactBlockOffer:
            return .skippableChatUpdate(.legacyErrorMessage(.unknownContactBlockOffer))
        case .groupCreationFailed:
            return .skippableChatUpdate(.legacyErrorMessage(.groupCreationFailed))
        case .nonBlockingIdentityChange:
            /// This type of error message historically put the person with the
            /// identity-key change on the `recipientAddress` property.
            guard let recipientAddress = errorMessage.recipientAddress?.asSingleServiceIdBackupAddress() else {
                return messageFailure(.identityKeyChangeInteractionMissingAuthor)
            }

            updateType = .identityUpdate
            updateAuthor = .remoteUser(recipientAddress)
        case .sessionRefresh:
            /// We always generate these ourselves.
            updateType = .chatSessionRefresh
            updateAuthor = .localUser
        case .decryptionFailure:
            /// This type of error message historically put the person who sent
            /// the failed-to-decrypt message in the `sender` property.
            guard let recipientAddress = errorMessage.sender?.asSingleServiceIdBackupAddress() else {
                return messageFailure(.decryptionErrorInteractionMissingAuthor)
            }

            updateType = .badDecrypt
            updateAuthor = .remoteUser(recipientAddress)
        }

        let updateAuthorRecipientId: MessageBackup.RecipientId
        switch updateAuthor {
        case .localUser:
            updateAuthorRecipientId = context.recipientContext.localRecipientId
        case .remoteUser(let contactAddress):
            guard let _updateAuthorRecipientId = context.recipientContext[.contact(contactAddress)] else {
                return messageFailure(.referencedRecipientIdMissing(.contact(contactAddress)))
            }

            updateAuthorRecipientId = _updateAuthorRecipientId
        }

        var simpleChatUpdate = BackupProto_SimpleChatUpdate()
        simpleChatUpdate.type = updateType

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .simpleUpdate(simpleChatUpdate)

        let interactionArchiveDetails = Details(
            author: updateAuthorRecipientId,
            directionalDetails: .directionless(BackupProto_ChatItem.DirectionlessMessageDetails()),
            dateCreated: errorMessage.timestamp,
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdateMessage),
            isSmsPreviouslyRestoredFromBackup: false
        )

        return .success(interactionArchiveDetails)
    }

    // MARK: -

    func restoreSimpleChatUpdate(
        _ simpleChatUpdate: BackupProto_SimpleChatUpdate,
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

        enum SimpleChatUpdateInteraction {
            case simpleInfoMessage(TSInfoMessageType)
            case prebuiltInfoMessage(TSInfoMessage)
            case errorMessage(TSErrorMessage)
        }

        let thread: TSThread = chatThread.tsThread
        let simpleChatUpdateInteraction: SimpleChatUpdateInteraction

        switch simpleChatUpdate.type {
        case .unknown, .UNRECOGNIZED:
            return invalidProtoData(.unrecognizedSimpleChatUpdate)
        case .joinedSignal:
            simpleChatUpdateInteraction = .simpleInfoMessage(.userJoinedSignal)
        case .identityUpdate:
            guard let verificationRecipient = context.recipientContext[chatItem.authorRecipientId] else {
                return invalidProtoData(.recipientIdNotFound(chatItem.authorRecipientId))
            }
            guard case .contact(let contactAddress) = verificationRecipient else {
                return invalidProtoData(.verificationStateChangeNotFromContact)
            }

            simpleChatUpdateInteraction = .errorMessage(.nonblockingIdentityChange(
                thread: thread,
                timestamp: chatItem.dateSent,
                // We'll use the author of this chat item as the user whose
                // identity key changed.
                address: contactAddress.asInteropAddress(),
                // We'll fudge and conservatively say that the identity was not
                // previously verified since we don't have it tracked in the
                // backup and it only affects the action shown for the message.
                wasIdentityVerified: false
            ))
        case .identityVerified, .identityDefault:
            guard let verificationRecipient = context.recipientContext[chatItem.authorRecipientId] else {
                return invalidProtoData(.recipientIdNotFound(chatItem.authorRecipientId))
            }
            guard case .contact(let contactAddress) = verificationRecipient else {
                return invalidProtoData(.verificationStateChangeNotFromContact)
            }

            let verificationState: OWSVerificationState = switch simpleChatUpdate.type {
            case .identityVerified: .verified
            case .identityDefault: .default
            default: owsFail("Impossible: checked above.")
            }

            simpleChatUpdateInteraction = .prebuiltInfoMessage(OWSVerificationStateChangeMessage(
                thread: thread,
                timestamp: chatItem.dateSent,
                // We'll use the author of this chat item as the user whose
                // verification state changed.
                recipientAddress: contactAddress.asInteropAddress(),
                verificationState: verificationState,
                // We don't know which device this update originated on, so
                // we'll pretend it was the local. This only affects the way the
                // message is displayed.
                isLocalChange: true
            ))
        case .changeNumber:
            guard let verificationRecipient = context.recipientContext[chatItem.authorRecipientId] else {
                return invalidProtoData(.recipientIdNotFound(chatItem.authorRecipientId))
            }
            guard
                case .contact(let contactAddress) = verificationRecipient,
                let aci = contactAddress.aci
            else {
                return invalidProtoData(.phoneNumberChangeNotFromContact)
            }

            simpleChatUpdateInteraction = .prebuiltInfoMessage(.makeForPhoneNumberChange(
                thread: thread,
                timestamp: chatItem.dateSent,
                aci: aci,
                oldNumber: nil,
                newNumber: nil
            ))
        case .releaseChannelDonationRequest:
            // TODO: [Backups] Add support (and a test case!) for this once we've implemented the Release Notes channel.
            logger.warn("Encountered not-yet-supported release-channel-donation-request update")
            return .success(())
        case .endSession:
            guard let senderRecipient = context.recipientContext[chatItem.authorRecipientId] else {
                return invalidProtoData(.recipientIdNotFound(chatItem.authorRecipientId))
            }
            let infoMessageType: TSInfoMessageType
            switch senderRecipient {
            case .localAddress:
                infoMessageType = .typeLocalUserEndedSession
            case .contact:
                infoMessageType = .typeRemoteUserEndedSession
            case .releaseNotesChannel, .group, .distributionList, .callLink:
                return invalidProtoData(.endSessionNotFromContact)
            }

            simpleChatUpdateInteraction = .simpleInfoMessage(infoMessageType)
        case .chatSessionRefresh:
            simpleChatUpdateInteraction = .errorMessage(.sessionRefresh(
                thread: thread,
                timestamp: chatItem.dateSent
            ))
        case .badDecrypt:
            guard let senderRecipient = context.recipientContext[chatItem.authorRecipientId] else {
                return invalidProtoData(.recipientIdNotFound(chatItem.authorRecipientId))
            }
            let contactAddress: MessageBackup.InteropAddress
            switch senderRecipient {
            case .localAddress:
                contactAddress = context.recipientContext.localIdentifiers.aciAddress
            case .contact(let _contactAddress):
                contactAddress = _contactAddress.asInteropAddress()
            case .releaseNotesChannel, .group, .distributionList, .callLink:
                return invalidProtoData(.decryptionErrorNotFromContact)
            }

            simpleChatUpdateInteraction = .errorMessage(.failedDecryption(
                thread: thread,
                timestamp: chatItem.dateSent,
                sender: contactAddress
            ))
        case .paymentsActivated:
            let senderAci: Aci
            switch context.recipientContext[chatItem.authorRecipientId] {
            case nil:
                return invalidProtoData(.recipientIdNotFound(chatItem.authorRecipientId))
            case .localAddress:
                senderAci = context.recipientContext.localIdentifiers.aci
            case .contact(let contactAddress):
                guard let aci = contactAddress.aci else { fallthrough }
                senderAci = aci
            case .releaseNotesChannel, .group, .distributionList, .callLink:
                return invalidProtoData(.paymentsActivatedNotFromAci)
            }

            simpleChatUpdateInteraction = .prebuiltInfoMessage(.paymentsActivatedMessage(
                thread: thread,
                timestamp: chatItem.dateSent,
                senderAci: senderAci
            ))
        case .paymentActivationRequest:
            let senderAci: Aci
            switch context.recipientContext[chatItem.authorRecipientId] {
            case nil:
                return invalidProtoData(.recipientIdNotFound(chatItem.authorRecipientId))
            case .localAddress:
                senderAci = context.recipientContext.localIdentifiers.aci
            case .contact(let contactAddress):
                guard let aci = contactAddress.aci else { fallthrough }
                senderAci = aci
            case .releaseNotesChannel, .group, .distributionList, .callLink:
                return invalidProtoData(.paymentsActivatedNotFromAci)
            }

            simpleChatUpdateInteraction = .prebuiltInfoMessage(.paymentsActivationRequestMessage(
                thread: thread,
                timestamp: chatItem.dateSent,
                senderAci: senderAci
            ))
        case .unsupportedProtocolMessage:
            let senderAddress: SignalServiceAddress?
            switch context.recipientContext[chatItem.authorRecipientId] {
            case nil:
                return invalidProtoData(.recipientIdNotFound(chatItem.authorRecipientId))
            case .localAddress:
                senderAddress = nil
            case .contact(let contactAddress):
                senderAddress = contactAddress.asInteropAddress()
            case .releaseNotesChannel, .group, .distributionList, .callLink:
                return invalidProtoData(.unsupportedProtocolVersionNotFromContact)
            }

            simpleChatUpdateInteraction = .prebuiltInfoMessage(OWSUnknownProtocolVersionMessage(
                thread: thread,
                timestamp: chatItem.dateSent,
                sender: senderAddress,
                // This isn't quite right, but we don't have the required
                // protocol version for this message in the backup. Setting it
                // to the highest we can insert into the DB ensures this message
                // will always show "unknown protocol version", but that's fine.
                protocolVersion: UInt(Int64.max)
            ))
        case .reportedSpam:
            simpleChatUpdateInteraction = .simpleInfoMessage(.reportedSpam)
        case .blocked:
            switch chatThread.threadType {
            case .contact:
                simpleChatUpdateInteraction = .simpleInfoMessage(.blockedOtherUser)
            case .groupV2:
                simpleChatUpdateInteraction = .simpleInfoMessage(.blockedGroup)
            }
        case .unblocked:
            switch chatThread.threadType {
            case .contact:
                simpleChatUpdateInteraction = .simpleInfoMessage(.unblockedOtherUser)
            case .groupV2:
                simpleChatUpdateInteraction = .simpleInfoMessage(.unblockedGroup)
            }
        case .messageRequestAccepted:
            simpleChatUpdateInteraction = .simpleInfoMessage(.acceptedMessageRequest)
        }

        guard let directionalDetails = chatItem.directionalDetails else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.chatItemMissingDirectionalDetails),
                chatItem.id
            )])
        }

        switch simpleChatUpdateInteraction {
        case .simpleInfoMessage(let infoMessageType):
            let infoMessage = TSInfoMessage(
                thread: thread,
                messageType: infoMessageType,
                timestamp: chatItem.dateSent
            )
            do {
                try interactionStore.insert(
                    infoMessage,
                    in: chatThread,
                    chatId: chatItem.typedChatId,
                    directionalDetails: directionalDetails,
                    context: context
                )
            } catch let error {
                return .messageFailure([.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
            }
        case .prebuiltInfoMessage(let infoMessage):
            do {
                try interactionStore.insert(
                    infoMessage,
                    in: chatThread,
                    chatId: chatItem.typedChatId,
                    directionalDetails: directionalDetails,
                    context: context
                )
            } catch let error {
                return .messageFailure([.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
            }
        case .errorMessage(let errorMessage):
            do {
                try interactionStore.insert(
                    errorMessage,
                    in: chatThread,
                    chatId: chatItem.typedChatId,
                    directionalDetails: directionalDetails,
                    context: context
                )
            } catch let error {
                return .messageFailure([.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
            }
        }

        return .success(())
    }
}
