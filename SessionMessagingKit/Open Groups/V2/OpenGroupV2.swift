
@objc(SNOpenGroupV2)
public final class OpenGroupV2 : NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    @objc public let server: String
    @objc public let room: String
    public let id: String
    @objc public let name: String
    @objc public let publicKey: String
    /// The ID with which the image can be retrieved from the server.
    public let imageID: String?

    public init(server: String, room: String, name: String, publicKey: String, imageID: String?) {
        self.server = server.lowercased()
        self.room = room
        self.id = "\(server).\(room)"
        self.name = name
        self.publicKey = publicKey
        self.imageID = imageID
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        server = coder.decodeObject(forKey: "server") as! String
        room = coder.decodeObject(forKey: "room") as! String
        self.id = "\(server).\(room)"
        name = coder.decodeObject(forKey: "name") as! String
        publicKey = coder.decodeObject(forKey: "publicKey") as! String
        imageID = coder.decodeObject(forKey: "imageID") as! String?
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(server, forKey: "server")
        coder.encode(room, forKey: "room")
        coder.encode(name, forKey: "name")
        coder.encode(publicKey, forKey: "publicKey")
        if let imageID = imageID { coder.encode(imageID, forKey: "imageID") }
    }

    override public var description: String { "\(name) (Server: \(server), Room: \(room)" }
}
