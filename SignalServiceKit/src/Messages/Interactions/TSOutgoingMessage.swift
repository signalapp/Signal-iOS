//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class TSOutgoingMessageBuilder: NSObject {
    @objc
    public let thread: TSThread
    @objc
    public var timestamp: UInt64 = NSDate.ows_millisecondTimeStamp()
    @objc
    public var messageBody: String?
    @objc
    public var attachmentIds = NSMutableArray()
    @objc
    public var expiresInSeconds: UInt32 = 0
    @objc
    public var expireStartedAt: UInt64 = 0
    @objc
    public var isVoiceMessage = false
    @objc
    public var groupMetaMessage: TSGroupMetaMessage = .unspecified
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
    @objc
    public var changeActionsProtoData: Data?
    @objc
    public var additionalRecipients: [SignalServiceAddress]?

    @objc
    public required init(thread: TSThread) {
        self.thread = thread
    }

    @objc
    public required init(thread: TSThread,
                         messageBody: String?) {
        self.thread = thread
        self.messageBody = messageBody
    }

    public required init(thread: TSThread,
                         timestamp: UInt64? = nil,
                         messageBody: String? = nil,
                         attachmentIds: NSMutableArray? = nil,
                         expiresInSeconds: UInt32 = 0,
                         expireStartedAt: UInt64 = 0,
                         isVoiceMessage: Bool = false,
                         groupMetaMessage: TSGroupMetaMessage = .unspecified,
                         quotedMessage: TSQuotedMessage? = nil,
                         contactShare: OWSContact? = nil,
                         linkPreview: OWSLinkPreview? = nil,
                         messageSticker: MessageSticker? = nil,
                         isViewOnceMessage: Bool = false,
                         changeActionsProtoData: Data? = nil,
                         additionalRecipients: [SignalServiceAddress]? = nil) {
        self.thread = thread

        if let timestamp = timestamp {
            self.timestamp = timestamp
        }
        self.messageBody = messageBody
        if let attachmentIds = attachmentIds {
            self.attachmentIds = attachmentIds
        }
        self.expiresInSeconds = expiresInSeconds
        self.expireStartedAt = expireStartedAt
        self.isVoiceMessage = isVoiceMessage
        self.groupMetaMessage = groupMetaMessage
        self.quotedMessage = quotedMessage
        self.contactShare = contactShare
        self.linkPreview = linkPreview
        self.messageSticker = messageSticker
        self.isViewOnceMessage = isViewOnceMessage
        self.changeActionsProtoData = changeActionsProtoData
        self.additionalRecipients = additionalRecipients
    }

    @objc(applyDisappearingMessagesConfiguration:)
    public func apply(configuration: OWSDisappearingMessagesConfiguration) {
        expiresInSeconds = (configuration.isEnabled
            ? configuration.durationSeconds
            : 0)
    }

    @objc
    public func build() -> TSOutgoingMessage {
        return TSOutgoingMessage(outgoingMessageWithBuilder: self)
    }
}
