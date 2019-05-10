/// A helper util class for the api
extension LokiAPI {
    
    // Custom erros for us
    enum WrappingError : LocalizedError {
        case failedToWrapData
        case failedToWrapEnvelope
        case failedToWrapWebSocket
        case failedToUnwrapData
        
        public var errorDescription: String? {
            switch self {
            case .failedToWrapData: return "Failed to wrap data"
            case .failedToWrapEnvelope: return NSLocalizedString("Failed to wrap data in an Envelope", comment: "")
            case .failedToWrapWebSocket: return NSLocalizedString("Failed to wrap data in an WebSocket", comment: "")
            case .failedToUnwrapData: return "Failed to unwrap data"
            }
        }
    }
    
    /// Wrap a message for sending to the storage server.
    /// This will wrap the message in an Envelope and then a WebSocket to match the desktop application.
    ///
    /// - Parameters:
    ///   - message: The signal message
    ///   - timestamp: The original message timestamp (TSOutgoingMessage.timestamp)
    /// - Returns: The wrapped message data
    /// - Throws: WrappingError if something went wrong
    static func wrap(message: SignalMessage, timestamp: UInt64) throws -> Data {
        do {
            let envelope = try buildEnvelope(from: message, timestamp: timestamp)
            let websocket = try buildWebSocket(from: envelope)
            return try websocket.serializedData()
        } catch let error {
            if !(error is WrappingError) {
                throw WrappingError.failedToWrapData
            } else {
                throw error
            }
        }

    }
    
    /// Unwrap data from the storage server
    ///
    /// - Parameter data: The data from the storage server (not base64 encoded)
    /// - Returns: The envelope
    /// - Throws: WrappingError if something went wrong
    static func unwrap(data: Data) throws -> SSKProtoEnvelope {
        do {
            let webSocketMessage = try WebSocketProtoWebSocketMessage.parseData(data)
            let envelope = webSocketMessage.request!.body!
            return try SSKProtoEnvelope.parseData(envelope)
        } catch let error {
            owsFailDebug("Loki API - failed unwrapping message: \(error)")
            throw WrappingError.failedToUnwrapData
        }
    }
    
    /// Wrap EnvelopeProto in a WebSocketProto
    /// This is needed because it is done automatically on the desktop
    private static func buildWebSocket(from envelope: SSKProtoEnvelope) throws -> WebSocketProtoWebSocketMessage {
        do {
            // This request is just a copy of the one on desktop
            let requestBuilder = WebSocketProtoWebSocketRequestMessage.builder(verb: "PUT", path: "/api/v1/message", requestID: UInt64.random(in: 1..<UInt64.max))
            let envelopeData = try envelope.serializedData()
            requestBuilder.setBody(envelopeData)
            
            // Build the websocket message
            let builder = WebSocketProtoWebSocketMessage.builder(type: .request)
            let request = try requestBuilder.build()
            builder.setRequest(request)
            
            return try builder.build()
        } catch let error {
            owsFailDebug("Loki API - error building websocket message: \(error)")
            throw WrappingError.failedToWrapWebSocket
        }
        
    }
    
    /// Build the EnvelopeProto from SignalMessage
    private static func buildEnvelope(from signalMessage: SignalMessage, timestamp: UInt64) throws -> SSKProtoEnvelope {
        guard let ourKeys = SSKEnvironment.shared.identityManager.identityKeyPair() else {
            owsFailDebug("Loki API - error building envelope: identityManager.identityKeyPair() is invalid")
            throw WrappingError.failedToWrapEnvelope
        }
        
        do {
            let ourPubKey = ourKeys.hexEncodedPublicKey
            
            let params = ParamParser(dictionary: signalMessage)
            
            let typeInt: Int32 = try params.required(key: "type")
            guard let type: SSKProtoEnvelope.SSKProtoEnvelopeType = SSKProtoEnvelope.SSKProtoEnvelopeType(rawValue: typeInt) else {
                Logger.error("`type` was invalid: \(typeInt)")
                throw ParamParser.ParseError.invalidFormat("type")
            }
            
            let builder = SSKProtoEnvelope.builder(type: type, timestamp: timestamp)
            builder.setSource(ourPubKey)
            builder.setSourceDevice(OWSDevicePrimaryDeviceId)
            
            if let content = try params.optionalBase64EncodedData(key: "content") {
                builder.setContent(content)
            }
            
            return try builder.build()
        } catch let error {
            owsFailDebug("Loki Message: error building envelope: \(error)")
            throw WrappingError.failedToWrapEnvelope
        }
    }
    
    
}
