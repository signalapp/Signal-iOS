
@objc(SNOpenGroup)
public final class OpenGroup : NSObject, NSCoding {
    @objc public let id: String
    @objc public let idAsData: Data
    @objc public let channel: UInt64
    @objc public let server: String
    @objc public let displayName: String
    @objc public let isDeletable: Bool
    
    @objc public init?(channel: UInt64, server: String, displayName: String, isDeletable: Bool) {
        let id = "\(server).\(channel)"
        self.id = id
        guard let idAsData = id.data(using: .utf8) else { return nil }
        self.idAsData = idAsData
        self.channel = channel
        self.server = server.lowercased()
        self.displayName = displayName
        self.isDeletable = isDeletable
    }
    
    // MARK: Coding
    @objc public init?(coder: NSCoder) {
        channel = UInt64(coder.decodeInt64(forKey: "channel"))
        server = coder.decodeObject(forKey: "server") as! String
        let id = "\(server).\(channel)"
        self.id = id
        guard let idAsData = id.data(using: .utf8) else { return nil }
        self.idAsData = idAsData
        displayName = coder.decodeObject(forKey: "displayName") as! String
        isDeletable = coder.decodeBool(forKey: "isDeletable")
        super.init()
    }

   @objc public func encode(with coder: NSCoder) {
        coder.encode(Int64(channel), forKey: "channel")
        coder.encode(server, forKey: "server")
        coder.encode(displayName, forKey: "displayName")
        coder.encode(isDeletable, forKey: "isDeletable")
    }
    
    override public var description: String { "\(displayName) (\(server))" }
}
