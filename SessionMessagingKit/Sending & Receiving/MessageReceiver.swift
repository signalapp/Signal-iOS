import SessionUtilities

internal enum MessageReceiver {

    internal enum Error : LocalizedError {
        case invalidMessage
        case unknownMessage
        // Shared sender keys
        case invalidGroupPublicKey
        case noData
        case noGroupPrivateKey
        case sharedSecretGenerationFailed
        case selfSend

        internal var errorDescription: String? {
            switch self {
            case .invalidMessage: return "Invalid message."
            case .unknownMessage: return "Unknown message type."
            // Shared sender keys
            case .invalidGroupPublicKey: return "Invalid group public key."
            case .noData: return "Received an empty envelope."
            case .noGroupPrivateKey: return "Missing group private key."
            case .sharedSecretGenerationFailed: return "Couldn't generate a shared secret."
            case .selfSend: return "Message addressed at self."
            }
        }
    }

    internal static func parse(_ ciphertext: Data) throws -> Message {
        let plaintext = ciphertext
        let proto: SNProtoContent
        do {
            proto = try SNProtoContent.parseData(plaintext)
        } catch {
            SNLog("Couldn't parse proto due to error: \(error).")
            throw error
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
            guard message.isValid else { throw Error.invalidMessage }
            return message
        } else {
            throw Error.unknownMessage
        }
    }
}
