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
    
    @objc(serverID)
    public var objc_serverID: UInt64 { return serverID ?? 0 }
    
    public init(serverID: UInt64?, hexEncodedPublicKey: String, displayName: String, body: String, type: String, timestamp: UInt64) {
        self.serverID = serverID
        self.hexEncodedPublicKey = hexEncodedPublicKey
        self.displayName = displayName
        self.body = body
        self.type = type
        self.timestamp = timestamp
        super.init()
    }
    
    @objc public convenience init(hexEncodedPublicKey: String, displayName: String, body: String, type: String, timestamp: UInt64) {
        self.init(serverID: nil, hexEncodedPublicKey: hexEncodedPublicKey, displayName: displayName, body: body, type: type, timestamp: timestamp)
    }
    
    internal func toJSON() -> JSON {
        let value: JSON = [ "timestamp" : timestamp, "from" : displayName, "source" : hexEncodedPublicKey ]
        return [ "text" : body, "annotations": [ [ "type" : type, "value" : value ] ] ]
    }
}
