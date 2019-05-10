
extension LokiAPI {
    
    enum WrappingError : LocalizedError {
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
    
    /// Wrap a message for sending to the storage server.
    /// This will wrap the message in an `SSKProtoEnvelope` and then a `WebSocketProtoWebSocketMessage` to match the desktop application.
    ///
    /// - Parameters:
    ///   - message: The Signal message.
    ///   - timestamp: The original message timestamp (`TSOutgoingMessage.timestamp`).
    /// - Returns: The wrapped message data.
    /// - Throws: A `WrappingError` if something went wrong.
    static func wrap(message: SignalMessage, timestamp: UInt64) throws -> Data {
        do {
            let envelope = try createEnvelope(around: message, timestamp: timestamp)
            let webSocketMessage = try createWebSocketMessage(around: envelope)
            return try webSocketMessage.serializedData()
        } catch let error {
            throw error as? WrappingError ?? WrappingError.failedToWrapData
        }
    }
    
    /// Unwrap data sent by the storage server.
    ///
    /// - Parameter data: The data from the storage server (not base 64 encoded).
    /// - Returns: An `SSKProtoEnvelope` object.
    /// - Throws: A `WrappingError` if something went wrong.
    static func unwrap(data: Data) throws -> SSKProtoEnvelope {
        do {
            let webSocketMessage = try WebSocketProtoWebSocketMessage.parseData(data)
            let envelope = webSocketMessage.request!.body!
            return try SSKProtoEnvelope.parseData(envelope)
        } catch let error {
            owsFailDebug("[Loki API] Failed to unwrap data: \(error).")
            throw WrappingError.failedToUnwrapData
        }
    }
    
    /// Wrap an `SSKProtoEnvelope` in a `WebSocketProtoWebSocketMessage`.
    private static func createWebSocketMessage(around envelope: SSKProtoEnvelope) throws -> WebSocketProtoWebSocketMessage {
        do {
            let requestBuilder = WebSocketProtoWebSocketRequestMessage.builder(verb: "PUT", path: "/api/v1/message", requestID: UInt64.random(in: 1..<UInt64.max))
            requestBuilder.setBody(try envelope.serializedData())
            let messageBuilder = WebSocketProtoWebSocketMessage.builder(type: .request)
            messageBuilder.setRequest(try requestBuilder.build())
            return try messageBuilder.build()
        } catch let error {
            owsFailDebug("[Loki API] - Failed to wrap envelope in web socket message: \(error).")
            throw WrappingError.failedToWrapEnvelopeInWebSocketMessage
        }
    }
    
    /// Wrap a `SignalMessage` in an `SSKProtoEnvelope`.
    private static func createEnvelope(around signalMessage: SignalMessage, timestamp: UInt64) throws -> SSKProtoEnvelope {
        guard let keyPair = SSKEnvironment.shared.identityManager.identityKeyPair() else {
            owsFailDebug("[Loki API] - Failed to wrap message in envelope: identityManager.identityKeyPair() is invalid.")
            throw WrappingError.failedToWrapMessageInEnvelope
        }
        do {
            let hexEncodedPublicKey = keyPair.hexEncodedPublicKey
            let parameters = ParamParser(dictionary: signalMessage)
            let rawType: Int32 = try parameters.required(key: "type")
            guard let type: SSKProtoEnvelope.SSKProtoEnvelopeType = SSKProtoEnvelope.SSKProtoEnvelopeType(rawValue: rawType) else {
                Logger.error("Invalid envelope type: \(rawType).")
                throw ParamParser.ParseError.invalidFormat("type")
            }
            let builder = SSKProtoEnvelope.builder(type: type, timestamp: timestamp)
            builder.setSource(hexEncodedPublicKey)
            builder.setSourceDevice(OWSDevicePrimaryDeviceId)
            if let content = try parameters.optionalBase64EncodedData(key: "content") {
                builder.setContent(content)
            }
            return try builder.build()
        } catch let error {
            owsFailDebug("[Loki API] Failed to wrap message in envelope: \(error).")
            throw WrappingError.failedToWrapMessageInEnvelope
        }
    }
}
