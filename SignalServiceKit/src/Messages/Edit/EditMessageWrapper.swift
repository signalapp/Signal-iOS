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

    func createMessageCopy(
        dataStore: EditManager.Shims.DataStore,
        thread: TSThread,
        isLatestRevision: Bool,
        tx: DBReadTransaction,
        updateBlock: ((MessageBuilderType) -> Void)?
    ) -> MessageType

    func updateMessageCopy(
        dataStore: EditManager.Shims.DataStore,
        newMessageCopy: MessageType,
        tx: DBWriteTransaction
    )
}

public struct IncomingEditMessageWrapper: EditMessageWrapper {

    public let message: TSIncomingMessage
    public let authorAci: Aci?

    public func createMessageCopy(
        dataStore: EditManager.Shims.DataStore,
        thread: TSThread,
        isLatestRevision: Bool,
        tx: DBReadTransaction,
        updateBlock: ((TSIncomingMessageBuilder) -> Void)?
    ) -> TSIncomingMessage {

        let editState: TSEditState = {
            if isLatestRevision {
                return message.wasRead ? .latestRevisionRead : .latestRevisionUnread
            } else {
                return .pastRevision
            }
        }()

        let builder = TSIncomingMessageBuilder(
            thread: thread,
            timestamp: message.timestamp,
            authorAci: authorAci,
            sourceDeviceId: message.sourceDeviceId,
            messageBody: message.body,
            bodyRanges: message.bodyRanges,
            attachmentIds: message.attachmentIds,
            editState: editState,
            expiresInSeconds: isLatestRevision ? message.expiresInSeconds : 0,
            expireStartedAt: message.expireStartedAt,
            quotedMessage: message.quotedMessage,
            contactShare: message.contactShare,
            linkPreview: message.linkPreview,
            messageSticker: message.messageSticker,
            read: isLatestRevision ? message.wasRead : true,
            serverTimestamp: message.serverTimestamp,
            serverDeliveryTimestamp: message.serverDeliveryTimestamp,
            serverGuid: message.serverGuid,
            wasReceivedByUD: message.wasReceivedByUD,
            isViewOnceMessage: message.isViewOnceMessage,
            storyAuthorAddress: message.storyAuthorAddress,
            storyTimestamp: message.storyTimestamp?.uint64Value,
            storyReactionEmoji: message.storyReactionEmoji,
            giftBadge: message.giftBadge
        )

        updateBlock?(builder)

        return builder.build()
    }

    public func updateMessageCopy(
        dataStore: EditManager.Shims.DataStore,
        newMessageCopy: TSIncomingMessage,
        tx: DBWriteTransaction
    ) {}
}

public struct OutgoingEditMessageWrapper: EditMessageWrapper {

    public let message: TSOutgoingMessage

    public func createMessageCopyBuilder(
        thread: TSThread,
        isLatestRevision: Bool
    ) -> TSOutgoingMessageBuilder {
        TSOutgoingMessageBuilder(
            thread: thread,
            timestamp: message.timestamp,
            messageBody: message.body,
            bodyRanges: message.bodyRanges,
            attachmentIds: message.attachmentIds,
            editState: isLatestRevision ? .latestRevisionRead : .pastRevision,
            expiresInSeconds: isLatestRevision ? message.expiresInSeconds : 0,
            expireStartedAt: message.expireStartedAt,
            isVoiceMessage: message.isVoiceMessage,
            groupMetaMessage: message.groupMetaMessage,
            quotedMessage: message.quotedMessage,
            contactShare: message.contactShare,
            linkPreview: message.linkPreview,
            messageSticker: message.messageSticker,
            isViewOnceMessage: message.isViewOnceMessage,
            changeActionsProtoData: message.changeActionsProtoData,
            storyAuthorAddress: message.storyAuthorAddress,
            storyTimestamp: message.storyTimestamp?.uint64Value,
            storyReactionEmoji: message.storyReactionEmoji,
            giftBadge: message.giftBadge
        )
    }

    public func createMessageCopy(
        dataStore: EditManager.Shims.DataStore,
        thread: TSThread,
        isLatestRevision: Bool,
        tx: DBReadTransaction,
        updateBlock: ((TSOutgoingMessageBuilder) -> Void)?
    ) -> TSOutgoingMessage {
        let builder = createMessageCopyBuilder(
            thread: thread,
            isLatestRevision: isLatestRevision
        )

        updateBlock?(builder)

        return dataStore.createOutgoingMessage(with: builder, tx: tx)
    }

    public func updateMessageCopy(
        dataStore: EditManager.Shims.DataStore,
        newMessageCopy: TSOutgoingMessage,
        tx: DBWriteTransaction
    ) {
        // Need to copy over the recipient address from the old message
        // This is needed when procesing sync messages.
        dataStore.copyRecipients(from: message, to: newMessageCopy, tx: tx)
    }
}
