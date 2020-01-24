
internal final class LokiAPITarget : NSObject, NSCoding {
    internal let address: String
    internal let port: UInt16
    internal let publicKeySet: KeySet?
    
    // MARK: Types
    internal enum Method : String {
        /// Only supported by snode targets.
        case getSwarm = "get_snodes_for_pubkey"
        /// Only supported by snode targets.
        case getMessages = "retrieve"
        case sendMessage = "store"
    }
    
    internal struct KeySet {
        let idKey: String
        let encryptionKey: String
    }
    
    // MARK: Initialization
    internal init(address: String, port: UInt16, publicKeySet: KeySet?) {
        self.address = address
        self.port = port
        self.publicKeySet = publicKeySet
    }
    
    // MARK: Coding
    internal init?(coder: NSCoder) {
        address = coder.decodeObject(forKey: "address") as! String
        port = coder.decodeObject(forKey: "port") as! UInt16
        if let idKey = coder.decodeObject(forKey: "idKey") as? String, let encryptionKey = coder.decodeObject(forKey: "encryptionKey") as? String {
            publicKeySet = KeySet(idKey: idKey, encryptionKey: encryptionKey)
        } else {
            publicKeySet = nil
        }
        super.init()
    }
    
    internal func encode(with coder: NSCoder) {
        coder.encode(address, forKey: "address")
        coder.encode(port, forKey: "port")
        if let keySet = publicKeySet {
            coder.encode(keySet.idKey, forKey: "idKey")
            coder.encode(keySet.encryptionKey, forKey: "encryptionKey")
        }
    }
    
    // MARK: Equality
    override internal func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? LokiAPITarget else { return false }
        return address == other.address && port == other.port
    }
    
    // MARK: Hashing
    override internal var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
        return address.hashValue ^ port.hashValue
    }

    // MARK: Description
    override internal var description: String { return "\(address):\(port)" }
}
