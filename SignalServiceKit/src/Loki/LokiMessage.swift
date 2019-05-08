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
    /// - Note: Expressed as seconds since 00:00:00 UTC on 1 January 1970.
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
    
    public static func fromSignalMessage(_ signalMessage: SignalMessage, requiringPoW isPoWRequired: Bool) -> Promise<LokiMessage> {
        return Promise<LokiMessage> { seal in
            DispatchQueue.global(qos: .default).async {
                let destination = signalMessage["destination"] as! String
                let data = signalMessage["content"] as! String
                let ttl = LokiAPI.defaultMessageTTL
                if isPoWRequired {
                    let timestamp = UInt64(Date().timeIntervalSince1970)
                    if let nonce = ProofOfWork.calculate(data: data, pubKey: destination, timestamp: timestamp, ttl: ttl) {
                        let result = LokiMessage(destination: destination, data: data, ttl: ttl, timestamp: timestamp, nonce: nonce)
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
    
    public func toJSON() -> JSON {
        var result = [ "pubKey" : destination, "data" : data.description, "ttl" : String(ttl) ]
        if let timestamp = timestamp, let nonce = nonce {
            result["timestamp"] = String(timestamp)
            result["nonce"] = nonce
        }
        return result
    }
}
