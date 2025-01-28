//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {
    public struct InteractionUniqueId: MessageBackupLoggableId, Hashable {
        let value: String
        let timestamp: UInt64

        public init(interaction: TSInteraction) {
            self.value = interaction.uniqueId
            self.timestamp = interaction.timestamp
        }

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "TSInteraction" }
        public var idLogString: String { "\(value):\(timestamp)" }
    }
}

extension BackupProto_ChatItem {
    var id: MessageBackup.ChatItemId {
        return .init(backupProtoChatItem: self)
    }
}

extension TSInteraction {
    var uniqueInteractionId: MessageBackup.InteractionUniqueId {
        return .init(interaction: self)
    }

    var chatItemId: MessageBackup.ChatItemId {
        return .init(interaction: self)
    }
}

// MARK: -

extension MessageBackup {

    struct InteractionArchiveDetails {
        typealias DirectionalDetails = BackupProto_ChatItem.OneOf_DirectionalDetails
        typealias ChatItemType = BackupProto_ChatItem.OneOf_Item

        let author: RecipientId
        let directionalDetails: DirectionalDetails
        let dateCreated: UInt64
        let expireStartDate: UInt64?
        let expiresInMs: UInt64?
        let isSealedSender: Bool
        let chatItemType: ChatItemType

        /// - SeeAlso: ``TSMessage/isSmsMessageRestoredFromBackup``
        let isSmsPreviouslyRestoredFromBackup: Bool

        /// Represents past revisions, if this instance represents the final
        /// form of a message that was edited.
        private(set) var pastRevisions: [InteractionArchiveDetails] = []

        mutating func addPastRevision(_ pastRevision: InteractionArchiveDetails) {
            pastRevisions.append(pastRevision)
        }

        public enum AuthorAddress {
            case localUser
            case contact(MessageBackup.ContactAddress)
        }

        private init(
            author: RecipientId,
            directionalDetails: DirectionalDetails,
            dateCreated: UInt64,
            expireStartDate: UInt64?,
            expiresInMs: UInt64?,
            isSealedSender: Bool,
            chatItemType: ChatItemType,
            isSmsPreviouslyRestoredFromBackup: Bool,
            pastRevisions: [InteractionArchiveDetails]
        ) {
            self.author = author
            self.directionalDetails = directionalDetails
            self.dateCreated = dateCreated
            self.expireStartDate = expireStartDate
            self.expiresInMs = expiresInMs
            self.isSealedSender = isSealedSender
            self.chatItemType = chatItemType
            self.isSmsPreviouslyRestoredFromBackup = isSmsPreviouslyRestoredFromBackup
            self.pastRevisions = pastRevisions
        }

        static func validateAndBuild(
            interactionUniqueId: InteractionUniqueId,
            author: AuthorAddress,
            directionalDetails: DirectionalDetails,
            dateCreated: UInt64,
            expireStartDate: UInt64?,
            expiresInMs: UInt64?,
            isSealedSender: Bool,
            chatItemType: ChatItemType,
            isSmsPreviouslyRestoredFromBackup: Bool,
            pastRevisions: [InteractionArchiveDetails] = [],
            threadInfo: MessageBackup.ChatArchivingContext.CachedThreadInfo,
            context: MessageBackup.RecipientArchivingContext
        ) -> MessageBackup.ArchiveInteractionResult<Self> {
            var authorRecipientId: RecipientId
            var author = author
            switch author {
            case .localUser:
                authorRecipientId = context.localRecipientId
            case .contact(let contactAddress):
                guard let recipientId = context[.contact(contactAddress)] else {
                    return .messageFailure([.archiveFrameError(
                        .referencedRecipientIdMissing(.contact(contactAddress)),
                        interactionUniqueId
                    )])
                }
                authorRecipientId = recipientId
                if authorRecipientId == context.localRecipientId {
                    author = .localUser
                }
            }

            var partialErrors = [MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>]()
            for timestamp in [dateCreated, expireStartDate, expiresInMs] {
                switch MessageBackup.Timestamps.validateTimestamp(timestamp).bubbleUp(Self.self, partialErrors: &partialErrors) {
                case .continue:
                    break
                case .bubbleUpError(let error):
                    return error
                }
            }

            switch (threadInfo, author) {
            case (.groupThread, _), (.contactThread, .localUser):
                break
            case (.contactThread(let threadContactAddress), .contact(let authorAddress)):
                let threadRecipientId = threadContactAddress.map { context[.contact($0)] } ?? nil

                // If this message is in a contact thread, the author must either
                // be the local user or that contact.
                if let threadRecipientId, threadRecipientId != authorRecipientId {
                    // There's a mismatch; the author of the message
                    // isn't in the 1:1 chat. This can happen if...
                    // * some chat pre- introduction of ACIs where
                    //   the contact later changed number. The author
                    //   on the message would be e164-only with the old
                    //   number, not matching the thread.
                    // * some chat that existed pre- introduction of ACIs
                    //   received a message after ACIs existed and
                    //   _hallucinated_ an ACI that it then wrote into
                    //   the message's authorUUID column.
                    //
                    // In any case, we recover from this by swizzling
                    // the author on export to the chat-level author,
                    // which is more trustworthy.
                    authorRecipientId = threadRecipientId
                    // Add a partial error so we log these.
                    partialErrors.append(.archiveFrameError(
                        .messageFromOtherRecipientInContactThread,
                        interactionUniqueId
                    ))
                }
            }

            let details = InteractionArchiveDetails(
                author: authorRecipientId,
                directionalDetails: directionalDetails,
                dateCreated: dateCreated,
                expireStartDate: expireStartDate,
                expiresInMs: expiresInMs,
                isSealedSender: isSealedSender,
                chatItemType: chatItemType,
                isSmsPreviouslyRestoredFromBackup: isSmsPreviouslyRestoredFromBackup,
                pastRevisions: pastRevisions
            )
            if partialErrors.isEmpty {
                return .success(details)
            } else {
                return .partialFailure(details, partialErrors)
            }
        }
    }

    enum SkippableChatUpdate {
        enum SkippableGroupUpdate {
            /// This is a group update from back when we kept raw strings on
            /// disk, instead of metadata required to construct the string. We
            /// knowingly drop these.
            case legacyRawString

            /// In backups, we collapse the `inviteFriendsToNewlyCreatedGroup`
            /// into the `createdByLocalUser`; the former is just omitted from
            /// backups.
            case inviteFriendsToNewlyCreatedGroup

            /// This is supposedly a group update, but we don't have any
            /// metadata on what the update actually was, so we're dropping this
            /// update message.
            case missingUpdateMetadata
        }

        /// Represents types of ``TSErrorMessage``s (as described by
        /// ``TSErrorMessageType``) that are legacy and exclued from backups.
        enum LegacyErrorMessageType {
            /// See: `TSErrorMessageType/noSession`
            case noSession
            /// See: `TSErrorMessageType/wrongTrustedIdentityKey`
            case wrongTrustedIdentityKey
            /// See: `TSErrorMessageType/invalidKeyException`
            case invalidKeyException
            /// See: `TSErrorMessageType/missingKeyId`
            case missingKeyId
            /// See: `TSErrorMessageType/invalidMessage`
            case invalidMessage
            /// See: `TSErrorMessageType/duplicateMessage`
            case duplicateMessage
            /// See: `TSErrorMessageType/invalidVersion`
            case invalidVersion
            /// See: `TSErrorMessageType/unknownContactBlockOffer`
            case unknownContactBlockOffer
            /// See: `TSErrorMessageType/groupCreationFailed`
            case groupCreationFailed
        }

        enum LegacyInfoMessageType {
            /// See: `TSInfoMessageType/userNotRegistered`
            case userNotRegistered
            /// See: `TSInfoMessageType/typeUnsupportedMessage`
            case typeUnsupportedMessage
            /// See: `TSInfoMessageType/typeGroupQuit`
            case typeGroupQuit
            /// See: `TSInfoMessageType/addToContactsOffer`
            case addToContactsOffer
            /// See: `TSInfoMessageType/addUserToProfileWhitelistOffer`
            case addUserToProfileWhitelistOffer
            /// See: `TSInfoMessageType/addGroupToProfileWhitelistOffer`
            case addGroupToProfileWhitelistOffer
            /// See: `TSInfoMessageType/syncedThread`
            case syncedThread
            /// This is a "thread merge" event for which we don't know the
            /// "before" thread's phone number.
            case threadMergeWithoutPhoneNumber
            /// This is a "session switchover" event for which we don't know the
            /// old session's phone number.
            case sessionSwitchoverWithoutPhoneNumber
        }

        /// Some group updates are deliberately skipped.
        case skippableGroupUpdate(SkippableGroupUpdate)

        /// This is a legacy ``TSErrorMessage`` that we no longer support, and
        /// is correspondingly dropped when creating a backup.
        case legacyErrorMessage(LegacyErrorMessageType)

        /// This is a legacy ``TSInfoMessage`` that we no longer support, and
        /// is correspondingly dropped when creating a backup.
        case legacyInfoMessage(LegacyInfoMessageType)

        /// This is a ``TSInfoMessage`` telling us about a contact being hidden,
        /// which doesn't go into the backup. Instead, we track and handle info
        /// messages for recipient hidden state separately.
        case contactHiddenInfoMessage

        /// This is a past revision for a message that was later edited. We skip
        /// these, instead handling all past revisions when handling the latest
        /// revision of a message.
        case pastRevisionOfEditedMessage

        /// An empty message is one expected to have a body (it is a visible, sent/received message)
        /// that does not (neither a text body nor any body attachments). In an ideal world, these would
        /// not exist. Sadly, we know they do exist for historical reasons and are not rendered by iOS,
        /// and therefore should be dropped when creating a backup.
        case emptyBodyMessage

        /// This is a message that is expiring soon, so we don't back it up at all.
        case soonToExpireMessage

        /// This message has a timestamp that exceeds the maximum allowed timestamp in backups.
        /// No legitimate message should have timestamps this size, so any message we see is the
        /// result of either intentional or unintentional fuzzing, and we just drop it.
        case timestampTooLarge

        /// We previously had a bug that made it possible to reply to your
        /// own stories; these replies would go into the Note To Self thread.
        /// We just drop these on export as they're meant to be impossible.
        case directStoryReplyInNoteToSelf
    }

    enum ArchiveInteractionResult<Component> {
        case success(Component)

        // MARK: Skips

        /// We intentionally skip archiving some chat-update interactions.
        case skippableChatUpdate(SkippableChatUpdate)

        // MARK: Errors

        /// Some portion of the interaction failed to archive, but we can still archive the rest of it.
        /// e.g. some recipient details are missing, so we archive without that recipient.
        case partialFailure(Component, [ArchiveFrameError<InteractionUniqueId>])
        /// The entire message failed and should be skipped.
        /// Other messages are unaffected.
        case messageFailure([ArchiveFrameError<InteractionUniqueId>])
        /// Catastrophic failure, which should stop _all_ message archiving.
        case completeFailure(FatalArchivingError)
    }

    enum RestoreInteractionResult<Component> {
        case success(Component)
        /// Some portion of the interaction failed to restore, but we can still restore the rest of it.
        /// e.g. a reaction failed to parse, so we just drop that reaction.
        case partialRestore(Component, [RestoreFrameError<ChatItemId>])
        /// The entire message failed and should be skipped.
        /// Other messages are unaffected.
        case messageFailure([RestoreFrameError<ChatItemId>])
    }
}

// MARK: -

extension MessageBackup.ArchiveInteractionResult {

    enum BubbleUp<ComponentType, ErrorComponentType> {
        case `continue`(ComponentType)
        case bubbleUpError(MessageBackup.ArchiveInteractionResult<ErrorComponentType>)
    }

    /// Make it easier to "bubble up" an error case of ``ArchiveInteractionResult`` thrown deeper in the call stack.
    /// Basically, collapses all the cases that should just be bubbled up to the caller (error cases) into an easily returnable case,
    /// ditto for the success or partial success cases, and handles updating partialErrors along the way.
    ///
    /// Concretely, turns this:
    ///
    /// switch someResult {
    /// case .success(let value):
    ///   myVar = value
    /// case .partialFailure(let value, let errors):
    ///   myVar = value
    ///   partialErrors.append(contentsOf: errors)
    /// case someFailureCase(let someErrorOrErrors)
    ///   let coalescedErrorOrErrors = partialErrors.coalesceSomehow(with: someErrorOrErrors)
    ///   // Just bubble up the error after coalescing
    ///   return .someFailureCase(coalescedErrorOrErrors)
    /// // ...
    /// // The same for every other error case that should be bubbled up
    /// // ...
    /// }
    ///
    /// Into this:
    ///
    /// switch someResult.bubbleUp(&partialErrors) {
    /// case .success(let value):
    ///   myVar = value
    /// case .bubbleUpError(let error):
    ///   return error
    /// }
    func bubbleUp<ErrorComponentType>(
        _ errorComponentType: ErrorComponentType.Type = Component.self,
        partialErrors: inout [MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>]
    ) -> BubbleUp<Component, ErrorComponentType> {
        switch self {
        case .success(let value):
            return .continue(value)

        case .partialFailure(let value, let errors):
            // Continue through partial failures.
            partialErrors.append(contentsOf: errors)
            return .continue(value)

        // These types are just bubbled up as-is
        case .skippableChatUpdate(let skippableChatUpdate):
            return .bubbleUpError(.skippableChatUpdate(skippableChatUpdate))
        case .completeFailure(let error):
            return .bubbleUpError(.completeFailure(error))

        case .messageFailure(let errors):
            // Add message failure to partial errors and bubble it up.
            partialErrors.append(contentsOf: errors)
            return .bubbleUpError(.messageFailure(partialErrors))
        }
    }
}

extension MessageBackup.RestoreInteractionResult {

    /// Returns nil for ``RestoreInteractionResult.messageFailure``, otherwise
    /// returns the restored component. Regardless, accumulates any errors so that the caller
    /// can return the passed in ``partialErrors`` array in the final result.
    ///
    /// Concretely, turns this:
    ///
    /// switch someResult {
    /// case .success(let value):
    ///   myVar = value
    /// case .partialRestore(let value, let errors):
    ///   myVar = value
    ///   partialErrors.append(contentsOf: errors)
    /// case messageFailure(let errors)
    ///   partialErrors.append(contentsOf: errors)
    ///   return .messageFailure(partialErrors)
    /// }
    ///
    /// Into this:
    ///
    /// guard let myVar = someResult.unwrap(&partialErrors) else {
    ///   return .messageFailure(partialErrors)
    /// }
    func unwrap(
        partialErrors: inout [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>]
    ) -> Component? {
        switch self {
        case .success(let component):
            return component
        case .partialRestore(let component, let errors):
            partialErrors.append(contentsOf: errors)
            return component
        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
            return nil
        }
    }
}

extension MessageBackup.RestoreInteractionResult where Component == Void {

    /// Given two results with Void success types, returns the combination of their errors or,
    /// if both succeeded, a Void success.
    /// `messageFailure`s override `partialRestore`s; if one or the other
    /// is `messageFailure`, the result will be `messageFailure`.
    func combine(_ other: Self) -> Self {
        switch (self, other) {
        case (.success, .success):
            return .success(())
        case let (.messageFailure(lhs), .messageFailure(rhs)):
            return .messageFailure(lhs + rhs)
        case let (.partialRestore(_, lhs), .partialRestore(_, rhs)):
            return .partialRestore((), lhs + rhs)
        case
            let (.messageFailure(lhs), .partialRestore(_, rhs)),
            let (.partialRestore(_, lhs), .messageFailure(rhs)):
            return .messageFailure(lhs + rhs)
        case
            let (.messageFailure(errors), .success),
            let (.success, .messageFailure(errors)):
            return .messageFailure(errors)
        case
            let (.partialRestore(_, errors), .success),
            let (.success, .partialRestore(_, errors)):
            return .partialRestore((), errors)
        }
    }
}

extension MessageBackup.RestoreInteractionResult where Component == Void {

    /// Returns false for ``RestoreInteractionResult.messageFailure``, otherwise
    /// returns true. Regardless, accumulates any errors so that the caller
    /// can return the passed in ``partialErrors`` array in the final result.
    func unwrap(
        partialErrors: inout [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>]
    ) -> Bool {
        switch self {
        case .success:
            return true
        case .partialRestore(_, let errors):
            partialErrors.append(contentsOf: errors)
            return true
        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
            return false
        }
    }
}
