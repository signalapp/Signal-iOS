//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Every time we add a new property to TSIncomingMessage, we should:
//
// * Add that property here.
// * Handle that property in the test factories.
@objc
public class TSIncomingMessageBuilder: TSMessageBuilder {
    @objc
    public var authorAci: ServiceIdObjC?
    @objc
    public var sourceDeviceId: UInt32 = OWSDevice.primaryDeviceId
    @objc
    public var serverTimestamp: NSNumber?
    @objc
    public var serverDeliveryTimestamp: UInt64 = 0
    @objc
    public var serverGuid: String?
    @objc
    public var wasReceivedByUD = false

    public required init(thread: TSThread,
                         timestamp: UInt64? = nil,
                         authorAci: ServiceId? = nil,
                         sourceDeviceId: UInt32 = 0,
                         messageBody: String? = nil,
                         bodyRanges: MessageBodyRanges? = nil,
                         attachmentIds: [String]? = nil,
                         editState: TSEditState = .none,
                         expiresInSeconds: UInt32 = 0,
                         // expireStartedAt should always initialized to zero for new incoming messages.
                         expireStartedAt: UInt64 = 0,
                         quotedMessage: TSQuotedMessage? = nil,
                         contactShare: OWSContact? = nil,
                         linkPreview: OWSLinkPreview? = nil,
                         messageSticker: MessageSticker? = nil,
                         read: Bool = false,
                         serverTimestamp: NSNumber? = nil,
                         serverDeliveryTimestamp: UInt64 = 0,
                         serverGuid: String? = nil,
                         wasReceivedByUD: Bool = false,
                         isViewOnceMessage: Bool = false,
                         storyAuthorAddress: SignalServiceAddress? = nil,
                         storyTimestamp: UInt64? = nil,
                         storyReactionEmoji: String? = nil,
                         giftBadge: OWSGiftBadge? = nil) {

        super.init(thread: thread,
                   timestamp: timestamp,
                   messageBody: messageBody,
                   bodyRanges: bodyRanges,
                   attachmentIds: attachmentIds,
                   editState: editState,
                   expiresInSeconds: expiresInSeconds,
                   expireStartedAt: expireStartedAt,
                   quotedMessage: quotedMessage,
                   contactShare: contactShare,
                   linkPreview: linkPreview,
                   messageSticker: messageSticker,
                   isViewOnceMessage: isViewOnceMessage,
                   read: read,
                   storyAuthorAddress: storyAuthorAddress,
                   storyTimestamp: storyTimestamp,
                   storyReactionEmoji: storyReactionEmoji,
                   giftBadge: giftBadge)

        self.authorAci = authorAci.map { ServiceIdObjC($0) }
        self.sourceDeviceId = sourceDeviceId
        self.serverTimestamp = serverTimestamp
        self.serverDeliveryTimestamp = serverDeliveryTimestamp
        self.serverGuid = serverGuid
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
                              authorAci: ServiceIdObjC?,
                              sourceDeviceId: UInt32,
                              messageBody: String?,
                              bodyRanges: MessageBodyRanges?,
                              attachmentIds: [String]?,
                              editState: TSEditState,
                              expiresInSeconds: UInt32,
                              quotedMessage: TSQuotedMessage?,
                              contactShare: OWSContact?,
                              linkPreview: OWSLinkPreview?,
                              messageSticker: MessageSticker?,
                              serverTimestamp: NSNumber?,
                              serverDeliveryTimestamp: UInt64,
                              serverGuid: String?,
                              wasReceivedByUD: Bool,
                              isViewOnceMessage: Bool,
                              storyAuthorAddress: SignalServiceAddress?,
                              storyTimestamp: NSNumber?,
                              storyReactionEmoji: String?,
                              giftBadge: OWSGiftBadge?) -> TSIncomingMessageBuilder {
        return TSIncomingMessageBuilder(thread: thread,
                                        timestamp: timestamp,
                                        authorAci: authorAci?.wrappedValue,
                                        sourceDeviceId: sourceDeviceId,
                                        messageBody: messageBody,
                                        bodyRanges: bodyRanges,
                                        attachmentIds: attachmentIds,
                                        editState: editState,
                                        expiresInSeconds: expiresInSeconds,
                                        quotedMessage: quotedMessage,
                                        contactShare: contactShare,
                                        linkPreview: linkPreview,
                                        messageSticker: messageSticker,
                                        serverTimestamp: serverTimestamp,
                                        serverDeliveryTimestamp: serverDeliveryTimestamp,
                                        serverGuid: serverGuid,
                                        wasReceivedByUD: wasReceivedByUD,
                                        isViewOnceMessage: isViewOnceMessage,
                                        storyAuthorAddress: storyAuthorAddress,
                                        storyTimestamp: storyTimestamp?.uint64Value,
                                        storyReactionEmoji: storyReactionEmoji,
                                        giftBadge: giftBadge)
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
