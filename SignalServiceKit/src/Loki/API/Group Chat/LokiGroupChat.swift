
@objc(LKGroupChat)
public final class LokiGroupChat : NSObject {
    @objc public let id: String
    @objc public let serverID: UInt64
    @objc public let server: String
    @objc public let displayName: String
    @objc public let isDeletable: Bool
    
    @objc public init(serverID: UInt64, server: String, displayName: String, isDeletable: Bool) {
        self.id = "\(server).\(serverID)"
        self.serverID = serverID
        self.server = server
        self.displayName = displayName
        self.isDeletable = isDeletable
    }
    
    override public var description: String { return displayName }
}
