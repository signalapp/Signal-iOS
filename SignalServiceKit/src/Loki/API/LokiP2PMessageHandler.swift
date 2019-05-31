
public final class LokiP2PMessageHandler {
    private static let messageReceiver = SSKEnvironment.shared.messageReceiver
    
    // MARK: Initialization
    private init() { }
    
    // MARK: General
    public static func handleReceivedMessage(base64EncodedData: String) {
        guard let data = Data(base64Encoded: base64EncodedData) else {
            Logger.warn("[Loki] Failed to decode data for P2P message.")
            return
        }
        guard let envelope = try? LokiMessageWrapper.unwrap(data: data) else {
            Logger.warn("[Loki] Failed to unwrap data for P2P message.")
            return
        }
        // We need to set the P2P field on the envelope
        let builder = envelope.asBuilder()
        builder.setIsPtpMessage(true)
        // Send it to the message receiver
        do {
            let newEnvelope = try builder.build()
            let envelopeData = try newEnvelope.serializedData()
            messageReceiver.handleReceivedEnvelopeData(envelopeData)
        } catch let error {
            Logger.warn("[Loki] Something went wrong during proto conversion: \(error).")
        }
    }
    
}
