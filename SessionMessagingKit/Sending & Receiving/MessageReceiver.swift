import SessionUtilitiesKit

internal enum MessageReceiver {

    internal enum Error : LocalizedError {
        case duplicateMessage
        case invalidMessage
        case unknownMessage
        case unknownEnvelopeType
        case noUserPublicKey
        case noData
        case senderBlocked
        case noThread
        case selfSend
        // Shared sender keys
        case invalidGroupPublicKey
        case noGroupPrivateKey
        case sharedSecretGenerationFailed

        internal var isRetryable: Bool {
            switch self {
            case .duplicateMessage, .invalidMessage, .unknownMessage, .unknownEnvelopeType, .noData, .senderBlocked, .selfSend: return false
            default: return true
            }
        }

        internal var errorDescription: String? {
            switch self {
            case .duplicateMessage: return "Duplicate message."
            case .invalidMessage: return "Invalid message."
            case .unknownMessage: return "Unknown message type."
            case .unknownEnvelopeType: return "Unknown envelope type."
            case .noUserPublicKey: return "Couldn't find user key pair."
            case .noData: return "Received an empty envelope."
            case .senderBlocked: return "Received a message from a blocked user."
            case .noThread: return "Couldn't find thread for message."
            // Shared sender keys
            case .invalidGroupPublicKey: return "Invalid group public key."
            case .noGroupPrivateKey: return "Missing group private key."
            case .sharedSecretGenerationFailed: return "Couldn't generate a shared secret."
            case .selfSend: return "Message addressed at self."
            }
        }
    }

    internal static func parse(_ data: Data, openGroupMessageServerID: UInt64?, using transaction: Any) throws -> (Message, SNProtoContent) {
        let userPublicKey = Configuration.shared.storage.getUserPublicKey()
        let isOpenGroupMessage = (openGroupMessageServerID != nil)
        // Parse the envelope
        let envelope = try SNProtoEnvelope.parseData(data)
        let storage = Configuration.shared.storage
        guard !Set(storage.getReceivedMessageTimestamps(using: transaction)).contains(envelope.timestamp) else { throw Error.duplicateMessage }
        storage.addReceivedMessageTimestamp(envelope.timestamp, using: transaction)
        // Decrypt the contents
        let plaintext: Data
        let sender: String
        var groupPublicKey: String? = nil
        if isOpenGroupMessage {
            (plaintext, sender) = (envelope.content!, envelope.source!)
        } else {
            switch envelope.type {
            case .unidentifiedSender: (plaintext, sender) = try decryptWithSignalProtocol(envelope: envelope, using: transaction)
            case .closedGroupCiphertext:
                (plaintext, sender) = try decryptWithSharedSenderKeys(envelope: envelope, using: transaction)
                groupPublicKey = envelope.source
            default: throw Error.unknownEnvelopeType
            }
        }
        // Don't process the envelope any further if the sender is blocked
        guard !isBlocked(sender) else { throw Error.senderBlocked }
        // Ignore self sends
        guard sender != userPublicKey else { throw Error.selfSend }
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
            if let typingIndicator = TypingIndicator.fromProto(proto) { return typingIndicator }
            if let closedGroupUpdate = ClosedGroupUpdate.fromProto(proto) { return closedGroupUpdate }
            if let expirationTimerUpdate = ExpirationTimerUpdate.fromProto(proto) { return expirationTimerUpdate }
            if let visibleMessage = VisibleMessage.fromProto(proto) { return visibleMessage }
            return nil
        }()
        if let message = message {
            if isOpenGroupMessage {
                guard message is VisibleMessage else { throw Error.invalidMessage }
            }
            message.sender = sender
            message.recipient = userPublicKey
            message.sentTimestamp = envelope.timestamp
            message.receivedTimestamp = NSDate.millisecondTimestamp()
            message.groupPublicKey = groupPublicKey
            message.openGroupServerMessageID = openGroupMessageServerID
            var isValid = message.isValid
            if message is VisibleMessage && !isValid && proto.dataMessage?.attachments.isEmpty == false {
                isValid = true
            }
            guard isValid else { throw Error.invalidMessage }
            return (message, proto)
        } else {
            throw Error.unknownMessage
        }
    }
}
