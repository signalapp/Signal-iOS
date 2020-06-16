
@objc(LKEphemeralMessage)
internal final class EphemeralMessage : TSOutgoingMessage {

    @objc internal override var ttl: UInt32 { return UInt32(TTLUtilities.getTTL(for: .ephemeral)) }

    @objc internal override func shouldBeSaved() -> Bool { return false }
    @objc internal override func shouldSyncTranscript() -> Bool { return false }

    @objc internal init(thread: TSThread) {
        super.init(outgoingMessageWithTimestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageBody: "",
            attachmentIds: NSMutableArray(), expiresInSeconds: 0, expireStartedAt: 0, isVoiceMessage: false,
            groupMetaMessage: .unspecified, quotedMessage: nil, contactShare: nil, linkPreview: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required init(dictionary: [String:Any]) throws {
        try super.init(dictionary: dictionary)
    }
}
