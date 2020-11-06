import PromiseKit
import SessionSnodeKit
import SessionUtilities

public enum SendingPipeline {

    public enum Destination {
        case contact(publicKey: String)
        case closedGroup(publicKey: String)
        case openGroup(channel: UInt64, server: String)
    }

    public enum Error : LocalizedError {
        case protoConversionFailed
        case protoSerializationFailed
        case proofOfWorkCalculationFailed

        public var errorDescription: String? {
            switch self {
            case .protoConversionFailed: return "Couldn't convert message to proto."
            case .protoSerializationFailed: return "Couldn't serialize proto."
            case .proofOfWorkCalculationFailed: return "Proof of work calculation failed."
            }
        }
    }

    public static func send(_ message: Message, to destination: Destination) -> Promise<Void> {
        guard let proto = message.toProto() else { return Promise(error: Error.protoConversionFailed) }
        let data: Data
        do {
            data = try proto.serializedData()
        } catch {
            SNLog("Couldn't serialize proto due to error: \(error).")
            return Promise(error: Error.protoSerializationFailed)
        }
        // TODO: Encryption
        // TODO: Validation
        let recipient = ""
        let base64EncodedData = data.base64EncodedString()
        let ttl: UInt64 = 2 * 24 * 60 * 60 * 1000
        guard let (timestamp, nonce) = ProofOfWork.calculate(ttl: ttl, publicKey: recipient, data: base64EncodedData) else {
            SNLog("Proof of work calculation failed.")
            return Promise(error: Error.proofOfWorkCalculationFailed)
        }
        let snodeMessage = SnodeMessage(recipient: recipient, data: base64EncodedData, ttl: ttl, timestamp: timestamp, nonce: nonce)
        let _ = SnodeAPI.sendMessage(snodeMessage)
        return Promise.value(())
    }
}
