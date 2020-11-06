import PromiseKit
import SessionSnodeKit
import SessionUtilities

public enum SendingPipeline {
    private static let ttl: UInt64 = 2 * 24 * 60 * 60 * 1000

    public enum Destination {
        case contact(publicKey: String)
        case closedGroup(publicKey: String)
        case openGroup(channel: UInt64, server: String)
    }

    public enum Error : LocalizedError {
        case invalidMessage
        case protoConversionFailed
        case protoSerializationFailed
        case proofOfWorkCalculationFailed

        public var errorDescription: String? {
            switch self {
            case .invalidMessage: return "Invalid message."
            case .protoConversionFailed: return "Couldn't convert message to proto."
            case .protoSerializationFailed: return "Couldn't serialize proto."
            case .proofOfWorkCalculationFailed: return "Proof of work calculation failed."
            }
        }
    }

    public static func send(_ message: Message, to destination: Destination) -> Promise<Void> {
        guard message.isValidForSending else { return Promise(error: Error.invalidMessage) }
        guard let proto = message.toProto() else { return Promise(error: Error.protoConversionFailed) }
        let plaintext: Data
        do {
            plaintext = try proto.serializedData()
        } catch {
            SNLog("Couldn't serialize proto due to error: \(error).")
            return Promise(error: Error.protoSerializationFailed)
        }
        let ciphertext = plaintext // TODO: Encryption
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
