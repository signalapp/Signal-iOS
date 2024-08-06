//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Every time we add a new property to TSMessage, we should:
//
// * Add that property here.
// * Handle that property for received sync transcripts.
// * Handle that property in the test factories.
@objc
public class TSMessageBuilder: NSObject {
    @objc
    public let thread: TSThread
    @objc
    public var timestamp: UInt64 = NSDate.ows_millisecondTimeStamp()
    @objc
    public var messageBody: String?
    @objc
    public var bodyRanges: MessageBodyRanges?
    @objc
    public var editState: TSEditState = .none
    @objc
    public var expiresInSeconds: UInt32 = 0
    @objc
    public var expireStartedAt: UInt64 = 0
    @objc
    public var isViewOnceMessage = false
    @objc
    public var read = false
    @objc
    public var storyAuthorAci: AciObjC?
    @objc
    public var storyTimestamp: NSNumber?
    @objc
    public var storyReactionEmoji: String?
    @objc
    public var isGroupStoryReply: Bool {
        storyAuthorAci != nil && storyTimestamp != nil && thread.isGroupThread
    }
    @objc
    public var giftBadge: OWSGiftBadge?

    init(
        thread: TSThread,
        timestamp: UInt64?,
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
        self.thread = thread
        self.timestamp = timestamp ?? self.timestamp
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

    static func withDefaultValues(
        thread: TSThread,
        timestamp: UInt64? = nil,
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

    @objc
    public class func messageBuilder(
        thread: TSThread,
        messageBody: String?
    ) -> TSMessageBuilder {
        return .withDefaultValues(thread: thread, messageBody: messageBody)
    }

    @objc
    public class func messageBuilder(
        thread: TSThread,
        timestamp: UInt64,
        messageBody: String?
    ) -> TSMessageBuilder {
        return .withDefaultValues(thread: thread, timestamp: timestamp, messageBody: messageBody)
    }
}
