
@objc(LKSessionRequestMessage)
internal final class SessionRequestMessage : TSOutgoingMessage {

    @objc internal override var ttl: UInt32 { return UInt32(TTLUtilities.getTTL(for: .sessionRequest)) }

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

    override func prepareCustomContentBuilder(_ recipient: SignalRecipient) -> Any? {
        guard let contentBuilder = super.prepareCustomContentBuilder(recipient) as? SSKProtoContent.SSKProtoContentBuilder else { return nil }
        // Attach a null message
        let nullMessageBuilder = SSKProtoNullMessage.builder()
        let paddingSize = UInt.random(in: 0..<512) // random(in:) uses the system's default random generator, which is cryptographically secure
        let padding = Cryptography.generateRandomBytes(paddingSize)
        nullMessageBuilder.setPadding(padding)
        do {
            let nullMessage = try nullMessageBuilder.build()
            contentBuilder.setNullMessage(nullMessage)
        } catch {
            owsFailDebug("Failed to build session request message for: \(recipient.recipientId()) due to error: \(error).")
            return nil
        }
        // Generate a pre key bundle for the recipient and attach it
        let preKeyBundle = OWSPrimaryStorage.shared().generatePreKeyBundle(forContact: recipient.recipientId())
        let preKeyBundleMessageBuilder = SSKProtoPrekeyBundleMessage.builder(from: preKeyBundle)
        do {
            let preKeyBundleMessage = try preKeyBundleMessageBuilder.build()
            contentBuilder.setPrekeyBundleMessage(preKeyBundleMessage)
        } catch {
            owsFailDebug("Failed to build session request message for: \(recipient.recipientId()) due to error: \(error).")
            return nil
        }
        // Return
        return contentBuilder
    }
}
