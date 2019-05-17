
@objc public extension TSOutgoingMessage {
    
    /// Loki: This is a message used to establish sessions
    @objc public static func createEmptyOutgoingMessage(inThread thread: TSThread) -> EphemeralMessage {
        return EphemeralMessage(outgoingMessageWithTimestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageBody: "", attachmentIds: [], expiresInSeconds: 0,
            expireStartedAt: 0, isVoiceMessage: false, groupMetaMessage: .unspecified, quotedMessage: nil, contactShare: nil, linkPreview: nil)
    }
}
