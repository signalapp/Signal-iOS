//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

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

    /// Clones this message into a new builder, applying the given edits and
    /// zeroing-out any attachment-related fields.
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

        let body = edits.body.unwrapChange(orKeepValue: message.body)
        let bodyRanges = edits.bodyRanges.unwrapChange(orKeepValue: message.bodyRanges)
        let timestamp = edits.timestamp.unwrapChange(orKeepValue: message.timestamp)
        let receivedAtTimestamp = edits.receivedAtTimestamp.unwrapChange(orKeepValue: message.receivedAtTimestamp)
        let serverTimestamp = edits.serverTimestamp.unwrapChange(orKeepValue: message.serverTimestamp?.uint64Value ?? 0)
        let serverDeliveryTimestamp = edits.serverDeliveryTimestamp.unwrapChange(orKeepValue: message.serverDeliveryTimestamp)
        let serverGuid = edits.serverGuid.unwrapChange(orKeepValue: message.serverGuid)

        /// Copies the wrapped message's fields with edited fields overridden as
        /// appropriate. Attachment-related properties are zeroed-out, and
        /// handled later by ``EditManagerAttachments/reconcileAttachments``.
        return TSIncomingMessageBuilder(
            thread: thread,
            timestamp: timestamp,
            receivedAtTimestamp: receivedAtTimestamp,
            authorAci: authorAci,
            authorE164: nil,
            messageBody: body,
            bodyRanges: bodyRanges,
            editState: editState,
            // Prior revisions don't expire (timer=0); instead they
            // are cascade-deleted when the latest revision expires.
            expiresInSeconds: isLatestRevision ? message.expiresInSeconds : 0,
            expireTimerVersion: isLatestRevision ? message.expireTimerVersion?.uint32Value : nil,
            expireStartedAt: message.expireStartedAt,
            read: isLatestRevision ? false : true,
            serverTimestamp: serverTimestamp,
            serverDeliveryTimestamp: serverDeliveryTimestamp,
            serverGuid: serverGuid,
            wasReceivedByUD: message.wasReceivedByUD,
            isSmsMessageRestoredFromBackup: message.isSmsMessageRestoredFromBackup,
            isViewOnceMessage: message.isViewOnceMessage,
            isViewOnceComplete: message.isViewOnceComplete,
            wasRemotelyDeleted: message.wasRemotelyDeleted,
            storyAuthorAci: message.storyAuthorAci?.wrappedAciValue,
            storyTimestamp: message.storyTimestamp?.uint64Value,
            storyReactionEmoji: message.storyReactionEmoji,
            quotedMessage: nil,
            contactShare: nil,
            linkPreview: nil,
            messageSticker: nil,
            giftBadge: message.giftBadge,
            paymentNotification: nil
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
        let body = edits.body.unwrapChange(orKeepValue: message.body)
        let bodyRanges = edits.bodyRanges.unwrapChange(orKeepValue: message.bodyRanges)
        let timestamp = edits.timestamp.unwrapChange(orKeepValue: message.timestamp)
        let receivedAtTimestamp = edits.receivedAtTimestamp.unwrapChange(orKeepValue: message.receivedAtTimestamp)

        /// Copies the wrapped message's fields with edited fields overridden as
        /// appropriate. Attachment-related properties are zeroed-out, and
        /// handled later by ``EditManagerAttachments/reconcileAttachments``.
        return TSOutgoingMessageBuilder(
            thread: thread,
            timestamp: timestamp,
            receivedAtTimestamp: receivedAtTimestamp,
            messageBody: body,
            bodyRanges: bodyRanges,
            // Outgoing messages are implicitly read.
            editState: isLatestRevision ? .latestRevisionRead : .pastRevision,
            // Prior revisions don't expire (timer=0); instead they
            // are cascade-deleted when the latest revision expires.
            expiresInSeconds: isLatestRevision ? message.expiresInSeconds : 0,
            expireTimerVersion: isLatestRevision ? message.expireTimerVersion?.uint32Value : 0,
            expireStartedAt: message.expireStartedAt,
            isVoiceMessage: message.isVoiceMessage,
            groupMetaMessage: message.groupMetaMessage,
            isSmsMessageRestoredFromBackup: message.isSmsMessageRestoredFromBackup,
            isViewOnceMessage: message.isViewOnceMessage,
            isViewOnceComplete: message.isViewOnceComplete,
            wasRemotelyDeleted: message.wasRemotelyDeleted,
            groupChangeProtoData: message.changeActionsProtoData,
            storyAuthorAci: message.storyAuthorAci?.wrappedAciValue,
            storyTimestamp: message.storyTimestamp?.uint64Value,
            storyReactionEmoji: message.storyReactionEmoji,
            quotedMessage: nil,
            contactShare: nil,
            linkPreview: nil,
            messageSticker: nil,
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
