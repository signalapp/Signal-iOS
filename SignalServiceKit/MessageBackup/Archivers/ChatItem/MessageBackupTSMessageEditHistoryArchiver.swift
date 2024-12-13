//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Represents an object that can perform archive/restore actions on a single
/// instance, in isolation, of a ``TSMessage`` subclass. The instance may either
/// be the latest or a prior revision in its edit history.
///
/// - SeeAlso
/// ``MessageBackupTSMessageEditHistoryArchiver``
///
/// - Note
/// At the time of writing, implementations exist for ``TSIncomingMessage`` and
/// ``TSOutgoingMessage``, which are the only types that can have an edit
/// history in practice.
protocol MessageBackupTSMessageEditHistoryBuilder<EditHistoryMessageType>: AnyObject {
    associatedtype EditHistoryMessageType: TSMessage

    typealias Details = MessageBackup.InteractionArchiveDetails

    /// Build archive details for the given message.
    ///
    /// - Parameter editRecord
    /// If the given message is a prior revision, this should contain the edit
    /// record corresponding to that revision.
    func buildMessageArchiveDetails(
        message: EditHistoryMessageType,
        editRecord: EditRecord?,
        context: MessageBackup.ChatArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<Details>

    /// Restore a message from the given chat item.
    ///
    /// - Parameter isPastRevision
    /// Whether this chat item is known to be a past revision. If this is true,
    /// `hasPastRevisions` will always be `false`.
    /// - Parameter hasPastRevisions
    /// Whether this chat item has past revisions. If this is true,
    /// `isPastRevision` will always be `false`.
    func restoreMessage(
        _ chatItem: BackupProto_ChatItem,
        isPastRevision: Bool,
        hasPastRevisions: Bool,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> MessageBackup.RestoreInteractionResult<EditHistoryMessageType>
}

/// An object that can perform archive/restore actions on an instance of a
/// ``TSMessage`` subclass and its entire edit history. This type is primarily
/// responsible for managing the edit history itself, and delegates the "heavy
/// lifting" of performing archive/restore actions on the ``TSMessage``s in the
/// edit history to a ``MessageBackupTSMessageEditHistoryBuilder``.
final class MessageBackupTSMessageEditHistoryArchiver<MessageType: TSMessage>
{
    typealias Details = MessageBackup.InteractionArchiveDetails

    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let dateProvider: DateProvider
    private let editMessageStore: any EditMessageStore

    init(
        dateProvider: @escaping DateProvider,
        editMessageStore: any EditMessageStore
    ) {
        self.dateProvider = dateProvider
        self.editMessageStore = editMessageStore
    }

    // MARK: - Archive

    /// Build archive details for the given message, along with its edit
    /// history (if it has prior revisions).
    ///
    /// - Important
    /// In practice, all messages that _might_ have an edit history are archived
    /// by an instance of this type, even if they do not ultimately have any
    /// prior revisions.
    ///
    /// - Note
    /// When past revision message instances are passed, this method returns a
    /// "skippable" result  case. Instead, the latest revision and all its past
    /// revisions are archived into the same ``Details``, which is a recursive
    /// type, when the latest revision is passed.
    ///
    /// - Parameter builder
    /// An object responsible for actually building archive details on the
    /// passed message, and those in its edit history.
    func archiveMessageAndEditHistory<
        Builder: MessageBackupTSMessageEditHistoryBuilder<MessageType>
    >(
        _ message: MessageType,
        context: MessageBackup.ChatArchivingContext,
        builder: Builder
    ) -> MessageBackup.ArchiveInteractionResult<Details>
    {
        var partialErrors = [ArchiveFrameError]()

        let shouldArchiveEditHistory: Bool
        switch message.editState {
        case .pastRevision:
            /// This message represents a past revision of a message, which is
            /// archived as part of archiving the latest revision. Consequently,
            /// we can skip this past revision here.
            return .skippableChatUpdate(.pastRevisionOfEditedMessage)
        case .none:
            shouldArchiveEditHistory = false
        case .latestRevisionRead, .latestRevisionUnread:
            shouldArchiveEditHistory = true
        }

        var messageDetails: Details
        switch builder.buildMessageArchiveDetails(
            message: message,
            editRecord: nil,
            context: context
        ).bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let _messageDetails):
            messageDetails = _messageDetails
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        if shouldArchiveEditHistory {
            switch addEditHistoryArchiveDetails(
                toLatestRevisionArchiveDetails: &messageDetails,
                latestRevisionMessage: message,
                context: context,
                builder: builder
            ).bubbleUp(Details.self, partialErrors: &partialErrors) {
            case .continue:
                break
            case .bubbleUpError(let errorResult):
                return errorResult
            }
        }

        if partialErrors.isEmpty {
            return .success(messageDetails)
        } else {
            return .partialFailure(messageDetails, partialErrors)
        }
    }

    /// Archive each of the prior revisions of the given latest revision of a
    /// message, and add those prior-revision archive details to the given
    /// archive details for the latest revision.
    private func addEditHistoryArchiveDetails<
        Builder: MessageBackupTSMessageEditHistoryBuilder<MessageType>
    >(
        toLatestRevisionArchiveDetails latestRevisionDetails: inout Details,
        latestRevisionMessage: MessageType,
        context: MessageBackup.ChatArchivingContext,
        builder: Builder
    ) -> MessageBackup.ArchiveInteractionResult<Void> {
        var partialErrors = [ArchiveFrameError]()

        guard case .standardMessage = latestRevisionDetails.chatItemType else {
            return .success(())
        }

        /// The edit history, from oldest revision to newest. This ordering
        /// matches the expected ordering for `revisions` on a `ChatItem`, but
        /// is reverse of what we get from `editMessageStore`.
        let editHistory: [(EditRecord, MessageType?)]
        do {
            editHistory = try editMessageStore.findEditHistory(
                for: latestRevisionMessage,
                tx: context.tx
            ).reversed()
        } catch {
            return .messageFailure([.archiveFrameError(
                .editHistoryFailedToFetch,
                latestRevisionMessage.uniqueInteractionId
            )])
        }

        for (editRecord, pastRevisionMessage) in editHistory {
            guard let pastRevisionMessage else { continue }

            /// Build archive details for this past revision, so we can append
            /// them to the most recent revision's archive details.
            ///
            /// We'll power through anything less than a `.completeFailure`
            /// while restoring a past revision, instead tracking the error,
            /// dropping the revision, and moving on.
            let pastRevisionDetails: Details
            switch builder.buildMessageArchiveDetails(
                message: pastRevisionMessage,
                editRecord: editRecord,
                context: context
            ) {
            case .success(let _pastRevisionDetails):
                pastRevisionDetails = _pastRevisionDetails
            case .partialFailure(let _pastRevisionDetails, let _partialErrors):
                pastRevisionDetails = _pastRevisionDetails
                partialErrors.append(contentsOf: _partialErrors)
            case .messageFailure(let _partialErrors):
                partialErrors.append(contentsOf: _partialErrors)
                continue
            case .completeFailure(let fatalError):
                return .completeFailure(fatalError)
            case .skippableChatUpdate:
                // This should never happen for an edit revision!
                continue
            }

            /// We're iterating the edit history from oldest to newest, so the
            /// past revision details stored on `latestRevisionDetails` will
            /// also be ordered oldest to newest.
            latestRevisionDetails.addPastRevision(pastRevisionDetails)
        }

        if partialErrors.isEmpty {
            return .success(())
        } else {
            return .partialFailure((), partialErrors)
        }
    }

    // MARK: - Restore

    /// Restore a message from the given chat item, along with its edit history
    /// (if it has prior revisions).
    ///
    /// - Note
    /// ``BackupProto_ChatItem`` is a recursive type, such that a top-level
    /// `ChatItem` represents the latest revision in an edit history and
    /// contains sub-`ChatItem`s representing its prior revisions.
    ///
    /// - Parameter builder
    /// An object responsible for actually restoring a message from the
    /// top-level `ChatItem`, and its contained prior revisions (if any).
    func restoreMessageAndEditHistory<
        Builder: MessageBackupTSMessageEditHistoryBuilder<MessageType>
    >(
        _ topLevelChatItem: BackupProto_ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext,
        builder: Builder
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        var partialErrors = [RestoreFrameError]()

        guard
            let latestRevisionMessage = builder.restoreMessage(
                topLevelChatItem,
                isPastRevision: false,
                hasPastRevisions: topLevelChatItem.revisions.count > 0,
                chatThread: chatThread,
                context: context
            ).unwrap(partialErrors: &partialErrors)
        else {
            return .messageFailure(partialErrors)
        }

        var earlierRevisionMessages = [MessageType]()

        /// `ChatItem.revisions` is ordered oldest -> newest, which aligns with
        /// how we want to insert them. Older revisions should be inserted
        /// before newer ones.
        for revisionChatItem in topLevelChatItem.revisions {
            guard
                let earlierRevisionMessage = builder.restoreMessage(
                    revisionChatItem,
                    isPastRevision: true,
                    hasPastRevisions: false, // Past revisions can't have their own past revisions!
                    chatThread: chatThread,
                    context: context
                ).unwrap(partialErrors: &partialErrors)
            else {
                /// This means we won't attempt to restore any later revisions,
                /// but we can't be confident they would have restored
                /// successfully anyway.
                return .messageFailure(partialErrors)
            }

            earlierRevisionMessages.append(earlierRevisionMessage)
        }

        for earlierRevisionMessage in earlierRevisionMessages {
            guard
                let wasRead = earlierRevisionMessage.wasRead()
                    .unwrap(partialErrors: &partialErrors)
            else {
                return .messageFailure(partialErrors)
            }

            let editRecord = EditRecord(
                latestRevisionId: latestRevisionMessage.sqliteRowId!,
                pastRevisionId: earlierRevisionMessage.sqliteRowId!,
                read: wasRead
            )

            do {
                try editMessageStore.insert(editRecord, tx: context.tx)
            } catch {
                return .partialRestore(
                    (),
                    [.restoreFrameError(
                        .databaseInsertionFailed(error),
                        topLevelChatItem.id
                    )] + partialErrors
                )
            }
        }

        if partialErrors.isEmpty {
            return .success(())
        } else {
            return .partialRestore((), partialErrors)
        }
    }
}

// MARK: -

private extension TSMessage {
    /// A workaround to generically expose "read status" off `TSMessage`.
    ///
    /// At the time of writing `TSMessage` has four subclasses: `Info`, `Error`,
    /// `Incoming`, and `Outgoing`. All of these conform to `OWSReadTracking`
    /// excepting `Outgoing`, because all outgoing messages are implicitly read.
    ///
    /// This method exposes that "read status" off `TSMessage`, since
    /// `MessageBackupTSMessageEditHistoryArchiver` operates generically on
    /// `TSMessage` subclasses and needs to know about read status.
    func wasRead() -> MessageBackup.RestoreInteractionResult<Bool> {
        if let info = self as? TSInfoMessage {
            return .success(info.wasRead)
        } else if let error = self as? TSErrorMessage {
            return .success(error.wasRead)
        } else if let incoming = self as? TSIncomingMessage {
            return .success(incoming.wasRead)
        } else if self is TSOutgoingMessage {
            // Implicitly read!
            return .success(true)
        }

        return .messageFailure([.restoreFrameError(
            .developerError(OWSAssertionError("Unexpected TSMessage type instantiated during restore: \(type(of: self))")),
            chatItemId
        )])
    }
}
