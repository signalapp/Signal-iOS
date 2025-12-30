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
        isLatestRevision: Bool,
        attachmentContentValidator: AttachmentContentValidator,
        tx: DBWriteTransaction,
    ) -> MessageBuilderType

    static func build(
        _ builder: MessageBuilderType,
        tx: DBReadTransaction,
    ) -> MessageType

    func updateMessageCopy(
        newMessageCopy: MessageType,
        tx: DBWriteTransaction,
    )
}

// MARK: -

public struct IncomingEditMessageWrapper: EditMessageWrapper {

    public let message: TSIncomingMessage
    public let thread: TSThread
    public let authorAci: Aci?

    /// Read state is .. complicated when it comes to edit revisions.
    ///
    /// For the latest revision of a message, the `TSInteraction/read` property
    /// is accurate.
    ///
    /// However, the `TSInteraction` for all past revisions has `read` set to
    /// `true`, and "whether the user has read that edit" is tracked separately
    /// on `EditRecord`.
    ///
    /// This is for two reasons:
    ///
    /// 1. There are many queries that filter on `TSInteraction/read`, and by
    /// automatically excluding prior revisions from those queries we make them
    /// simpler; for example, queries pertaining to unread count, or whether a
    /// thread contains an unread mention of the local user.
    ///
    /// 2. Interactions are marked "read" by tracking the latest interaction to
    /// become visible, and marking all interactions before it (by SQL insertion
    /// order) as read. Old edit revisions are not visible in the UI, and are
    /// inserted as *newer* interactions than the latest revision; this makes it
    /// complicated to correctly mark those interactions as read.
    ///
    /// ---
    ///
    /// Note that we should only ever be targeting a latest revision for edits.
    public var wasRead: Bool {
        switch message.editState {
        case .none, .latestRevisionRead, .latestRevisionUnread:
            return message.wasRead
        case .pastRevision:
            // We shouldn't ever be targeting a past revision for an edit. If we
            // were, though, assume it was unread since it can't be seen in the
            // conversation view.
            owsFailDebug("Edit target was unexpectedly past revision!")
            return false
        }
    }

    public func cloneAsBuilderWithoutAttachments(
        applying edits: MessageEdits,
        isLatestRevision: Bool,
        attachmentContentValidator: AttachmentContentValidator,
        tx: DBWriteTransaction,
    ) -> TSIncomingMessageBuilder {
        let editState: TSEditState = {
            if isLatestRevision {
                switch message.editState {
                case .none:
                    return message.wasRead ? .latestRevisionRead : .latestRevisionUnread
                case .latestRevisionRead, .latestRevisionUnread:
                    return message.editState
                case .pastRevision:
                    owsFailDebug("Latest revision message unexpectedly had .pastRevision edit state!")
                    return message.editState
                }
            } else {
                return .pastRevision
            }
        }()

        let messageBody: ValidatedInlineMessageBody?
        switch edits.body {
        case .keep:
            messageBody = message.body.map {
                attachmentContentValidator.truncatedMessageBodyForInlining(
                    MessageBody(text: $0, ranges: message.bodyRanges ?? .empty),
                    tx: tx,
                )
            }
        case .change(let body):
            messageBody = body
        }
        let timestamp = edits.timestamp.unwrapChange(orKeepValue: message.timestamp)
        let receivedAtTimestamp = edits.receivedAtTimestamp.unwrapChange(orKeepValue: message.receivedAtTimestamp)
        let serverTimestamp = edits.serverTimestamp.unwrapChange(orKeepValue: message.serverTimestamp?.uint64Value ?? 0)
        let serverDeliveryTimestamp = edits.serverDeliveryTimestamp.unwrapChange(orKeepValue: message.serverDeliveryTimestamp)
        let serverGuid = edits.serverGuid.unwrapChange(orKeepValue: message.serverGuid)

        if message.isPoll {
            owsFailDebug("Poll messages should not be editable")
        }

        /// Copies the wrapped message's fields with edited fields overridden as
        /// appropriate. Attachment-related properties are zeroed-out, and
        /// handled later by ``EditManagerAttachments/reconcileAttachments``.
        return TSIncomingMessageBuilder(
            thread: thread,
            timestamp: timestamp,
            receivedAtTimestamp: receivedAtTimestamp,
            authorAci: authorAci,
            authorE164: nil,
            messageBody: messageBody,
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
            paymentNotification: nil,
            isPoll: false,
        )
    }

    public static func build(
        _ builder: TSIncomingMessageBuilder,
        tx: DBReadTransaction,
    ) -> TSIncomingMessage {
        return builder.build()
    }

    public func updateMessageCopy(
        newMessageCopy: TSIncomingMessage,
        tx: DBWriteTransaction,
    ) {}
}

// MARK: -

public struct OutgoingEditMessageWrapper: EditMessageWrapper {

    public let message: TSOutgoingMessage
    public let thread: TSThread

    public init(
        message: TSOutgoingMessage,
        thread: TSThread,
    ) {
        self.message = message
        self.thread = thread
    }

    /// Outgoing messages are always read.
    public var wasRead: Bool { true }

    public func cloneAsBuilderWithoutAttachments(
        applying edits: MessageEdits,
        isLatestRevision: Bool,
        attachmentContentValidator: AttachmentContentValidator,
        tx: DBWriteTransaction,
    ) -> TSOutgoingMessageBuilder {
        let messageBody: ValidatedInlineMessageBody?
        switch edits.body {
        case .keep:
            messageBody = message.body.map {
                attachmentContentValidator.truncatedMessageBodyForInlining(
                    MessageBody(text: $0, ranges: message.bodyRanges ?? .empty),
                    tx: tx,
                )
            }
        case .change(let body):
            messageBody = body
        }
        let timestamp = edits.timestamp.unwrapChange(orKeepValue: message.timestamp)
        let receivedAtTimestamp = edits.receivedAtTimestamp.unwrapChange(orKeepValue: message.receivedAtTimestamp)

        if message.isPoll {
            owsFailDebug("Poll messages should not be editable")
        }

        /// Copies the wrapped message's fields with edited fields overridden as
        /// appropriate. Attachment-related properties are zeroed-out, and
        /// handled later by ``EditManagerAttachments/reconcileAttachments``.
        return TSOutgoingMessageBuilder(
            thread: thread,
            timestamp: timestamp,
            receivedAtTimestamp: receivedAtTimestamp,
            messageBody: messageBody,
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
            wasNotCreatedLocally: message.wasNotCreatedLocally,
            groupChangeProtoData: message.changeActionsProtoData,
            storyAuthorAci: message.storyAuthorAci?.wrappedAciValue,
            storyTimestamp: message.storyTimestamp?.uint64Value,
            storyReactionEmoji: message.storyReactionEmoji,
            quotedMessage: nil,
            contactShare: nil,
            linkPreview: nil,
            messageSticker: nil,
            giftBadge: message.giftBadge,
            isPoll: false,
        )
    }

    public static func build(
        _ builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction,
    ) -> TSOutgoingMessage {
        return builder.build(transaction: tx)
    }

    public func updateMessageCopy(
        newMessageCopy: TSOutgoingMessage,
        tx: DBWriteTransaction,
    ) {
        // Need to copy over the recipient address from the old message
        // This is needed when procesing sync messages.
        newMessageCopy.updateWithRecipientAddressStates(
            message.recipientAddressStates,
            tx: tx,
        )
    }
}
