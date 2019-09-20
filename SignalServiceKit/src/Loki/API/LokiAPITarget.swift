
internal final class LokiAPITarget : NSObject, NSCoding {
    internal let address: String
    internal let port: UInt16
    
    // MARK: Types
    internal enum Method : String {
        /// Only supported by snode targets.
        case getSwarm = "get_snodes_for_pubkey"
        /// Only supported by snode targets.
        case getMessages = "retrieve"
        case sendMessage = "store"
    }
    
    // MARK: Initialization
    internal init(address: String, port: UInt16) {
        self.address = address
        self.port = port
    }
    
    // MARK: Coding
    internal init?(coder: NSCoder) {
        address = coder.decodeObject(forKey: "address") as! String
        port = coder.decodeObject(forKey: "port") as! UInt16
        super.init()
    }
    
    internal func encode(with coder: NSCoder) {
        coder.encode(address, forKey: "address")
        coder.encode(port, forKey: "port")
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
