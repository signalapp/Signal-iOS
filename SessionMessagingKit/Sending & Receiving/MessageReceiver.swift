import SessionUtilitiesKit

public enum MessageReceiver {

    public enum Error : LocalizedError {
        case duplicateMessage
        case invalidMessage
        case unknownMessage
        case unknownEnvelopeType
        case noUserX25519KeyPair
        case noUserED25519KeyPair
        case invalidSignature
        case noData
        case senderBlocked
        case noThread
        case selfSend
        case decryptionFailed
        // Shared sender keys
        case invalidGroupPublicKey
        case noGroupKeyPair
        case sharedSecretGenerationFailed

        public var isRetryable: Bool {
            switch self {
            case .duplicateMessage, .invalidMessage, .unknownMessage, .unknownEnvelopeType, .invalidSignature, .noData, .senderBlocked, .selfSend, .decryptionFailed: return false
            default: return true
            }
        }

        public var errorDescription: String? {
            switch self {
            case .duplicateMessage: return "Duplicate message."
            case .invalidMessage: return "Invalid message."
            case .unknownMessage: return "Unknown message type."
            case .unknownEnvelopeType: return "Unknown envelope type."
            case .noUserX25519KeyPair: return "Couldn't find user X25519 key pair."
            case .noUserED25519KeyPair: return "Couldn't find user ED25519 key pair."
            case .invalidSignature: return "Invalid message signature."
            case .noData: return "Received an empty envelope."
            case .senderBlocked: return "Received a message from a blocked user."
            case .noThread: return "Couldn't find thread for message."
            case .selfSend: return "Message addressed at self."
            case .decryptionFailed: return "Decryption failed."
            // Shared sender keys
            case .invalidGroupPublicKey: return "Invalid group public key."
            case .noGroupKeyPair: return "Missing group key pair."
            case .sharedSecretGenerationFailed: return "Couldn't generate a shared secret."
            }
        }
    }

    public static func parse(_ data: Data, openGroupMessageServerID: UInt64?, using transaction: Any) throws -> (Message, SNProtoContent) {
        let userPublicKey = SNMessagingKitConfiguration.shared.storage.getUserPublicKey()
        let isOpenGroupMessage = (openGroupMessageServerID != nil)
        // Parse the envelope
        let envelope = try SNProtoEnvelope.parseData(data)
        let storage = SNMessagingKitConfiguration.shared.storage
        guard !Set(storage.getReceivedMessageTimestamps(using: transaction)).contains(envelope.timestamp) else { throw Error.duplicateMessage }
        storage.addReceivedMessageTimestamp(envelope.timestamp, using: transaction)
        // Decrypt the contents
        guard let ciphertext = envelope.content else { throw Error.noData }
        var plaintext: Data!
        var sender: String!
        var groupPublicKey: String? = nil
        if isOpenGroupMessage {
            (plaintext, sender) = (envelope.content!, envelope.source!)
        } else {
            switch envelope.type {
            case .unidentifiedSender:
                guard let userX25519KeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else { throw Error.noUserX25519KeyPair }
                (plaintext, sender) = try decryptWithSessionProtocol(ciphertext: ciphertext, using: userX25519KeyPair)
            case .closedGroupCiphertext:
                guard let hexEncodedGroupPublicKey = envelope.source, SNMessagingKitConfiguration.shared.storage.isClosedGroup(hexEncodedGroupPublicKey) else { throw Error.invalidGroupPublicKey }
                do {
                    var encryptionKeyPairs = Storage.shared.getClosedGroupEncryptionKeyPairs(for: hexEncodedGroupPublicKey)
                    guard !encryptionKeyPairs.isEmpty else { throw Error.noGroupKeyPair }
                    // Loop through all known group key pairs in reverse order (i.e. try the latest key pair first (which'll more than
                    // likely be the one we want) but try older ones in case that didn't work)
                    var encryptionKeyPair = encryptionKeyPairs.removeLast()
                    func decrypt() throws {
                        do {
                            (plaintext, sender) = try decryptWithSessionProtocol(ciphertext: ciphertext, using: encryptionKeyPair)
                        } catch {
                            if !encryptionKeyPairs.isEmpty {
                                encryptionKeyPair = encryptionKeyPairs.removeLast()
                                try decrypt()
                            } else {
                                throw error
                            }
                        }
                    }
                    try decrypt()
                } catch {
                    // Fall back on the V1 method
                    guard let privateKey = SNMessagingKitConfiguration.shared.storage.getClosedGroupPrivateKey(for: hexEncodedGroupPublicKey) else { throw Error.noGroupKeyPair }
                    let keyPair = try ECKeyPair(publicKeyData: Data(hex: hexEncodedGroupPublicKey.removing05PrefixIfNeeded()), privateKeyData: Data(hex: privateKey))
                    (plaintext, sender) = try decryptWithSessionProtocol(ciphertext: ciphertext, using: keyPair)
                }
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
            if let closedGroupUpdate = ClosedGroupUpdateV2.fromProto(proto) { return closedGroupUpdate }
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
