import PromiseKit

@objc(LKGroupMessage)
public final class LokiGroupMessage : NSObject {
    public let serverID: UInt64?
    public let hexEncodedPublicKey: String
    public let displayName: String
    public let body: String
    /// - Note: Expressed as milliseconds since 00:00:00 UTC on 1 January 1970.
    public let timestamp: UInt64
    public let type: String
    public let quote: Quote?
    
    @objc(serverID)
    public var objc_serverID: UInt64 { return serverID ?? 0 }
    
    public struct Quote {
        public let quotedMessageTimestamp: UInt64
        public let quoteeHexEncodedPublicKey: String
        public let quotedMessageBody: String
    }
    
    public init(serverID: UInt64?, hexEncodedPublicKey: String, displayName: String, body: String, type: String, timestamp: UInt64, quote: Quote?) {
        self.serverID = serverID
        self.hexEncodedPublicKey = hexEncodedPublicKey
        self.displayName = displayName
        self.body = body
        self.type = type
        self.timestamp = timestamp
        self.quote = quote
        super.init()
    }
    
    @objc public convenience init(hexEncodedPublicKey: String, displayName: String, body: String, type: String, timestamp: UInt64, quotedMessageTimestamp: UInt64, quoteeHexEncodedPublicKey: String?, quotedMessageBody: String?) {
        let quote: Quote?
        if quotedMessageTimestamp != 0, let quoteeHexEncodedPublicKey = quoteeHexEncodedPublicKey, let quotedMessageBody = quotedMessageBody {
            quote = Quote(quotedMessageTimestamp: quotedMessageTimestamp, quoteeHexEncodedPublicKey: quoteeHexEncodedPublicKey, quotedMessageBody: quotedMessageBody)
        } else {
            quote = nil
        }
        self.init(serverID: nil, hexEncodedPublicKey: hexEncodedPublicKey, displayName: displayName, body: body, type: type, timestamp: timestamp, quote: quote)
    }
    
    internal func toJSON() -> JSON {
        var value: JSON = [ "timestamp" : timestamp, "from" : displayName, "source" : hexEncodedPublicKey ]
        if let quote = quote {
            value["quote"] = [ "id" : quote.quotedMessageTimestamp, "author" : quote.quoteeHexEncodedPublicKey, "text" : quote.quotedMessageBody ]
        }
        return [ "text" : body, "annotations": [ [ "type" : type, "value" : value ] ] ]
    }
}
