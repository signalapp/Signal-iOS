import PromiseKit

public struct LokiMessage {
    /// The hex encoded public key of the receiver.
    let destination: String
    /// The content of the message.
    let data: LosslessStringConvertible
    /// The time to live for the message.
    let ttl: UInt64
    /// When the proof of work was calculated, if applicable.
    ///
    /// - Note: Expressed as milliseconds since 00:00:00 UTC on 1 January 1970.
    let timestamp: UInt64?
    /// The base 64 encoded proof of work, if applicable.
    let nonce: String?
    
    public init(destination: String, data: LosslessStringConvertible, ttl: UInt64, timestamp: UInt64?, nonce: String?) {
        self.destination = destination
        self.data = data
        self.ttl = ttl
        self.timestamp = timestamp
        self.nonce = nonce
    }
    
    /// Build a LokiMessage from a SignalMessage
    ///
    /// - Parameters:
    ///   - signalMessage: the signal message
    ///   - timestamp: the original message timestamp (TSOutgoingMessage.timestamp)
    ///   - isPoWRequired: Should we calculate proof of work
    /// - Returns: The loki message
    public static func from(signalMessage: SignalMessage, timestamp: UInt64, requiringPoW isPoWRequired: Bool) -> Promise<LokiMessage> {
        // To match the desktop application we have to take the data
        // wrap it in an envelope, then
        // wrap it in a websocket
        return Promise<LokiMessage> { seal in
            DispatchQueue.global(qos: .default).async {
                guard let envelope = buildEnvelope(fromSignalMessage: signalMessage, timestamp: timestamp) else {
                    seal.reject(LokiAPI.Error.failedToWrapInEnvelope)
                    return
                }
                
                // Make the data
                guard let websocket = wrapInWebsocket(envelope: envelope),
                    let serialized = try? websocket.serializedData() else {
                        seal.reject(LokiAPI.Error.failedToWrapInWebSocket)
                        return;
                }
                
                let data = serialized.base64EncodedString()
                let destination = signalMessage["destination"] as! String
                let ttl = LokiAPI.defaultMessageTTL
                
                if isPoWRequired {
                    // timeIntervalSince1970 returns timestamp in seconds but the storage server only accepts timestamp in milliseconds
                    let now = UInt64(Date().timeIntervalSince1970 * 1000)
                    if let nonce = ProofOfWork.calculate(data: data, pubKey: destination, timestamp: now, ttl: ttl) {
                        let result = LokiMessage(destination: destination, data: data, ttl: ttl, timestamp: now, nonce: nonce)
                        seal.fulfill(result)
                    } else {
                        seal.reject(LokiAPI.Error.proofOfWorkCalculationFailed)
                    }
                } else {
                    let result = LokiMessage(destination: destination, data: data, ttl: ttl, timestamp: nil, nonce: nil)
                    seal.fulfill(result)
                }
            }
        }
    }
    
    /// Wrap EnvelopeProto in a WebSocketProto
    /// This is needed because it is done automatically on the desktop
    private static func wrapInWebsocket(envelope: SSKProtoEnvelope) -> WebSocketProtoWebSocketMessage? {
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
        } catch {
            owsFailDebug("Loki Message: error building websocket message: \(error)")
            return nil
        }
        
    }
    
    /// Build the EnvelopeProto from SignalMessage
    private static func buildEnvelope(fromSignalMessage signalMessage: SignalMessage, timestamp: UInt64) -> SSKProtoEnvelope? {
        guard let ourKeys = SSKEnvironment.shared.identityManager.identityKeyPair() else {
            owsFailDebug("error building envelope: identityManager.identityKeyPair() is invalid")
            return nil;
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
        } catch {
            owsFailDebug("Loki Message: error building envelope: \(error)")
            return nil
        }
    }
    
    public func toJSON() -> JSON {
        var result = [ "pubKey" : destination, "data" : data.description, "ttl" : String(ttl) ]
        if let timestamp = timestamp, let nonce = nonce {
            result["timestamp"] = String(timestamp)
            result["nonce"] = nonce
        }
        return result
    }
}
