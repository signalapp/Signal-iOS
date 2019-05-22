
public class LokiP2PMessageHandler {
    public static let shared = LokiP2PMessageHandler()

    private var messageReceiver: OWSMessageReceiver {
        return SSKEnvironment.shared.messageReceiver
    }
    
    private init() {}
    
    public func handleReceivedMessage(base64EncodedData: String) {
        guard let data = Data(base64Encoded: base64EncodedData) else {
            Logger.warn("[LokiP2PMessageHandler] Failed to decode p2p message data")
            return
        }
        
        guard let envelope = try? LokiMessageWrapper.unwrap(data: data) else {
            Logger.warn("[LokiP2PMessageHandler] Failed to unwrap p2p data")
            return
        }
        
        // We need to set the p2p field on the envelope
        let builder = envelope.asBuilder()
        builder.setIsPtpMessage(true)
        
        // Send it to message receiver
        do {
            let newEnvelope = try builder.build()
            let envelopeData = try newEnvelope.serializedData()
            messageReceiver.handleReceivedEnvelopeData(envelopeData)
        } catch let error {
            Logger.warn("[LokiP2PMessageHandler] Something went wrong while converting proto: \(error)")
            owsFailDebug("Failed to build envelope")
        }
    }
    
}
