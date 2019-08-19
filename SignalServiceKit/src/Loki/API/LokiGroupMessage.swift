import PromiseKit

@objc public final class LokiGroupMessage: NSObject {
    let serverID: UInt
    let hexEncodedPublicKey: String
    let displayName: String
    let body: String
    let type: String
    
    /// - Note: Expressed as milliseconds since 00:00:00 UTC on 1 January 1970.
    let timestamp: UInt64
    
    @objc public init(serverID: UInt, hexEncodedPublicKey: String, displayName: String, body: String, type: String, timestamp: UInt64) {
        self.serverID = serverID
        self.hexEncodedPublicKey = hexEncodedPublicKey
        self.displayName = displayName
        self.body = body
        self.type = type
        self.timestamp = timestamp
    }
    
    public func toJSON() -> JSON {
        let value: JSON = [ "timestamp": timestamp, "from": displayName, "source": hexEncodedPublicKey ]
        return [ "text": body, "annotations": [ "type": type, "value": value ] ]
    }
}
