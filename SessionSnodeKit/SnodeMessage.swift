import PromiseKit
import SessionUtilitiesKit

public final class SnodeMessage : NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    /// The hex encoded public key of the recipient.
    public let recipient: String
    /// The content of the message.
    public let data: LosslessStringConvertible
    /// The time to live for the message in milliseconds.
    public let ttl: UInt64
    /// When the proof of work was calculated.
    ///
    /// - Note: Expressed as milliseconds since 00:00:00 UTC on 1 January 1970.
    public let timestamp: UInt64
    /// The base 64 encoded proof of work.
    public let nonce: String

    // MARK: Initialization
    public init(recipient: String, data: LosslessStringConvertible, ttl: UInt64, timestamp: UInt64, nonce: String) {
        self.recipient = recipient
        self.data = data
        self.ttl = ttl
        self.timestamp = timestamp
        self.nonce = nonce
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let recipient = coder.decodeObject(forKey: "recipient") as! String?,
            let data = coder.decodeObject(forKey: "data") as! String?,
            let ttl = coder.decodeObject(forKey: "ttl") as! UInt64?,
            let timestamp = coder.decodeObject(forKey: "timestamp") as! UInt64?,
            let nonce = coder.decodeObject(forKey: "nonce") as! String? else { return nil }
        self.recipient = recipient
        self.data = data
        self.ttl = ttl
        self.timestamp = timestamp
        self.nonce = nonce
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(recipient, forKey: "recipient")
        coder.encode(data, forKey: "data")
        coder.encode(ttl, forKey: "ttl")
        coder.encode(timestamp, forKey: "timestamp")
        coder.encode(nonce, forKey: "nonce")
    }

    // MARK: JSON Conversion
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
