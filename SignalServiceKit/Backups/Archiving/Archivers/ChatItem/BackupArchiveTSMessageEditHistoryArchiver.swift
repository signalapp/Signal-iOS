//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension BackupArchive {
    enum TSMessageEditHistory {
        enum RevisionType<MessageType: TSMessage> {
            case latestRevision(hasPastRevisions: Bool)
            case pastRevision(latestRevisionMessage: MessageType)
        }

        /// Represents an object that can perform archive/restore actions on a single
        /// instance, in isolation, of a ``TSMessage`` subclass. The instance may either
        /// be the latest or a prior revision in its edit history.
        ///
        /// - SeeAlso
        /// ``BackupArchiveTSMessageEditHistoryArchiver``
        ///
        /// - Note
        /// At the time of writing, implementations exist for ``TSIncomingMessage`` and
        /// ``TSOutgoingMessage``, which are the only types that can have an edit
        /// history in practice.
        protocol Builder<MessageType>: AnyObject {
            associatedtype MessageType: TSMessage

            typealias Details = BackupArchive.InteractionArchiveDetails

            /// Build archive details for the given message.
            ///
            /// - Parameter editRecord
            /// If the given message is a prior revision, this should contain the edit
            /// record corresponding to that revision.
            func buildMessageArchiveDetails(
                message: MessageType,
                editRecord: EditRecord?,
                threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
                context: BackupArchive.ChatArchivingContext
            ) -> BackupArchive.ArchiveInteractionResult<Details>

            /// Restore a message from the given chat item.
            ///
            /// - Parameter revisionType
            /// The type of revision being restored.
            func restoreMessage(
                _ chatItem: BackupProto_ChatItem,
                revisionType: RevisionType<MessageType>,
                chatThread: BackupArchive.ChatThread,
                context: BackupArchive.ChatItemRestoringContext
            ) -> BackupArchive.RestoreInteractionResult<MessageType>
        }
    }
}

/// An object that can perform archive/restore actions on an instance of a
/// ``TSMessage`` subclass and its entire edit history. This type is primarily
/// responsible for managing the edit history itself, and delegates the "heavy
/// lifting" of performing archive/restore actions on the ``TSMessage``s in the
/// edit history to a ``BackupArchiveTSMessageEditHistoryBuilder``.
final class BackupArchiveTSMessageEditHistoryArchiver<MessageType: TSMessage>
{
    typealias Details = BackupArchive.InteractionArchiveDetails

    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>
    private typealias RestoreFrameError = BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>

    private let editMessageStore: EditMessageStore

    init(
        editMessageStore: EditMessageStore
    ) {
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
        Builder: BackupArchive.TSMessageEditHistory.Builder<MessageType>
    >(
        _ message: MessageType,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext,
        builder: Builder
    ) -> BackupArchive.ArchiveInteractionResult<Details>
    {
        var partialErrors = [ArchiveFrameError]()

        let shouldArchiveEditHistory: Bool
        switch message.editState {
        case .pastRevision:
            /// This message represents a past revision of a message, which is
            /// archived as part of archiving the latest revision. Consequently,
            /// we can skip this past revision here.
            return .skippableInteraction(.pastRevisionOfEditedMessage)
        case .none:
            shouldArchiveEditHistory = false
        case .latestRevisionRead, .latestRevisionUnread:
            shouldArchiveEditHistory = true
        }

        var messageDetails: Details
        switch builder.buildMessageArchiveDetails(
            message: message,
            editRecord: nil,
            threadInfo: threadInfo,
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
                threadInfo: threadInfo,
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
        Builder: BackupArchive.TSMessageEditHistory.Builder<MessageType>
    >(
        toLatestRevisionArchiveDetails latestRevisionDetails: inout Details,
        latestRevisionMessage: MessageType,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext,
        builder: Builder
    ) -> BackupArchive.ArchiveInteractionResult<Void> {
        /// Returns `nil` if the given `Details` are allowed to have or be a
        /// past revision, or an error type if not.
        func areRevisionsLegal(_ details: Details) -> ArchiveFrameError.ErrorType.UnexpectedRevisionsMessageType? {
            return switch details.chatItemType {
            case .standardMessage, .directStoryReplyMessage: nil
            case .remoteDeletedMessage: .remoteDeletedMessage
            case .contactMessage: .contactMessage
            case .stickerMessage: .stickerMessage
            case .updateMessage: .updateMessage
            case .paymentNotification: .paymentNotification
            case .giftBadge: .giftBadge
            case .viewOnceMessage: .viewOnceMessage
            case .poll: .poll
            }
        }

        switch latestRevisionDetails.chatItemType {
        case .remoteDeletedMessage:
            // Remote-deleted messages with edit history delete the contents of
            // their prior revisions, but leave the revisions around as
            // placeholders. We don't want to archive those, nor do we need to
            // produce an error, so we bail early.
            return .success(())
        default:
            break
        }

        // Short-circuit if this message type shouldn't have edit history.
        if let illegalRevisionType = areRevisionsLegal(latestRevisionDetails) {
            return .partialFailure((), [.archiveFrameError(
                .revisionsPresentOnUnexpectedMessage(illegalRevisionType),
                latestRevisionMessage.uniqueInteractionId
            )])
        }

        var partialErrors = [ArchiveFrameError]()

        /// The edit history, from oldest revision to newest. This ordering
        /// matches the expected ordering for `revisions` on a `ChatItem`, but
        /// is reverse of what we get from `editMessageStore`.
        let editHistory: [(EditRecord, MessageType?)]
        do {
            editHistory = try editMessageStore.findEditHistory(
                forMostRecentRevision: latestRevisionMessage,
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
                threadInfo: threadInfo,
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
            case .skippableInteraction:
                // This should never happen for an edit revision!
                continue
            }

            // We have a past revision that's not of a legal type. Skip it.
            if let illegalRevisionType = areRevisionsLegal(pastRevisionDetails) {
                partialErrors.append(.archiveFrameError(
                    .revisionWasUnexpectedMessage(illegalRevisionType),
                    pastRevisionMessage.uniqueInteractionId,
                ))
            } else {
                /// We're iterating the edit history from oldest to newest, so
                /// the past revision details stored on `latestRevisionDetails`
                /// will also be ordered oldest to newest.
                latestRevisionDetails.addPastRevision(pastRevisionDetails)
            }
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
        Builder: BackupArchive.TSMessageEditHistory.Builder<MessageType>
    >(
        _ topLevelChatItem: BackupProto_ChatItem,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
        builder: Builder
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        var partialErrors = [RestoreFrameError]()

        let latestRevisionMessage: MessageType
        switch builder
            .restoreMessage(
                topLevelChatItem,
                revisionType: .latestRevision(hasPastRevisions: topLevelChatItem.revisions.count > 0),
                chatThread: chatThread,
                context: context
            )
            .bubbleUp(Void.self, partialErrors: &partialErrors)
        {
        case .continue(let component):
            latestRevisionMessage = component
        case .bubbleUpError(let error):
            return error
        }

        /// `ChatItem.revisions` is ordered oldest -> newest, which aligns with
        /// how we want to insert them. Older revisions should be inserted
        /// before newer ones.
        for revisionChatItem in topLevelChatItem.revisions {
            switch builder
                 .restoreMessage(
                    revisionChatItem,
                    revisionType: .pastRevision(latestRevisionMessage: latestRevisionMessage),
                    chatThread: chatThread,
                    context: context
                )
                 .bubbleUp(Void.self, partialErrors: &partialErrors)
            {
            case .continue:
                break
            case .bubbleUpError(let error):
                /// This means we won't attempt to restore any later revisions,
                /// but we can't be confident they would have restored
                /// successfully anyway.
                return error
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
    /// `BackupArchiveTSMessageEditHistoryArchiver` operates generically on
    /// `TSMessage` subclasses and needs to know about read status.
    func wasRead() -> BackupArchive.RestoreInteractionResult<Bool> {
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
