//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

@objc
public class TSOutgoingMessageBuilder: TSMessageBuilder {
    @objc
    public var isVoiceMessage = false
    @objc
    public var groupMetaMessage: TSGroupMetaMessage = .unspecified
    @objc
    public var changeActionsProtoData: Data?

    public init(
        thread: TSThread,
        timestamp: UInt64?,
        messageBody: String?,
        bodyRanges: MessageBodyRanges?,
        editState: TSEditState,
        expiresInSeconds: UInt32?,
        expireStartedAt: UInt64?,
        isVoiceMessage: Bool,
        groupMetaMessage: TSGroupMetaMessage,
        isViewOnceMessage: Bool,
        changeActionsProtoData: Data?,
        storyAuthorAci: Aci?,
        storyTimestamp: UInt64?,
        storyReactionEmoji: String?,
        giftBadge: OWSGiftBadge?
    ) {
        super.init(
            thread: thread,
            timestamp: timestamp,
            messageBody: messageBody,
            bodyRanges: bodyRanges,
            editState: editState,
            expiresInSeconds: expiresInSeconds,
            expireStartedAt: expireStartedAt,
            isViewOnceMessage: isViewOnceMessage,
            read: true, // Outgoing messages are always read.
            storyAuthorAci: storyAuthorAci.map { AciObjC($0) },
            storyTimestamp: storyTimestamp,
            storyReactionEmoji: storyReactionEmoji,
            giftBadge: giftBadge
        )

        self.isVoiceMessage = isVoiceMessage
        self.groupMetaMessage = groupMetaMessage
        self.changeActionsProtoData = changeActionsProtoData
    }

    public static func withDefaultValues(
        thread: TSThread,
        timestamp: UInt64? = nil,
        messageBody: String? = nil,
        bodyRanges: MessageBodyRanges? = nil,
        editState: TSEditState = .none,
        expiresInSeconds: UInt32? = nil,
        expireStartedAt: UInt64? = nil,
        isVoiceMessage: Bool = false,
        groupMetaMessage: TSGroupMetaMessage = .unspecified,
        isViewOnceMessage: Bool = false,
        changeActionsProtoData: Data? = nil,
        storyAuthorAci: Aci? = nil,
        storyTimestamp: UInt64? = nil,
        storyReactionEmoji: String? = nil,
        giftBadge: OWSGiftBadge? = nil
    ) -> TSOutgoingMessageBuilder {
        return TSOutgoingMessageBuilder(
            thread: thread,
            timestamp: timestamp,
            messageBody: messageBody,
            bodyRanges: bodyRanges,
            editState: editState,
            expiresInSeconds: expiresInSeconds,
            expireStartedAt: expireStartedAt,
            isVoiceMessage: isVoiceMessage,
            groupMetaMessage: groupMetaMessage,
            isViewOnceMessage: isViewOnceMessage,
            changeActionsProtoData: changeActionsProtoData,
            storyAuthorAci: storyAuthorAci,
            storyTimestamp: storyTimestamp,
            storyReactionEmoji: storyReactionEmoji,
            giftBadge: giftBadge
        )
    }

    // MARK: -

    @objc
    public static func outgoingMessageBuilder(
        thread: TSThread
    ) -> TSOutgoingMessageBuilder {
        return .withDefaultValues(thread: thread)
    }

    @objc
    public static func outgoingMessageBuilder(
        thread: TSThread,
        messageBody: String?
    ) -> TSOutgoingMessageBuilder {
        return .withDefaultValues(thread: thread, messageBody: messageBody)
    }

    // MARK: -

    private var hasBuilt = false

    public func build(transaction: SDSAnyReadTransaction) -> TSOutgoingMessage {
        if hasBuilt {
            owsFailDebug("Don't build more than once.")
        }

        hasBuilt = true

        return TSOutgoingMessage(
            outgoingMessageWith: self,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: transaction
        )
    }
}
