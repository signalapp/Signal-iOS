//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
    public var attachmentIds = [String]()
    @objc
    public var expiresInSeconds: UInt32 = 0
    @objc
    public var expireStartedAt: UInt64 = 0
    @objc
    public var quotedMessage: TSQuotedMessage?
    @objc
    public var contactShare: OWSContact?
    @objc
    public var linkPreview: OWSLinkPreview?
    @objc
    public var messageSticker: MessageSticker?
    @objc
    public var isViewOnceMessage = false

    init(thread: TSThread,
         timestamp: UInt64? = nil,
         messageBody: String? = nil,
         bodyRanges: MessageBodyRanges? = nil,
         attachmentIds: [String]? = nil,
         expiresInSeconds: UInt32 = 0,
         expireStartedAt: UInt64 = 0,
         quotedMessage: TSQuotedMessage? = nil,
         contactShare: OWSContact? = nil,
         linkPreview: OWSLinkPreview? = nil,
         messageSticker: MessageSticker? = nil,
         isViewOnceMessage: Bool = false) {
        self.thread = thread

        if let timestamp = timestamp {
            self.timestamp = timestamp
        }
        self.messageBody = messageBody
        self.bodyRanges = bodyRanges
        if let attachmentIds = attachmentIds {
            self.attachmentIds = attachmentIds
        }
        self.expiresInSeconds = expiresInSeconds
        self.expireStartedAt = expireStartedAt
        self.quotedMessage = quotedMessage
        self.contactShare = contactShare
        self.linkPreview = linkPreview
        self.messageSticker = messageSticker
        self.isViewOnceMessage = isViewOnceMessage
    }

    @objc
    public class func messageBuilder(thread: TSThread) -> TSMessageBuilder {
        return TSMessageBuilder(thread: thread)
    }

    @objc
    public class func messageBuilder(thread: TSThread,
                                     messageBody: String?) -> TSMessageBuilder {
        return TSMessageBuilder(thread: thread,
                                messageBody: messageBody)
    }

    @objc
    public class func messageBuilder(thread: TSThread,
                                     timestamp: UInt64,
                                     messageBody: String?) -> TSMessageBuilder {
        return TSMessageBuilder(thread: thread,
                                timestamp: timestamp,
                                messageBody: messageBody)
    }

    @objc(applyDisappearingMessagesConfiguration:)
    public func apply(configuration: OWSDisappearingMessagesConfiguration) {
        expiresInSeconds = (configuration.isEnabled
            ? configuration.durationSeconds
            : 0)
    }

    #if TESTABLE_BUILD
    @objc
    public func addAttachmentId(_ attachmentId: String) {
        attachmentIds = attachmentIds + [attachmentId ]
    }
    #endif
}
