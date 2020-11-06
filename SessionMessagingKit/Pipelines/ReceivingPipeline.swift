import SessionUtilities

public enum ReceivingPipeline {

    public enum Error : LocalizedError {
        case invalidMessage
        // Shared sender keys
        case invalidGroupPublicKey
        case noData
        case noGroupPrivateKey
        case sharedSecretGenerationFailed
        case selfSend

        public var errorDescription: String? {
            switch self {
            case .invalidMessage: return "Invalid message."
            // Shared sender keys
            case .invalidGroupPublicKey: return "Invalid group public key."
            case .noData: return "Received an empty envelope."
            case .noGroupPrivateKey: return "Missing group private key."
            case .sharedSecretGenerationFailed: return "Couldn't generate a shared secret."
            case .selfSend: return "Message addressed at self."
            }
        }
    }

    public static func parse(_ ciphertext: Data) -> Message? {
        let plaintext = ciphertext // TODO: Decryption
        let proto: SNProtoContent
        do {
            proto = try SNProtoContent.parseData(plaintext)
        } catch {
            SNLog("Couldn't parse proto due to error: \(error).")
            return nil
        }
        let message: Message? = {
            if let readReceipt = ReadReceipt.fromProto(proto) { return readReceipt }
            if let sessionRequest = SessionRequest.fromProto(proto) { return sessionRequest }
            if let typingIndicator = TypingIndicator.fromProto(proto) { return typingIndicator }
            if let closedGroupUpdate = ClosedGroupUpdate.fromProto(proto) { return closedGroupUpdate }
            if let expirationTimerUpdate = ExpirationTimerUpdate.fromProto(proto) { return expirationTimerUpdate }
            if let visibleMessage = VisibleMessage.fromProto(proto) { return visibleMessage }
            return nil
        }()
        if let message = message {
            guard message.isValid else { return nil }
            return message
        } else {
            return nil
        }
    }
}
