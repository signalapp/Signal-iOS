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
    public var read: Bool
    public var storyAuthorAci: AciObjC?
    public var storyTimestamp: NSNumber?
    public var storyReactionEmoji: String?
    public var giftBadge: OWSGiftBadge?

    public var isGroupStoryReply: Bool {
        storyAuthorAci != nil && storyTimestamp != nil && thread.isGroupThread
    }

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
        read: Bool,
        storyAuthorAci: AciObjC?,
        storyTimestamp: UInt64?,
        storyReactionEmoji: String?,
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
        self.read = read
        self.storyAuthorAci = storyAuthorAci
        self.storyTimestamp = storyTimestamp.map { NSNumber(value: $0) }
        self.storyReactionEmoji = storyReactionEmoji
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
        read: Bool = false,
        storyAuthorAci: AciObjC? = nil,
        storyTimestamp: UInt64? = nil,
        storyReactionEmoji: String? = nil,
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
            read: read,
            storyAuthorAci: storyAuthorAci,
            storyTimestamp: storyTimestamp,
            storyReactionEmoji: storyReactionEmoji,
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
