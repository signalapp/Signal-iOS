import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

@objc(SNMessageSender)
public final class MessageSender : NSObject {

    // MARK: Error
    public enum Error : LocalizedError {
        case invalidMessage
        case protoConversionFailed
        case proofOfWorkCalculationFailed
        case noUserPublicKey
        // Closed groups
        case noThread
        case noPrivateKey
        case invalidClosedGroupUpdate

        internal var isRetryable: Bool {
            switch self {
            case .invalidMessage, .protoConversionFailed, .proofOfWorkCalculationFailed, .invalidClosedGroupUpdate: return false
            default: return true
            }
        }
        
        public var errorDescription: String? {
            switch self {
            case .invalidMessage: return "Invalid message."
            case .protoConversionFailed: return "Couldn't convert message to proto."
            case .proofOfWorkCalculationFailed: return "Proof of work calculation failed."
            case .noUserPublicKey: return "Couldn't find user key pair."
            // Closed groups
            case .noThread: return "Couldn't find a thread associated with the given group public key."
            case .noPrivateKey: return "Couldn't find a private key associated with the given group public key."
            case .invalidClosedGroupUpdate: return "Invalid group update."
            }
        }
    }

    // MARK: Initialization
    private override init() { }

    public static let shared = MessageSender() // FIXME: Remove once requestSenderKey is static

    // MARK: Convenience
    public static func send(_ message: Message, to destination: Message.Destination, using transaction: Any) -> Promise<Void> {
        switch destination {
        case .contact(_), .closedGroup(_): return sendToSnodeDestination(destination, message: message, using: transaction)
        case .openGroup(_, _): return sendToOpenGroupDestination(destination, message: message, using: transaction)
        }
    }

    // MARK: One-on-One Chats & Closed Groups
    internal static func sendToSnodeDestination(_ destination: Message.Destination, message: Message, using transaction: Any) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        let storage = Configuration.shared.storage
        if message.sentTimestamp == nil { // Visible messages will already have their sent timestamp set
            message.sentTimestamp = NSDate.millisecondTimestamp()
        }
        message.sender = storage.getUserPublicKey()
        switch destination {
        case .contact(let publicKey): message.recipient = publicKey
        case .closedGroup(let groupPublicKey): message.recipient = groupPublicKey
        case .openGroup(_, _): preconditionFailure()
        }
        // Set the failure handler (for precondition failure handling)
        let _ = promise.catch(on: DispatchQueue.main) { error in
            storage.withAsync({ transaction in
                MessageSender.handleFailedMessageSend(message, with: error, using: transaction)
            }, completion: { })
            if case .contact(_) = destination, message is VisibleMessage {
                NotificationCenter.default.post(name: .messageSendingFailed, object: NSNumber(value: message.sentTimestamp!))
            }
        }
        // Validate the message
        guard message.isValid else { seal.reject(Error.invalidMessage); return promise }
        // Attach the user's profile if needed
        if let message = message as? VisibleMessage {
            let displayName = storage.getUserDisplayName()!
            if let profileKey = storage.getUserProfileKey(), let profilePictureURL = storage.getUserProfilePictureURL() {
                message.profile = VisibleMessage.Profile(displayName: displayName, profileKey: profileKey, profilePictureURL: profilePictureURL)
            } else {
                message.profile = VisibleMessage.Profile(displayName: displayName)
            }
        }
        // Convert it to protobuf
        guard let proto = message.toProto() else { seal.reject(Error.protoConversionFailed); return promise }
        // Serialize the protobuf
        let plaintext: Data
        do {
            plaintext = try proto.serializedData()
        } catch {
            SNLog("Couldn't serialize proto due to error: \(error).")
            seal.reject(error)
            return promise
        }
        // Encrypt the serialized protobuf
        if case .contact(_) = destination, message is VisibleMessage {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .encryptingMessage, object: NSNumber(value: message.sentTimestamp!))
            }
        }
        let ciphertext: Data
        do {
            switch destination {
            case .contact(let publicKey): ciphertext = try encryptWithSignalProtocol(plaintext, associatedWith: message, for: publicKey, using: transaction)
            case .closedGroup(let groupPublicKey): ciphertext = try encryptWithSharedSenderKeys(plaintext, for: groupPublicKey, using: transaction)
            case .openGroup(_, _): preconditionFailure()
            }
        } catch {
            SNLog("Couldn't encrypt message for destination: \(destination) due to error: \(error).")
            seal.reject(error)
            return promise
        }
        // Wrap the result
        let kind: SNProtoEnvelope.SNProtoEnvelopeType
        let senderPublicKey: String
        switch destination {
        case .contact(_):
            kind = .unidentifiedSender
            senderPublicKey = ""
        case .closedGroup(let groupPublicKey):
            kind = .closedGroupCiphertext
            senderPublicKey = groupPublicKey
        case .openGroup(_, _): preconditionFailure()
        }
        let wrappedMessage: Data
        do {
            wrappedMessage = try MessageWrapper.wrap(type: kind, timestamp: message.sentTimestamp!,
                senderPublicKey: senderPublicKey, base64EncodedContent: ciphertext.base64EncodedString())
        } catch {
            SNLog("Couldn't wrap message due to error: \(error).")
            seal.reject(error)
            return promise
        }
        // Calculate proof of work
        if case .contact(_) = destination, message is VisibleMessage {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .calculatingMessagePoW, object: NSNumber(value: message.sentTimestamp!))
            }
        }
        let recipient = message.recipient!
        let base64EncodedData = wrappedMessage.base64EncodedString()
        guard let (timestamp, nonce) = ProofOfWork.calculate(ttl: type(of: message).ttl, publicKey: recipient, data: base64EncodedData) else {
            SNLog("Proof of work calculation failed.")
            seal.reject(Error.proofOfWorkCalculationFailed)
            return promise
        }
        // Send the result
        if case .contact(_) = destination, message is VisibleMessage {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .messageSending, object: NSNumber(value: message.sentTimestamp!))
            }
        }
        let snodeMessage = SnodeMessage(recipient: recipient, data: base64EncodedData, ttl: type(of: message).ttl, timestamp: timestamp, nonce: nonce)
        SnodeAPI.sendMessage(snodeMessage).done(on: DispatchQueue.global(qos: .userInitiated)) { promises in
            var isSuccess = false
            let promiseCount = promises.count
            var errorCount = 0
            promises.forEach {
                let _ = $0.done(on: DispatchQueue.global(qos: .userInitiated)) { _ in
                    guard !isSuccess else { return } // Succeed as soon as the first promise succeeds
                    isSuccess = true
                    seal.fulfill(())
                }
                $0.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
                    errorCount += 1
                    guard errorCount == promiseCount else { return } // Only error out if all promises failed
                    seal.reject(error)
                }
            }
        }.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
            SNLog("Couldn't send message due to error: \(error).")
            seal.reject(error)
        }
        // Handle completion
        let _ = promise.done(on: DispatchQueue.main) {
            storage.withAsync({ transaction in
                MessageSender.handleSuccessfulMessageSend(message, using: transaction)
            }, completion: { })
            if case .contact(_) = destination, message is VisibleMessage {
                NotificationCenter.default.post(name: .messageSent, object: NSNumber(value: message.sentTimestamp!))
            }
            if message is VisibleMessage {
                let notifyPNServerJob = NotifyPNServerJob(message: snodeMessage)
                storage.withAsync({ transaction in
                    JobQueue.shared.add(notifyPNServerJob, using: transaction)
                }, completion: { })
            }
        }
        // Return
        return promise
    }

    // MARK: Open Groups
    internal static func sendToOpenGroupDestination(_ destination: Message.Destination, message: Message, using transaction: Any) -> Promise<Void> {
        let (promise, seal) = Promise<Void>.pending()
        let storage = Configuration.shared.storage
        message.sentTimestamp = NSDate.millisecondTimestamp()
        switch destination {
        case .contact(_): preconditionFailure()
        case .closedGroup(_): preconditionFailure()
        case .openGroup(let channel, let server): message.recipient = "\(server).\(channel)"
        }
        // Set the failure handler (for precondition failure handling)
        let _ = promise.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
            storage.withAsync({ transaction in
                MessageSender.handleFailedMessageSend(message, with: error, using: transaction)
            }, completion: { })
        }
        // Validate the message
        guard message.isValid else { seal.reject(Error.invalidMessage); return promise }
        // Convert the message to an open group message
        let (channel, server) = { () -> (UInt64, String) in
            switch destination {
            case .openGroup(let channel, let server): return (channel, server)
            default: preconditionFailure()
            }
        }()
        guard let message = message as? VisibleMessage,
            let openGroupMessage = OpenGroupMessage.from(message, for: server) else { seal.reject(Error.invalidMessage); return promise }
        // Send the result
        OpenGroupAPI.sendMessage(openGroupMessage, to: channel, on: server).done(on: DispatchQueue.global(qos: .userInitiated)) { openGroupMessage in
            message.openGroupServerMessageID = openGroupMessage.serverID
            seal.fulfill(())
        }.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
            seal.reject(error)
        }
        // Handle completion
        let _ = promise.done(on: DispatchQueue.global(qos: .userInitiated)) {
            storage.withAsync({ transaction in
                MessageSender.handleSuccessfulMessageSend(message, using: transaction)
            }, completion: { })
        }
        // Return
        return promise
    }
}
