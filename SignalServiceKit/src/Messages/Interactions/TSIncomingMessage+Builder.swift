//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// Every time we add a new property to TSIncomingMessage, we should:
//
// * Add that property here.
// * Handle that property in the test factories.
@objc
public class TSIncomingMessageBuilder: TSMessageBuilder {
    @objc
    public var authorAddress: SignalServiceAddress?
    @objc
    public var sourceDeviceId: UInt32 = OWSDevicePrimaryDeviceId
    @objc
    public var serverTimestamp: NSNumber?
    @objc
    public var serverDeliveryTimestamp: UInt64 = 0
    @objc
    public var wasReceivedByUD = false

    public required init(thread: TSThread,
                         timestamp: UInt64? = nil,
                         authorAddress: SignalServiceAddress? = nil,
                         sourceDeviceId: UInt32 = 0,
                         messageBody: String? = nil,
                         bodyRanges: MessageBodyRanges? = nil,
                         attachmentIds: [String]? = nil,
                         expiresInSeconds: UInt32 = 0,
                         quotedMessage: TSQuotedMessage? = nil,
                         contactShare: OWSContact? = nil,
                         linkPreview: OWSLinkPreview? = nil,
                         messageSticker: MessageSticker? = nil,
                         serverTimestamp: NSNumber? = nil,
                         serverDeliveryTimestamp: UInt64 = 0,
                         wasReceivedByUD: Bool = false,
                         isViewOnceMessage: Bool = false) {

        super.init(thread: thread,
                   timestamp: timestamp,
                   messageBody: messageBody,
                   bodyRanges: bodyRanges,
                   attachmentIds: attachmentIds,
                   expiresInSeconds: expiresInSeconds,
                   // expireStartedAt is always initialized to zero
            // for incoming messages.
            expireStartedAt: 0,
            quotedMessage: quotedMessage,
            contactShare: contactShare,
            linkPreview: linkPreview,
            messageSticker: messageSticker,
            isViewOnceMessage: isViewOnceMessage)

        self.authorAddress = authorAddress
        self.sourceDeviceId = sourceDeviceId
        self.serverTimestamp = serverTimestamp
        self.serverDeliveryTimestamp = serverDeliveryTimestamp
        self.wasReceivedByUD = wasReceivedByUD
    }

    @objc
    public class func incomingMessageBuilder(thread: TSThread) -> TSIncomingMessageBuilder {
        return TSIncomingMessageBuilder(thread: thread)
    }

    @objc
    public class func incomingMessageBuilder(thread: TSThread,
                                             messageBody: String?) -> TSIncomingMessageBuilder {
        return TSIncomingMessageBuilder(thread: thread,
                                        messageBody: messageBody)
    }

    // This factory method can be used at call sites that want
    // to specify every property; usage will fail to compile if
    // if any property is missing.
    @objc
    public class func builder(thread: TSThread,
                              timestamp: UInt64,
                              authorAddress: SignalServiceAddress?,
                              sourceDeviceId: UInt32,
                              messageBody: String?,
                              bodyRanges: MessageBodyRanges?,
                              attachmentIds: [String]?,
                              expiresInSeconds: UInt32,
                              quotedMessage: TSQuotedMessage?,
                              contactShare: OWSContact?,
                              linkPreview: OWSLinkPreview?,
                              messageSticker: MessageSticker?,
                              serverTimestamp: NSNumber?,
                              serverDeliveryTimestamp: UInt64,
                              wasReceivedByUD: Bool,
                              isViewOnceMessage: Bool) -> TSIncomingMessageBuilder {
        return TSIncomingMessageBuilder(thread: thread,
                                        timestamp: timestamp,
                                        authorAddress: authorAddress,
                                        sourceDeviceId: sourceDeviceId,
                                        messageBody: messageBody,
                                        bodyRanges: bodyRanges,
                                        attachmentIds: attachmentIds,
                                        expiresInSeconds: expiresInSeconds,
                                        quotedMessage: quotedMessage,
                                        contactShare: contactShare,
                                        linkPreview: linkPreview,
                                        messageSticker: messageSticker,
                                        serverTimestamp: serverTimestamp,
                                        serverDeliveryTimestamp: serverDeliveryTimestamp,
                                        wasReceivedByUD: wasReceivedByUD,
                                        isViewOnceMessage: isViewOnceMessage)
    }

    private var hasBuilt = false

    @objc
    public func build() -> TSIncomingMessage {
        if hasBuilt {
            owsFailDebug("Don't build more than once.")
        }
        hasBuilt = true
        return TSIncomingMessage(incomingMessageWithBuilder: self)
    }
}
