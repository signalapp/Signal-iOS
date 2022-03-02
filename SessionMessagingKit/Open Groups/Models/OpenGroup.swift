import Sodium
import SessionUtilitiesKit

// FIXME: We need to leave the @objc name as `SNOpenGroupV2` otherwise YapDatabase won't be able to decode it
@objc(SNOpenGroupV2)
public final class OpenGroup: NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    @objc public let server: String
    @objc public let room: String
    public let id: String
    
    @objc public let publicKey: String
    @objc public let name: String
    @objc public let groupDescription: String?  // API key is 'description'
    
    /// The ID with which the image can be retrieved from the server.
    public let imageID: String?
    
    /// Monotonic room information counter that increases each time the room's metadata changes
    public let infoUpdates: Int64

    public init(
        server: String,
        room: String,
        publicKey: String,
        name: String,
        groupDescription: String?,
        imageID: String?,
        infoUpdates: Int64
    ) {
        self.server = server.lowercased()
        self.room = room
        self.id = "\(server).\(room)"
        self.publicKey = publicKey
        self.name = name
        self.groupDescription = groupDescription
        self.imageID = imageID
        self.infoUpdates = infoUpdates
    }

    // MARK: - Coding
    
    public init?(coder: NSCoder) {
        server = coder.decodeObject(forKey: "server") as! String
        room = coder.decodeObject(forKey: "room") as! String
        self.id = "\(server).\(room)"
        
        publicKey = coder.decodeObject(forKey: "publicKey") as! String
        name = coder.decodeObject(forKey: "name") as! String
        groupDescription = coder.decodeObject(forKey: "groupDescription") as? String
        imageID = coder.decodeObject(forKey: "imageID") as! String?
        infoUpdates = coder.decodeInt64(forKey: "infoUpdates")
        
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(server, forKey: "server")
        coder.encode(room, forKey: "room")
        coder.encode(publicKey, forKey: "publicKey")
        coder.encode(name, forKey: "name")
        if let groupDescription = groupDescription { coder.encode(groupDescription, forKey: "groupDescription") }
        if let imageID = imageID { coder.encode(imageID, forKey: "imageID") }
        coder.encode(infoUpdates, forKey: "infoUpdates")
    }

    override public var description: String { "\(name) (Server: \(server), Room: \(room))" }
}
