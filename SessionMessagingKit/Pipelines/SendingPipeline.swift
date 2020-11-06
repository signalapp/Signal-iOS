import PromiseKit
import SessionSnodeKit
import SessionUtilities

public enum SendingPipeline {
    private static let ttl: UInt64 = 2 * 24 * 60 * 60 * 1000

    public enum Destination {
        case contact(publicKey: String)
        case closedGroup(groupPublicKey: String)
        case openGroup(channel: UInt64, server: String)
    }

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

    public static func send(_ message: Message, to destination: Destination, using transaction: Any) -> Promise<Void> {
        guard message.isValid else { return Promise(error: Error.invalidMessage) }
        guard let proto = message.toProto() else { return Promise(error: Error.protoConversionFailed) }
        let plaintext: Data
        do {
            plaintext = try proto.serializedData()
        } catch {
            SNLog("Couldn't serialize proto due to error: \(error).")
            return Promise(error: error)
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
        let recipient = message.recipient!
        let base64EncodedData = ciphertext.base64EncodedString()
        guard let (timestamp, nonce) = ProofOfWork.calculate(ttl: ttl, publicKey: recipient, data: base64EncodedData) else {
            SNLog("Proof of work calculation failed.")
            return Promise(error: Error.proofOfWorkCalculationFailed)
        }
        let snodeMessage = SnodeMessage(recipient: recipient, data: base64EncodedData, ttl: ttl, timestamp: timestamp, nonce: nonce)
        let _ = SnodeAPI.sendMessage(snodeMessage)
        return Promise.value(())
    }
}
