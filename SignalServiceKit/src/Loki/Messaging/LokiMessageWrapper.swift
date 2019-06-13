
public enum LokiMessageWrapper {
    
    public enum WrappingError : LocalizedError {
        case failedToWrapData
        case failedToWrapMessageInEnvelope
        case failedToWrapEnvelopeInWebSocketMessage
        case failedToUnwrapData
        
        public var errorDescription: String? {
            switch self {
            case .failedToWrapData: return "Failed to wrap data."
            case .failedToWrapMessageInEnvelope: return "Failed to wrap message in envelope."
            case .failedToWrapEnvelopeInWebSocketMessage: return "Failed to wrap envelope in web socket message."
            case .failedToUnwrapData: return "Failed to unwrap data."
            }
        }
    }
    
    /// Wraps `message` in an `SSKProtoEnvelope` and then a `WebSocketProtoWebSocketMessage` to match the desktop application.
    public static func wrap(message: SignalMessage) throws -> Data {
        do {
            let envelope = try createEnvelope(around: message)
            let webSocketMessage = try createWebSocketMessage(around: envelope)
            return try webSocketMessage.serializedData()
        } catch let error {
            throw error as? WrappingError ?? WrappingError.failedToWrapData
        }
    }
    
    private static func createEnvelope(around message: SignalMessage) throws -> SSKProtoEnvelope {
        do {
            let builder = SSKProtoEnvelope.builder(type: message.type, timestamp: message.timestamp)
            builder.setSource(message.senderID)
            builder.setSourceDevice(message.senderDeviceID)
            if let content = try Data(base64Encoded: message.content) {
                builder.setContent(content)
            } else {
                throw WrappingError.failedToWrapMessageInEnvelope
            }
            return try builder.build()
        } catch let error {
            print("[Loki] Failed to wrap message in envelope: \(error).")
            throw WrappingError.failedToWrapMessageInEnvelope
        }
    }
    
    private static func createWebSocketMessage(around envelope: SSKProtoEnvelope) throws -> WebSocketProtoWebSocketMessage {
        do {
            let requestBuilder = WebSocketProtoWebSocketRequestMessage.builder(verb: "PUT", path: "/api/v1/message", requestID: UInt64.random(in: 1..<UInt64.max))
            requestBuilder.setBody(try envelope.serializedData())
            let messageBuilder = WebSocketProtoWebSocketMessage.builder(type: .request)
            messageBuilder.setRequest(try requestBuilder.build())
            return try messageBuilder.build()
        } catch let error {
            print("[Loki] Failed to wrap envelope in web socket message: \(error).")
            throw WrappingError.failedToWrapEnvelopeInWebSocketMessage
        }
    }
    
    /// - Note: `data` shouldn't be base 64 encoded.
    public static func unwrap(data: Data) throws -> SSKProtoEnvelope {
        do {
            let webSocketMessage = try WebSocketProtoWebSocketMessage.parseData(data)
            let envelope = webSocketMessage.request!.body!
            return try SSKProtoEnvelope.parseData(envelope)
        } catch let error {
            print("[Loki] Failed to unwrap data: \(error).")
            throw WrappingError.failedToUnwrapData
        }
    }
}
