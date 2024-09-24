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
    public var expireTimerVersion: NSNumber?
    public var expireStartedAt: UInt64
    public var isSmsMessageRestoredFromBackup: Bool
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
        expireTimerVersion: UInt32?,
        expireStartedAt: UInt64?,
        isSmsMessageRestoredFromBackup: Bool,
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
        self.expireTimerVersion = expireTimerVersion.map(NSNumber.init(value:))
        self.expireStartedAt = expireStartedAt ?? 0
        self.isSmsMessageRestoredFromBackup = isSmsMessageRestoredFromBackup
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

    /// NOTE: if expiresInSeconds is set, expireTimerVersion should also be set (even if its nil, which is a valid input)
    /// Setting expiresInSeconds without passing along the version from the caller/proto can lead to bugs.
    @nonobjc
    static func withDefaultValues(
        thread: TSThread,
        timestamp: UInt64? = nil,
        receivedAtTimestamp: UInt64? = nil,
        messageBody: String? = nil,
        bodyRanges: MessageBodyRanges? = nil,
        editState: TSEditState = .none,
        expiresInSeconds: UInt32? = nil,
        expireTimerVersion: UInt32? = nil,
        expireStartedAt: UInt64? = nil,
        isSmsMessageRestoredFromBackup: Bool = false,
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
            expireTimerVersion: expireTimerVersion,
            expireStartedAt: expireStartedAt,
            isSmsMessageRestoredFromBackup: isSmsMessageRestoredFromBackup,
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

    class func messageBuilder(thread: TSThread) -> TSMessageBuilder {
        return .withDefaultValues(thread: thread)
    }

    class func messageBuilder(thread: TSThread, timestamp: UInt64) -> TSMessageBuilder {
        return .withDefaultValues(thread: thread, timestamp: timestamp)
    }
}
