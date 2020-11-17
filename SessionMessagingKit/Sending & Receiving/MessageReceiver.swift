import SessionUtilitiesKit

internal enum MessageReceiver {

    internal enum Error : LocalizedError {
        case invalidMessage
        case unknownMessage
        case unknownEnvelopeType
        case noUserPublicKey
        case noData
        case senderBlocked
        // Shared sender keys
        case invalidGroupPublicKey
        case noGroupPrivateKey
        case sharedSecretGenerationFailed
        case selfSend

        internal var errorDescription: String? {
            switch self {
            case .invalidMessage: return "Invalid message."
            case .unknownMessage: return "Unknown message type."
            case .unknownEnvelopeType: return "Unknown envelope type."
            case .noUserPublicKey: return "Couldn't find user key pair."
            case .noData: return "Received an empty envelope."
            case .senderBlocked: return "Received a message from a blocked user."
            // Shared sender keys
            case .invalidGroupPublicKey: return "Invalid group public key."
            case .noGroupPrivateKey: return "Missing group private key."
            case .sharedSecretGenerationFailed: return "Couldn't generate a shared secret."
            case .selfSend: return "Message addressed at self."
            }
        }
    }

    internal static func parse(_ data: Data, using transaction: Any) throws -> Message {
        // Parse the envelope
        let envelope = try SNProtoEnvelope.parseData(data)
        // Decrypt the contents
        let plaintext: Data
        let sender: String
        switch envelope.type {
        case .unidentifiedSender: (plaintext, sender) = try decryptWithSignalProtocol(envelope: envelope, using: transaction)
        case .closedGroupCiphertext: (plaintext, sender) = try decryptWithSharedSenderKeys(envelope: envelope, using: transaction)
        default: throw Error.unknownEnvelopeType
        }
        // Don't process the envelope any further if the sender is blocked
        guard !Configuration.shared.storage.isBlocked(sender) else { throw Error.senderBlocked }
        // Parse the proto
        let proto: SNProtoContent
        do {
            proto = try SNProtoContent.parseData((plaintext as NSData).removePadding())
        } catch {
            SNLog("Couldn't parse proto due to error: \(error).")
            throw error
        }
        // Parse the message
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
            message.sender = sender
            message.recipient = Configuration.shared.storage.getUserPublicKey()
            message.receivedTimestamp = NSDate.millisecondTimestamp()
            guard message.isValid else { throw Error.invalidMessage }
            return message
        } else {
            throw Error.unknownMessage
        }
    }

    internal static func handle(_ message: Message, messageServerID: UInt64?, using transaction: Any) {
        switch message {
        case is ReadReceipt: break
        case is SessionRequest: break
        case is TypingIndicator: break
        case is ClosedGroupUpdate: break
        case is ExpirationTimerUpdate: break
        case let message as VisibleMessage: handleVisibleMessage(message, using: transaction)
        default: fatalError()
        }
    }

    private static func handleVisibleMessage(_ message: VisibleMessage, using transaction: Any) {
        let storage = Configuration.shared.storage
        // Update profile if needed
        if let profile = message.profile {
            storage.updateProfile(for: message.sender!, from: profile, using: transaction)
        }
        // Persist the message
        let (threadID, tsIncomingMessage) = storage.persist(message, using: transaction)
        message.threadID = threadID
        // Cancel any typing indicators
        storage.cancelTypingIndicatorsIfNeeded(for: message.threadID!, senderPublicKey: message.sender!)
        // Notify the user if needed
        storage.notifyUserIfNeeded(for: tsIncomingMessage, threadID: threadID)
    }
}
