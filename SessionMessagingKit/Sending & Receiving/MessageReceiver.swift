import SessionUtilitiesKit

// TODO:
// • Threads don't show up on the first message; only on the second.
// • Profile pictures aren't showing up.
// • Check that message expiration works.
// • Open group messages (sync messages).

internal enum MessageReceiver {

    internal enum Error : LocalizedError {
        case invalidMessage
        case unknownMessage
        case unknownEnvelopeType
        case noUserPublicKey
        case noData
        case senderBlocked
        case noThread
        // Shared sender keys
        case invalidGroupPublicKey
        case noGroupPrivateKey
        case sharedSecretGenerationFailed
        case selfSend

        internal var isRetryable: Bool {
            switch self {
            case .invalidMessage, .unknownMessage, .unknownEnvelopeType, .noData, .senderBlocked, .selfSend: return false
            default: return true
            }
        }

        internal var errorDescription: String? {
            switch self {
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

    internal static func parse(_ data: Data, messageServerID: UInt64?, using transaction: Any) throws -> Message {
        // Parse the envelope
        let envelope = try SNProtoEnvelope.parseData(data)
        // Decrypt the contents
        let plaintext: Data
        let sender: String
        var groupPublicKey: String? = nil
        switch envelope.type {
        case .unidentifiedSender: (plaintext, sender) = try decryptWithSignalProtocol(envelope: envelope, using: transaction)
        case .closedGroupCiphertext:
            (plaintext, sender) = try decryptWithSharedSenderKeys(envelope: envelope, using: transaction)
            groupPublicKey = envelope.source
        default: throw Error.unknownEnvelopeType
        }
        // Don't process the envelope any further if the sender is blocked
        guard !Configuration.shared.messageReceiverDelegate.isBlocked(sender) else { throw Error.senderBlocked }
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
            if let nullMessage = NullMessage.fromProto(proto) { return nullMessage }
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
            message.groupPublicKey = groupPublicKey
            message.openGroupServerMessageID = messageServerID
            guard message.isValid else { throw Error.invalidMessage }
            return message
        } else {
            throw Error.unknownMessage
        }
    }

    internal static func handle(_ message: Message, using transaction: Any) throws {
        switch message {
        case let message as ReadReceipt: handleReadReceipt(message, using: transaction)
        case let message as SessionRequest: handleSessionRequest(message, using: transaction)
        case let message as NullMessage: handleNullMessage(message, using: transaction)
        case let message as TypingIndicator: handleTypingIndicator(message, using: transaction)
        case let message as ClosedGroupUpdate: handleClosedGroupUpdate(message, using: transaction)
        case let message as ExpirationTimerUpdate: handleExpirationTimerUpdate(message, using: transaction)
        case let message as VisibleMessage: try handleVisibleMessage(message, using: transaction)
        default: fatalError()
        }
    }

    private static func handleReadReceipt(_ message: ReadReceipt, using transaction: Any) {
        Configuration.shared.messageReceiverDelegate.markMessagesAsRead(message.timestamps!, from: message.sender!, at: message.receivedTimestamp!)
    }

    private static func handleSessionRequest(_ message: SessionRequest, using transaction: Any) {
        // We might not need this anymore
    }

    private static func handleNullMessage(_ message: NullMessage, using transaction: Any) {
        // We might not need this anymore
    }

    private static func handleTypingIndicator(_ message: TypingIndicator, using transaction: Any) {
        let delegate = Configuration.shared.messageReceiverDelegate
        switch message.kind! {
        case .started: delegate.showTypingIndicatorIfNeeded(for: message.sender!)
        case .stopped: delegate.hideTypingIndicatorIfNeeded(for: message.sender!)
        }
    }

    private static func handleClosedGroupUpdate(_ message: ClosedGroupUpdate, using transaction: Any) {
        let delegate = Configuration.shared.messageReceiverDelegate
        switch message.kind! {
        case .new: delegate.handleNewGroup(message, using: transaction)
        case .info: delegate.handleGroupUpdate(message, using: transaction)
        case .senderKeyRequest: delegate.handleSenderKeyRequest(message, using: transaction)
        case .senderKey: delegate.handleSenderKey(message, using: transaction)
        }
    }

    private static func handleExpirationTimerUpdate(_ message: ExpirationTimerUpdate, using transaction: Any) {
        let delegate = Configuration.shared.messageReceiverDelegate
        if message.duration! > 0 {
            delegate.setExpirationTimer(to: message.duration!, for: message.sender!, groupPublicKey: message.groupPublicKey, using: transaction)
        } else {
            delegate.disableExpirationTimer(for: message.sender!, groupPublicKey: message.groupPublicKey, using: transaction)
        }
    }

    private static func handleVisibleMessage(_ message: VisibleMessage, using transaction: Any) throws {
        let delegate = Configuration.shared.messageReceiverDelegate
        // Update profile if needed
        if let profile = message.profile {
            delegate.updateProfile(for: message.sender!, from: profile, using: transaction)
        }
        // Persist the message
        guard let (threadID, tsIncomingMessage) = Configuration.shared.storage.persist(message, groupPublicKey: message.groupPublicKey, using: transaction) else { throw Error.noThread }
        message.threadID = threadID
        // Cancel any typing indicators
        delegate.cancelTypingIndicatorsIfNeeded(for: message.sender!)
        // Notify the user if needed
        delegate.notifyUserIfNeeded(for: tsIncomingMessage, threadID: threadID)
    }
}
