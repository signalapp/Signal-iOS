import PromiseKit

public struct Message {
    /// The hex encoded public key of the recipient.
    let recipientPublicKey: String
    /// The content of the message.
    let data: LosslessStringConvertible
    /// The time to live for the message in milliseconds.
    let ttl: UInt64
    /// When the proof of work was calculated.
    ///
    /// - Note: Expressed as milliseconds since 00:00:00 UTC on 1 January 1970.
    let timestamp: UInt64? = nil
    /// The base 64 encoded proof of work.
    let nonce: String? = nil
    
    public func toJSON() -> JSON {
        var result = [ "pubKey" : recipientPublicKey, "data" : data.description, "ttl" : String(ttl) ]
        if let timestamp = timestamp, let nonce = nonce {
            result["timestamp"] = String(timestamp)
            result["nonce"] = nonce
        }
        return result
    }
}
