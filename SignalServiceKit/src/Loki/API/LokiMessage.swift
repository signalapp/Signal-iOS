import PromiseKit

public struct LokiMessage {
    /// The hex encoded public key of the receiver.
    let destination: String
    /// The content of the message.
    let data: LosslessStringConvertible
    /// The time to live for the message in milliseconds.
    let ttl: UInt64
    /// Whether this message is a ping.
    ///
    /// - Note: The concept of pinging only applies to P2P messaging.
    let isPing: Bool
    /// When the proof of work was calculated, if applicable (P2P messages don't require proof of work).
    ///
    /// - Note: Expressed as milliseconds since 00:00:00 UTC on 1 January 1970.
    private(set) var timestamp: UInt64? = nil
    /// The base 64 encoded proof of work, if applicable (P2P messages don't require proof of work).
    private(set) var nonce: String? = nil
    
    private init(destination: String, data: LosslessStringConvertible, ttl: UInt64, isPing: Bool) {
        self.destination = destination
        self.data = data
        self.ttl = ttl
        self.isPing = isPing
    }
    
    /// Construct a `LokiMessage` from a `SignalMessage`.
    ///
    /// - Note: `timestamp` is the original message timestamp (i.e. `TSOutgoingMessage.timestamp`).
    public static func from(signalMessage: SignalMessage) -> LokiMessage? {
        // To match the desktop application, we have to wrap the data in an envelope and then wrap that in a websocket object
        do {
            let wrappedMessage = try LokiMessageWrapper.wrap(message: signalMessage)
            let data = wrappedMessage.base64EncodedString()
            let destination = signalMessage.recipientID
            var ttl = LokiAPI.defaultMessageTTL
            if let messageTTL = signalMessage.ttl, messageTTL > 0 { ttl = UInt64(messageTTL) }
            let isPing = signalMessage.isPing
            return LokiMessage(destination: destination, data: data, ttl: ttl, isPing: isPing)
        } catch let error {
            Logger.debug("[Loki] Failed to convert Signal message to Loki message: \(signalMessage).")
            return nil
        }
    }
    
    /// Calculate the proof of work for this message.
    ///
    /// - Returns: The promise of a new message with its `timestamp` and `nonce` set.
    public func calculatePoW() -> Promise<LokiMessage> {
        return Promise<LokiMessage> { seal in
            DispatchQueue.global(qos: .default).async {
                let now = NSDate.ows_millisecondTimeStamp()
                let dataAsString = self.data as! String // Safe because of how from(signalMessage:with:) is implemented
                if let nonce = ProofOfWork.calculate(data: dataAsString, pubKey: self.destination, timestamp: now, ttl: self.ttl) {
                    var result = self
                    result.timestamp = now
                    result.nonce = nonce
                    seal.fulfill(result)
                } else {
                    seal.reject(LokiAPI.Error.proofOfWorkCalculationFailed)
                }
            }
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
