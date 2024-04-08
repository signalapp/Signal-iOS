//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Wrapper that preserves the type information of the message
/// being targeted for editing.  This wrapper prevents a lot of unecessary
/// casting from TSMessage back into the specific message types.  In
/// most cases TSMessage is fine to pass around, but for certain situations
/// having the TSMessage -> TSMessageBuilder relationship defined is
/// useful, and for things like outgoing edits, preserving this information
/// is necessary.
public protocol EditMessageWrapper {
    associatedtype MessageType: TSMessage
    associatedtype MessageBuilderType: TSMessageBuilder

    var message: MessageType { get }

    var wasRead: Bool { get }

    func cloneAsBuilderWithoutAttachments(
        applying: MessageEdits,
        isLatestRevision: Bool
    ) -> MessageBuilderType

    static func build(
        _ builder: MessageBuilderType,
        dataStore: EditManagerImpl.Shims.DataStore,
        tx: DBReadTransaction
    ) -> MessageType

    func updateMessageCopy(
        dataStore: EditManagerImpl.Shims.DataStore,
        newMessageCopy: MessageType,
        tx: DBWriteTransaction
    )
}

public struct IncomingEditMessageWrapper: EditMessageWrapper {

    public let message: TSIncomingMessage
    public let thread: TSThread
    public let authorAci: Aci?

    /// Read state is .. complicated when it comes to edit revisions.
    ///
    /// First, some context: For an incoming edit message, the `read` value of the interaction may
    /// not tell the whole story about the read  state of the edit.   This is mainly because of two things:
    ///
    /// 1) The queries that look up read count are affected by the number of unread items in a
    ///   thread, and leaving a bunch of old  edit revision as 'unread' could
    ///
    /// 2) Read state is tracked by watching for an interaction to become visible and marking all items
    ///   before it in a conversation as read.   Old edit revisions are neither (a) visible on the UI to trigger
    ///   the standard read tracking logic or (b) guaranteed to be located _before_ the last message in a
    ///   thread (due to other architectural limitations)
    ///
    /// Because of the above to points, when processing an edit, old revisions are marked as `read`
    /// regardless  of the `read` state of the original target mesasge.
    ///
    /// All of this is to say that this method as solely determining if the message in question was
    /// viewed through the UI and marked read through the standard read tracking mechanisms.
    ///
    /// If the `editState` of the message is marked as `.lastRevision'
    /// it couldn't (or shouldn't as of this writing) have been visible in the UI to mark as read in normal
    /// conversation view, and if the state is `.latestRevisionUnread`, it is, as per t's name, still unread.
    ///
    /// If the message is neither of these states, (meaning it's either `.latestRevisionRead`
    /// or `.none` (unedited)), the messages `wasRead` can be consulted for the read
    /// state of the message.
    ///
    /// The primary (or at least original) use for this boolean was to determine
    /// the read state of the current message when processing an incoming edit.
    /// This allows capturing all the unread edits to allow view receipts to
    /// be sent later on if the edit history is viewed.
    public var wasRead: Bool {
        if message.editState == .latestRevisionRead || message.editState == .none {
            return message.wasRead
        }
        return false
    }

    public func cloneAsBuilderWithoutAttachments(
        applying edits: MessageEdits,
        isLatestRevision: Bool
    ) -> TSIncomingMessageBuilder {
        let editState: TSEditState = {
            if isLatestRevision {
                if message.editState == .none {
                    return message.wasRead ? .latestRevisionRead : .latestRevisionUnread
                } else {
                    return message.editState
                }
            } else {
                return .pastRevision
            }
        }()

        let timestamp = edits.timestamp
        let body = edits.body.unwrap(keepValue: message.body)
        let bodyRanges = edits.bodyRanges.unwrap(keepValue: message.bodyRanges)

        return TSIncomingMessageBuilder(
            thread: thread,
            timestamp: timestamp,
            authorAci: authorAci,
            messageBody: body,
            bodyRanges: bodyRanges,
            // Legacy attachment ids get set separately.
            attachmentIds: [],
            editState: editState,
            // Prior revisions don't expire (timer=0); instead they
            // are cascade-deleted when the latest revision expires.
            expiresInSeconds: isLatestRevision ? message.expiresInSeconds : 0,
            expireStartedAt: message.expireStartedAt,
            // Quoted message gets set separately.
            quotedMessage: nil,
            // Contact shares don't support edits; should already be nil but drop anyway.
            contactShare: nil,
            // Link preview gets set separately.
            linkPreview: nil,
            // Stickers don't support edits; should already be nil but drop anyway.
            messageSticker: nil,
            read: isLatestRevision ? false : true,
            serverTimestamp: message.serverTimestamp,
            serverDeliveryTimestamp: message.serverDeliveryTimestamp,
            serverGuid: message.serverGuid,
            wasReceivedByUD: message.wasReceivedByUD,
            isViewOnceMessage: message.isViewOnceMessage,
            storyAuthorAci: message.storyAuthorAci?.wrappedAciValue,
            storyTimestamp: message.storyTimestamp?.uint64Value,
            storyReactionEmoji: message.storyReactionEmoji,
            giftBadge: message.giftBadge
        )
    }

    public static func build(
        _ builder: TSIncomingMessageBuilder,
        dataStore: EditManagerImpl.Shims.DataStore,
        tx: DBReadTransaction
    ) -> TSIncomingMessage {
        return builder.build()
    }

    public func updateMessageCopy(
        dataStore: EditManagerImpl.Shims.DataStore,
        newMessageCopy: TSIncomingMessage,
        tx: DBWriteTransaction
    ) {}
}

public struct OutgoingEditMessageWrapper: EditMessageWrapper {

    public let message: TSOutgoingMessage
    public let thread: TSThread

    public init(
        message: TSOutgoingMessage,
        thread: TSThread
    ) {
        self.message = message
        self.thread = thread
    }

    // Always return true for the sake of outgoing message read status
    public var wasRead: Bool { true }

    public func cloneAsBuilderWithoutAttachments(
        applying edits: MessageEdits,
        isLatestRevision: Bool
    ) -> TSOutgoingMessageBuilder {
        let timestamp = edits.timestamp
        let body = edits.body.unwrap(keepValue: message.body)
        let bodyRanges = edits.bodyRanges.unwrap(keepValue: message.bodyRanges)

        return TSOutgoingMessageBuilder(
            thread: thread,
            timestamp: timestamp,
            messageBody: body,
            bodyRanges: bodyRanges,
            // Legacy attachment ids get set separately.
            attachmentIds: [],
            editState: isLatestRevision ? .latestRevisionRead : .pastRevision,
            // Prior revisions don't expire (timer=0); instead they
            // are cascade-deleted when the latest revision expires.
            expiresInSeconds: isLatestRevision ? message.expiresInSeconds : 0,
            expireStartedAt: message.expireStartedAt,
            isVoiceMessage: message.isVoiceMessage,
            groupMetaMessage: message.groupMetaMessage,
            // Quoted message gets set separately.
            quotedMessage: nil,
            // Contact shares don't support edits; should already be nil but drop anyway.
            contactShare: nil,
            // Link preview gets set separately.
            linkPreview: nil,
            // Stickers don't support edits; should already be nil but drop anyway.
            messageSticker: nil,
            isViewOnceMessage: message.isViewOnceMessage,
            changeActionsProtoData: message.changeActionsProtoData,
            storyAuthorAci: message.storyAuthorAci?.wrappedAciValue,
            storyTimestamp: message.storyTimestamp?.uint64Value,
            storyReactionEmoji: message.storyReactionEmoji,
            giftBadge: message.giftBadge
        )
    }

    public static func build(
        _ builder: TSOutgoingMessageBuilder,
        dataStore: EditManagerImpl.Shims.DataStore,
        tx: DBReadTransaction
    ) -> TSOutgoingMessage {
        return dataStore.build(builder, tx: tx)
    }

    public func updateMessageCopy(
        dataStore: EditManagerImpl.Shims.DataStore,
        newMessageCopy: TSOutgoingMessage,
        tx: DBWriteTransaction
    ) {
        // Need to copy over the recipient address from the old message
        // This is needed when procesing sync messages.
        dataStore.update(
            newMessageCopy,
            withRecipientAddressStates: message.recipientAddressStates,
            tx: tx
        )
    }
}
