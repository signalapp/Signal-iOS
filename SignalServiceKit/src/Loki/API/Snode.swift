
public final class Snode : NSObject, NSCoding {
    public let address: String
    public let port: UInt16
    internal let publicKeySet: KeySet?

    public var ip: String {
        String(address[address.index(address.startIndex, offsetBy: 8)..<address.endIndex])
    }

    // MARK: Nested Types
    internal enum Method : String {
        /// Only supported by snode targets.
        case getSwarm = "get_snodes_for_pubkey"
        /// Only supported by snode targets.
        case getMessages = "retrieve"
        case sendMessage = "store"
    }
    
    internal struct KeySet {
        let ed25519Key: String
        let x25519Key: String
    }
    
    // MARK: Initialization
    internal init(address: String, port: UInt16, publicKeySet: KeySet?) {
        self.address = address
        self.port = port
        self.publicKeySet = publicKeySet
    }
    
    // MARK: Coding
    public init?(coder: NSCoder) {
        address = coder.decodeObject(forKey: "address") as! String
        port = coder.decodeObject(forKey: "port") as! UInt16
        if let idKey = coder.decodeObject(forKey: "idKey") as? String, let encryptionKey = coder.decodeObject(forKey: "encryptionKey") as? String {
            publicKeySet = KeySet(ed25519Key: idKey, x25519Key: encryptionKey)
        } else {
            publicKeySet = nil
        }
        super.init()
    }
    
    public func encode(with coder: NSCoder) {
        coder.encode(address, forKey: "address")
        coder.encode(port, forKey: "port")
        if let keySet = publicKeySet {
            coder.encode(keySet.ed25519Key, forKey: "idKey")
            coder.encode(keySet.x25519Key, forKey: "encryptionKey")
        }
    }
    
    // MARK: Equality
    override public func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? Snode else { return false }
        return address == other.address && port == other.port
    }
    
    // MARK: Hashing
    override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
        return address.hashValue ^ port.hashValue
    }

    // MARK: Description
    override public var description: String { return "\(address):\(port)" }
}
