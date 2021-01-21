//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// Every time we add a new property to TSErrorMessage, we should:
//
// * Add that property here.
// * Handle that property in the test factories.
@objc
public class TSErrorMessageBuilder: TSMessageBuilder {
    @objc
    public let errorType: TSErrorMessageType
    @objc
    public var recipientAddress: SignalServiceAddress?
    @objc
    public var wasIdentityVerified: Bool

    public required init(thread: TSThread,
                         timestamp: UInt64? = nil,
                         messageBody: String? = nil,
                         bodyRanges: MessageBodyRanges? = nil,
                         attachmentIds: [String]? = nil,
                         expiresInSeconds: UInt32 = 0,
                         quotedMessage: TSQuotedMessage? = nil,
                         contactShare: OWSContact? = nil,
                         linkPreview: OWSLinkPreview? = nil,
                         messageSticker: MessageSticker? = nil,
                         isViewOnceMessage: Bool = false,
                         errorType: TSErrorMessageType,
                         recipientAddress: SignalServiceAddress? = nil,
                         wasIdentityVerified: Bool = false) {

        self.errorType = errorType
        self.recipientAddress = recipientAddress
        self.wasIdentityVerified = wasIdentityVerified

        super.init(thread: thread,
                   timestamp: timestamp,
                   messageBody: messageBody,
                   bodyRanges: bodyRanges,
                   attachmentIds: attachmentIds,
                   expiresInSeconds: expiresInSeconds,
                   // expireStartedAt is always initialized to zero
                   // for error messages.
                   expireStartedAt: 0,
                   quotedMessage: quotedMessage,
                   contactShare: contactShare,
                   linkPreview: linkPreview,
                   messageSticker: messageSticker,
                   isViewOnceMessage: isViewOnceMessage)
    }

    @objc
    public class func errorMessageBuilder(thread: TSThread,
                                          errorType: TSErrorMessageType) -> TSErrorMessageBuilder {
        TSErrorMessageBuilder(thread: thread, errorType: errorType)
    }

    @objc
    public class func errorMessageBuilder(errorType: TSErrorMessageType,
                                          envelope: SSKProtoEnvelope,
                                          transaction: SDSAnyWriteTransaction) -> TSErrorMessageBuilder {
        let thread = TSContactThread.getOrCreateThread(withContactAddress: envelope.sourceAddress!,
                                                       transaction: transaction)
        return TSErrorMessageBuilder(thread: thread, errorType: errorType)
    }

    private var hasBuilt = false

    @objc
    public func build() -> TSErrorMessage {
        if hasBuilt {
            owsFailDebug("Don't build more than once.")
        }
        hasBuilt = true
        return TSErrorMessage(errorMessageWithBuilder: self)
    }
}
