
@objc(SNOpenGroupV2)
public final class OpenGroupV2 : NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    @objc public let server: String
    @objc public let room: String
    public let id: String
    public let name: String

    public init(server: String, room: String, name: String) {
        self.server = server.lowercased()
        self.room = room
        self.id = "\(server).\(room)"
        self.name = name
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        server = coder.decodeObject(forKey: "server") as! String
        room = coder.decodeObject(forKey: "room") as! String
        self.id = "\(server).\(room)"
        name = coder.decodeObject(forKey: "name") as! String
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(server, forKey: "server")
        coder.encode(room, forKey: "room")
        coder.encode(name, forKey: "name")
    }

    override public var description: String { "\(name) (\(server) → \(room)" }
}
