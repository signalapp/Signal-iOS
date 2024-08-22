//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objcMembers
public class TSMessageBuilder: NSObject {
    public let thread: TSThread
    public var timestamp: UInt64
    public var receivedAtTimestamp: UInt64
    public var messageBody: String?
    public var bodyRanges: MessageBodyRanges?
    public var editState: TSEditState
    public var expiresInSeconds: UInt32
    public var expireStartedAt: UInt64
    public var isViewOnceMessage: Bool
    public var isViewOnceComplete: Bool
    public var wasRemotelyDeleted: Bool

    public var storyAuthorAci: AciObjC?
    public var storyTimestamp: NSNumber?
    public var storyReactionEmoji: String?
    public var isGroupStoryReply: Bool {
        storyAuthorAci != nil && storyTimestamp != nil && thread.isGroupThread
    }

    public var quotedMessage: TSQuotedMessage?
    public var contactShare: OWSContact?
    public var linkPreview: OWSLinkPreview?
    public var messageSticker: MessageSticker?
    public var giftBadge: OWSGiftBadge?

    @nonobjc
    init(
        thread: TSThread,
        timestamp: UInt64?,
        receivedAtTimestamp: UInt64?,
        messageBody: String?,
        bodyRanges: MessageBodyRanges?,
        editState: TSEditState,
        expiresInSeconds: UInt32?,
        expireStartedAt: UInt64?,
        isViewOnceMessage: Bool,
        isViewOnceComplete: Bool,
        wasRemotelyDeleted: Bool,
        storyAuthorAci: AciObjC?,
        storyTimestamp: UInt64?,
        storyReactionEmoji: String?,
        quotedMessage: TSQuotedMessage?,
        contactShare: OWSContact?,
        linkPreview: OWSLinkPreview?,
        messageSticker: MessageSticker?,
        giftBadge: OWSGiftBadge?
    ) {
        let nowMs = NSDate.ows_millisecondTimeStamp()

        self.thread = thread
        self.timestamp = timestamp ?? nowMs
        self.receivedAtTimestamp = receivedAtTimestamp ?? nowMs
        self.messageBody = messageBody
        self.bodyRanges = bodyRanges
        self.editState = editState
        self.expiresInSeconds = expiresInSeconds ?? 0
        self.expireStartedAt = expireStartedAt ?? 0
        self.isViewOnceMessage = isViewOnceMessage
        self.isViewOnceComplete = isViewOnceComplete
        self.wasRemotelyDeleted = wasRemotelyDeleted
        self.storyAuthorAci = storyAuthorAci
        self.storyTimestamp = storyTimestamp.map { NSNumber(value: $0) }
        self.storyReactionEmoji = storyReactionEmoji

        self.quotedMessage = quotedMessage
        self.contactShare = contactShare
        self.linkPreview = linkPreview
        self.messageSticker = messageSticker
        self.giftBadge = giftBadge
    }

    @nonobjc
    static func withDefaultValues(
        thread: TSThread,
        timestamp: UInt64? = nil,
        receivedAtTimestamp: UInt64? = nil,
        messageBody: String? = nil,
        bodyRanges: MessageBodyRanges? = nil,
        editState: TSEditState = .none,
        expiresInSeconds: UInt32? = nil,
        expireStartedAt: UInt64? = nil,
        isViewOnceMessage: Bool = false,
        isViewOnceComplete: Bool = false,
        wasRemotelyDeleted: Bool = false,
        storyAuthorAci: AciObjC? = nil,
        storyTimestamp: UInt64? = nil,
        storyReactionEmoji: String? = nil,
        quotedMessage: TSQuotedMessage? = nil,
        contactShare: OWSContact? = nil,
        linkPreview: OWSLinkPreview? = nil,
        messageSticker: MessageSticker? = nil,
        giftBadge: OWSGiftBadge? = nil
    ) -> TSMessageBuilder {
        return TSMessageBuilder(
            thread: thread,
            timestamp: timestamp,
            receivedAtTimestamp: receivedAtTimestamp,
            messageBody: messageBody,
            bodyRanges: bodyRanges,
            editState: editState,
            expiresInSeconds: expiresInSeconds,
            expireStartedAt: expireStartedAt,
            isViewOnceMessage: isViewOnceMessage,
            isViewOnceComplete: isViewOnceComplete,
            wasRemotelyDeleted: wasRemotelyDeleted,
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

    public class func messageBuilder(
        thread: TSThread,
        messageBody: String?
    ) -> TSMessageBuilder {
        return .withDefaultValues(thread: thread, messageBody: messageBody)
    }

    public class func messageBuilder(
        thread: TSThread,
        timestamp: UInt64,
        messageBody: String?
    ) -> TSMessageBuilder {
        return .withDefaultValues(thread: thread, timestamp: timestamp, messageBody: messageBody)
    }
}
