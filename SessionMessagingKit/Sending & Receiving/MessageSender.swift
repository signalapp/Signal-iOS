import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

public enum MessageSender {

    public enum Error : LocalizedError {
        case invalidMessage
        case protoConversionFailed
        case proofOfWorkCalculationFailed
        case noUserPublicKey

        public var errorDescription: String? {
            switch self {
            case .invalidMessage: return "Invalid message."
            case .protoConversionFailed: return "Couldn't convert message to proto."
            case .proofOfWorkCalculationFailed: return "Proof of work calculation failed."
            case .noUserPublicKey: return "Couldn't find user key pair."
            }
        }
    }

    internal static func send(_ message: Message, to destination: Message.Destination, using transaction: Any) -> Promise<Void> {
        switch destination {
        case .contact(_), .closedGroup(_): return sendToSnodeDestination(destination, message: message, using: transaction)
        case .openGroup(_, _): return sendToOpenGroupDestination(destination, message: message, using: transaction)
        }
    }

    internal static func sendToSnodeDestination(_ destination: Message.Destination, message: Message, using transaction: Any) -> Promise<Void> {
        message.sentTimestamp = NSDate.millisecondTimestamp()
        switch destination {
        case .contact(let publicKey): message.recipient = publicKey
        case .closedGroup(let groupPublicKey): message.recipient = groupPublicKey
        case .openGroup(_, _): preconditionFailure()
        }
        // Validate the message
        guard message.isValid else { return Promise(error: Error.invalidMessage) }
        // Convert it to protobuf
        guard let proto = message.toProto() else { return Promise(error: Error.protoConversionFailed) }
        // Serialize the protobuf
        let plaintext: Data
        do {
            plaintext = try proto.serializedData()
        } catch {
            SNLog("Couldn't serialize proto due to error: \(error).")
            return Promise(error: error)
        }
        // Encrypt the serialized protobuf
        if case .contact(_) = destination {
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
            return Promise(error: error)
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
            return Promise(error: error)
        }
        // Calculate proof of work
        if case .contact(_) = destination {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .calculatingMessagePoW, object: NSNumber(value: message.sentTimestamp!))
            }
        }
        let recipient = message.recipient!
        let base64EncodedData = wrappedMessage.base64EncodedString()
        guard let (timestamp, nonce) = ProofOfWork.calculate(ttl: type(of: message).ttl, publicKey: recipient, data: base64EncodedData) else {
            SNLog("Proof of work calculation failed.")
            return Promise(error: Error.proofOfWorkCalculationFailed)
        }
        // Send the result
        if case .contact(_) = destination {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .messageSending, object: NSNumber(value: message.sentTimestamp!))
            }
        }
        let snodeMessage = SnodeMessage(recipient: recipient, data: base64EncodedData, ttl: type(of: message).ttl, timestamp: timestamp, nonce: nonce)
        let (promise, seal) = Promise<Void>.pending()
        SnodeAPI.sendMessage(snodeMessage).done(on: Threading.workQueue) { promises in
            var isSuccess = false
            let promiseCount = promises.count
            var errorCount = 0
            promises.forEach {
                let _ = $0.done(on: Threading.workQueue) { _ in
                    guard !isSuccess else { return } // Succeed as soon as the first promise succeeds
                    isSuccess = true
                    seal.fulfill(())
                }
                $0.catch(on: Threading.workQueue) { error in
                    errorCount += 1
                    guard errorCount == promiseCount else { return } // Only error out if all promises failed
                    seal.reject(error)
                }
            }
        }.catch(on: Threading.workQueue) { error in
            SNLog("Couldn't send message due to error: \(error).")
            seal.reject(error)
        }
        let _ = promise.done(on: DispatchQueue.main) {
            if case .contact(_) = destination {
                NotificationCenter.default.post(name: .messageSent, object: NSNumber(value: message.sentTimestamp!))
            }
            let notifyPNServerJob = NotifyPNServerJob(message: snodeMessage)
            Configuration.shared.storage.with { transaction in
                JobQueue.shared.add(notifyPNServerJob, using: transaction)
            }
        }
        let _ = promise.catch(on: DispatchQueue.main) { _ in
            if case .contact(_) = destination {
                NotificationCenter.default.post(name: .messageSendingFailed, object: NSNumber(value: message.sentTimestamp!))
            }
        }
        return promise
    }

    internal static func sendToOpenGroupDestination(_ destination: Message.Destination, message: Message, using transaction: Any) -> Promise<Void> {
        guard message.isValid else { return Promise(error: Error.invalidMessage) }
        let (channel, server) = { () -> (UInt64, String) in
            switch destination {
            case .openGroup(let channel, let server): return (channel, server)
            default: preconditionFailure()
            }
        }()
        guard let message = message as? VisibleMessage,
            let openGroupMessage = OpenGroupMessage.from(message, for: server) else { return Promise(error: Error.invalidMessage) }
        let promise = OpenGroupAPI.sendMessage(openGroupMessage, to: channel, on: server)
        let _ = promise.done(on: DispatchQueue.global(qos: .userInitiated)) { _ in
            // TODO: Save server message ID
        }
        promise.catch(on: DispatchQueue.global(qos: .userInitiated)) { _ in
            // TODO: Handle failure
        }
        return promise.map { _ in }
    }
}
