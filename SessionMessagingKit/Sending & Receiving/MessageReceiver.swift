import SessionUtilitiesKit

public enum MessageReceiver {
    private static var lastEncryptionKeyPairRequest: [String:Date] = [:] 

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
        case invalidGroupPublicKey
        case noGroupKeyPair

        public var isRetryable: Bool {
            switch self {
            case .duplicateMessage, .invalidMessage, .unknownMessage, .unknownEnvelopeType,
                .invalidSignature, .noData, .senderBlocked, .noThread, .selfSend, .decryptionFailed: return false
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
            }
        }
    }

    public static func parse(_ data: Data, openGroupMessageServerID: UInt64?, isRetry: Bool = false, using transaction: Any) throws -> (Message, SNProtoContent) {
        let userPublicKey = SNMessagingKitConfiguration.shared.storage.getUserPublicKey()
        let isOpenGroupMessage = (openGroupMessageServerID != nil)
        // Parse the envelope
        let envelope = try SNProtoEnvelope.parseData(data)
        let storage = SNMessagingKitConfiguration.shared.storage
        // Decrypt the contents
        guard let ciphertext = envelope.content else { throw Error.noData }
        var plaintext: Data!
        var sender: String!
        var groupPublicKey: String? = nil
        if isOpenGroupMessage {
            (plaintext, sender) = (envelope.content!, envelope.source!)
        } else {
            switch envelope.type {
            case .sessionMessage:
                guard let userX25519KeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else { throw Error.noUserX25519KeyPair }
                (plaintext, sender) = try decryptWithSessionProtocol(ciphertext: ciphertext, using: userX25519KeyPair)
            case .closedGroupMessage:
                guard let hexEncodedGroupPublicKey = envelope.source, SNMessagingKitConfiguration.shared.storage.isClosedGroup(hexEncodedGroupPublicKey) else { throw Error.invalidGroupPublicKey }
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
                groupPublicKey = envelope.source
                try decrypt()
                /*
                do {
                    try decrypt()
                } catch {
                    do {
                        let now = Date()
                        // Don't spam encryption key pair requests
                        let shouldRequestEncryptionKeyPair = given(lastEncryptionKeyPairRequest[groupPublicKey!]) { now.timeIntervalSince($0) > 30 } ?? true
                        if shouldRequestEncryptionKeyPair {
                            try MessageSender.requestEncryptionKeyPair(for: groupPublicKey!, using: transaction as! YapDatabaseReadWriteTransaction)
                            lastEncryptionKeyPairRequest[groupPublicKey!] = now
                        }
                    }
                    throw error // Throw the * decryption * error and not the error generated by requestEncryptionKeyPair (if it generated one)
                }
                 */
            default: throw Error.unknownEnvelopeType
            }
        }
        // Don't process the envelope any further if the sender is blocked
        guard !isBlocked(sender) else { throw Error.senderBlocked }
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
            if let closedGroupControlMessage = ClosedGroupControlMessage.fromProto(proto) { return closedGroupControlMessage }
            if let dataExtractionNotification = DataExtractionNotification.fromProto(proto) { return dataExtractionNotification }
            if let expirationTimerUpdate = ExpirationTimerUpdate.fromProto(proto) { return expirationTimerUpdate }
            if let configurationMessage = ConfigurationMessage.fromProto(proto) { return configurationMessage }
            if let unsendRequest = UnsendRequest.fromProto(proto) { return unsendRequest }
            if let messageRequestResponse = MessageRequestResponse.fromProto(proto) { return messageRequestResponse }
            if let visibleMessage = VisibleMessage.fromProto(proto) { return visibleMessage }
            return nil
        }()
        if let message = message {
            // Ignore self sends if needed
            if !message.isSelfSendValid {
                guard sender != userPublicKey else { throw Error.selfSend }
            }
            // Guard against control messages in open groups
            if isOpenGroupMessage {
                guard message is VisibleMessage else { throw Error.invalidMessage }
            }
            // Finish parsing
            message.sender = sender
            message.recipient = userPublicKey
            message.sentTimestamp = envelope.timestamp
            message.receivedTimestamp = NSDate.millisecondTimestamp()
            if isOpenGroupMessage {
                message.openGroupServerTimestamp = envelope.serverTimestamp
            }
            message.groupPublicKey = groupPublicKey
            message.openGroupServerMessageID = openGroupMessageServerID
            // Validate
            var isValid = message.isValid
            if message is VisibleMessage && !isValid && proto.dataMessage?.attachments.isEmpty == false {
                isValid = true
            }
            guard isValid else {
                throw Error.invalidMessage
            }
            // If the message failed to process the first time around we retry it later (if the error is retryable). In this case the timestamp
            // will already be in the database but we don't want to treat the message as a duplicate. The isRetry flag is a simple workaround
            // for this issue.
            if let message = message as? ClosedGroupControlMessage, case .new = message.kind {
                // Allow duplicates in this case to avoid the following situation:
                // • The app performed a background poll or received a push notification
                // • This method was invoked and the received message timestamps table was updated
                // • Processing wasn't finished
                // • The user doesn't see the new closed group
            } else {
                guard !Set(storage.getReceivedMessageTimestamps(using: transaction)).contains(envelope.timestamp) || isRetry else { throw Error.duplicateMessage }
                storage.addReceivedMessageTimestamp(envelope.timestamp, using: transaction)
            }
            // Return
            return (message, proto)
        } else {
            throw Error.unknownMessage
        }
    }
}
