//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

@objcMembers
public class TSOutgoingMessageBuilder: TSMessageBuilder {
    public var isVoiceMessage: Bool
    public var groupMetaMessage: TSGroupMetaMessage
    public var groupChangeProtoData: Data?

    @nonobjc
    public init(
        thread: TSThread,
        timestamp: UInt64?,
        receivedAtTimestamp: UInt64?,
        messageBody: String?,
        bodyRanges: MessageBodyRanges?,
        editState: TSEditState,
        expiresInSeconds: UInt32?,
        expireTimerVersion: UInt32?,
        expireStartedAt: UInt64?,
        isVoiceMessage: Bool,
        groupMetaMessage: TSGroupMetaMessage,
        isSmsMessageRestoredFromBackup: Bool,
        isViewOnceMessage: Bool,
        isViewOnceComplete: Bool,
        wasRemotelyDeleted: Bool,
        groupChangeProtoData: Data?,
        storyAuthorAci: Aci?,
        storyTimestamp: UInt64?,
        storyReactionEmoji: String?,
        quotedMessage: TSQuotedMessage?,
        contactShare: OWSContact?,
        linkPreview: OWSLinkPreview?,
        messageSticker: MessageSticker?,
        giftBadge: OWSGiftBadge?
    ) {
        self.isVoiceMessage = isVoiceMessage
        self.groupMetaMessage = groupMetaMessage
        self.groupChangeProtoData = groupChangeProtoData

        super.init(
            thread: thread,
            timestamp: timestamp,
            receivedAtTimestamp: receivedAtTimestamp,
            messageBody: messageBody,
            bodyRanges: bodyRanges,
            editState: editState,
            expiresInSeconds: expiresInSeconds,
            expireTimerVersion: expireTimerVersion,
            expireStartedAt: expireStartedAt,
            isSmsMessageRestoredFromBackup: isSmsMessageRestoredFromBackup,
            isViewOnceMessage: isViewOnceMessage,
            isViewOnceComplete: isViewOnceComplete,
            wasRemotelyDeleted: wasRemotelyDeleted,
            storyAuthorAci: storyAuthorAci.map { AciObjC($0) },
            storyTimestamp: storyTimestamp,
            storyReactionEmoji: storyReactionEmoji,
            quotedMessage: quotedMessage,
            contactShare: contactShare,
            linkPreview: linkPreview,
            messageSticker: messageSticker,
            giftBadge: giftBadge
        )
    }

    @nonobjc
    public static func withDefaultValues(
        thread: TSThread,
        timestamp: UInt64? = nil,
        receivedAtTimestamp: UInt64? = nil,
        messageBody: String? = nil,
        bodyRanges: MessageBodyRanges? = nil,
        editState: TSEditState = .none,
        expiresInSeconds: UInt32? = nil,
        expireTimerVersion: UInt32? = nil,
        expireStartedAt: UInt64? = nil,
        isVoiceMessage: Bool = false,
        groupMetaMessage: TSGroupMetaMessage = .unspecified,
        isSmsMessageRestoredFromBackup: Bool = false,
        isViewOnceMessage: Bool = false,
        isViewOnceComplete: Bool = false,
        wasRemotelyDeleted: Bool = false,
        groupChangeProtoData: Data? = nil,
        storyAuthorAci: Aci? = nil,
        storyTimestamp: UInt64? = nil,
        storyReactionEmoji: String? = nil,
        quotedMessage: TSQuotedMessage? = nil,
        contactShare: OWSContact? = nil,
        linkPreview: OWSLinkPreview? = nil,
        messageSticker: MessageSticker? = nil,
        giftBadge: OWSGiftBadge? = nil
    ) -> TSOutgoingMessageBuilder {
        return TSOutgoingMessageBuilder(
            thread: thread,
            timestamp: timestamp,
            receivedAtTimestamp: receivedAtTimestamp,
            messageBody: messageBody,
            bodyRanges: bodyRanges,
            editState: editState,
            expiresInSeconds: expiresInSeconds,
            expireTimerVersion: expireTimerVersion,
            expireStartedAt: expireStartedAt,
            isVoiceMessage: isVoiceMessage,
            groupMetaMessage: groupMetaMessage,
            isSmsMessageRestoredFromBackup: isSmsMessageRestoredFromBackup,
            isViewOnceMessage: isViewOnceMessage,
            isViewOnceComplete: isViewOnceComplete,
            wasRemotelyDeleted: wasRemotelyDeleted,
            groupChangeProtoData: groupChangeProtoData,
            storyAuthorAci: storyAuthorAci,
            storyTimestamp: storyTimestamp,
            storyReactionEmoji: storyReactionEmoji,
            quotedMessage: quotedMessage,
            contactShare: contactShare,
            linkPreview: linkPreview,
            messageSticker: messageSticker,
            giftBadge: giftBadge
        )
    }

    // MARK: -

    public static func outgoingMessageBuilder(
        thread: TSThread
    ) -> TSOutgoingMessageBuilder {
        return .withDefaultValues(thread: thread)
    }

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
