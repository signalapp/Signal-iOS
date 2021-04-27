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

    // MARK: Initialization
    public init(recipient: String, data: LosslessStringConvertible, ttl: UInt64, timestamp: UInt64) {
        self.recipient = recipient
        self.data = data
        self.ttl = ttl
        self.timestamp = timestamp
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let recipient = coder.decodeObject(forKey: "recipient") as! String?,
            let data = coder.decodeObject(forKey: "data") as! String?,
            let ttl = coder.decodeObject(forKey: "ttl") as! UInt64?,
            let timestamp = coder.decodeObject(forKey: "timestamp") as! UInt64? else { return nil }
        self.recipient = recipient
        self.data = data
        self.ttl = ttl
        self.timestamp = timestamp
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(recipient, forKey: "recipient")
        coder.encode(data, forKey: "data")
        coder.encode(ttl, forKey: "ttl")
        coder.encode(timestamp, forKey: "timestamp")
    }

    // MARK: JSON Conversion
    public func toJSON() -> JSON {
        return [
            "pubKey" : Features.useTestnet ? recipient.removing05PrefixIfNeeded() : recipient,
            "data" : data.description,
            "ttl" : String(ttl),
            "timestamp" : String(timestamp),
            "nonce" : ""
        ]
    }
}
