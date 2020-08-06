//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// Every time we add a new property to TSOutgoingMessage, we should:
//
// * Add that property here.
// * Handle that property for received sync transcripts.
// * Handle that property in the test factories.
@objc
public class TSOutgoingMessageBuilder: TSMessageBuilder {
    @objc
    public var isVoiceMessage = false
    @objc
    public var groupMetaMessage: TSGroupMetaMessage = .unspecified
    @objc
    public var changeActionsProtoData: Data?
    @objc
    public var additionalRecipients: [SignalServiceAddress]?

    public required init(thread: TSThread,
                         timestamp: UInt64? = nil,
                         messageBody: String? = nil,
                         bodyRanges: MessageBodyRanges? = nil,
                         attachmentIds: [String]? = nil,
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

        super.init(thread: thread,
                   timestamp: timestamp,
                   messageBody: messageBody,
                   bodyRanges: bodyRanges,
                   attachmentIds: attachmentIds,
                   expiresInSeconds: expiresInSeconds,
                   expireStartedAt: expireStartedAt,
                   quotedMessage: quotedMessage,
                   contactShare: contactShare,
                   linkPreview: linkPreview,
                   messageSticker: messageSticker,
                   isViewOnceMessage: isViewOnceMessage)

        self.isVoiceMessage = isVoiceMessage
        self.groupMetaMessage = groupMetaMessage
        self.changeActionsProtoData = changeActionsProtoData
        self.additionalRecipients = additionalRecipients
    }

    @objc
    public class func outgoingMessageBuilder(thread: TSThread) -> TSOutgoingMessageBuilder {
        return TSOutgoingMessageBuilder(thread: thread)
    }

    @objc
    public class func outgoingMessageBuilder(thread: TSThread,
                                             messageBody: String?) -> TSOutgoingMessageBuilder {
        return TSOutgoingMessageBuilder(thread: thread,
                                        messageBody: messageBody)
    }

    // This factory method can be used at call sites that want
    // to specify every property; usage will fail to compile if
    // if any property is missing.
    @objc
    public class func builder(thread: TSThread,
                              timestamp: UInt64,
                              messageBody: String?,
                              bodyRanges: MessageBodyRanges?,
                              attachmentIds: [String]?,
                              expiresInSeconds: UInt32,
                              expireStartedAt: UInt64,
                              isVoiceMessage: Bool,
                              groupMetaMessage: TSGroupMetaMessage,
                              quotedMessage: TSQuotedMessage?,
                              contactShare: OWSContact?,
                              linkPreview: OWSLinkPreview?,
                              messageSticker: MessageSticker?,
                              isViewOnceMessage: Bool,
                              changeActionsProtoData: Data?,
                              additionalRecipients: [SignalServiceAddress]?) -> TSOutgoingMessageBuilder {
        return TSOutgoingMessageBuilder(thread: thread,
                                        timestamp: timestamp,
                                        messageBody: messageBody,
                                        bodyRanges: bodyRanges,
                                        attachmentIds: attachmentIds,
                                        expiresInSeconds: expiresInSeconds,
                                        expireStartedAt: expireStartedAt,
                                        isVoiceMessage: isVoiceMessage,
                                        groupMetaMessage: groupMetaMessage,
                                        quotedMessage: quotedMessage,
                                        contactShare: contactShare,
                                        linkPreview: linkPreview,
                                        messageSticker: messageSticker,
                                        isViewOnceMessage: isViewOnceMessage,
                                        changeActionsProtoData: changeActionsProtoData,
                                        additionalRecipients: additionalRecipients)
    }

    private var hasBuilt = false

    @objc
    public func build() -> TSOutgoingMessage {
        if hasBuilt {
            owsFailDebug("Don't build more than once.")
        }
        hasBuilt = true
        return TSOutgoingMessage(outgoingMessageWithBuilder: self)
    }
}

public extension TSOutgoingMessage {
    @objc func failedRecipientAddresses(errorCode: OWSErrorCode) -> [SignalServiceAddress] {
        guard let states = recipientAddressStates else { return [] }

        return states.filter { _, state in
            return state.state == .failed && state.errorCode?.intValue == errorCode.rawValue
        }.map { $0.key }
    }
}
