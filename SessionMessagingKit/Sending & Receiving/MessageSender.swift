import PromiseKit
import SessionSnodeKit
import SessionUtilities

// TODO: Open group encryption
// TODO: Signal protocol encryption

internal enum MessageSender {

    internal enum Error : LocalizedError {
        case invalidMessage
        case protoConversionFailed
        case proofOfWorkCalculationFailed
        case noUserPublicKey

        internal var errorDescription: String? {
            switch self {
            case .invalidMessage: return "Invalid message."
            case .protoConversionFailed: return "Couldn't convert message to proto."
            case .proofOfWorkCalculationFailed: return "Proof of work calculation failed."
            case .noUserPublicKey: return "Couldn't find user key pair."
            }
        }
    }

    internal static func send(_ message: Message, to destination: Message.Destination, using transaction: Any) -> Promise<Void> {
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
            case .contact(let publicKey): ciphertext = try encryptWithSignalProtocol(plaintext, for: publicKey, using: transaction)
            case .closedGroup(let groupPublicKey): ciphertext = try encryptWithSharedSenderKeys(plaintext, for: groupPublicKey, using: transaction)
            case .openGroup(_, _): fatalError("Not implemented.")
            }
        } catch {
            SNLog("Couldn't encrypt message for destination: \(destination) due to error: \(error).")
            return Promise(error: error)
        }
        // Calculate proof of work
        if case .contact(_) = destination {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .calculatingMessagePoW, object: NSNumber(value: message.sentTimestamp!))
            }
        }
        let recipient = message.recipient!
        let base64EncodedData = ciphertext.base64EncodedString()
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
            Configuration.shared.storage.persist(notifyPNServerJob)
            notifyPNServerJob.execute()
        }
        let _ = promise.catch(on: DispatchQueue.main) { _ in
            if case .contact(_) = destination {
                NotificationCenter.default.post(name: .messageSendingFailed, object: NSNumber(value: message.sentTimestamp!))
            }
        }
        return promise
    }
}
