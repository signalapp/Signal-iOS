import PromiseKit
import SessionUtilities

public struct SnodeMessage {
    /// The hex encoded public key of the recipient.
    let recipient: String
    /// The content of the message.
    let data: LosslessStringConvertible
    /// The time to live for the message in milliseconds.
    let ttl: UInt64
    /// When the proof of work was calculated.
    ///
    /// - Note: Expressed as milliseconds since 00:00:00 UTC on 1 January 1970.
    let timestamp: UInt64
    /// The base 64 encoded proof of work.
    let nonce: String

    public init(recipient: String, data: LosslessStringConvertible, ttl: UInt64, timestamp: UInt64, nonce: String) {
        self.recipient = recipient
        self.data = data
        self.ttl = ttl
        self.timestamp = timestamp
        self.nonce = nonce
    }
    
    public func toJSON() -> JSON {
        return [
            "pubKey" : recipient,
            "data" : data.description,
            "ttl" : String(ttl),
            "timestamp" : String(timestamp),
            "nonce" : nonce
        ]
    }
}
