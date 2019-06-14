
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

    // MARK: Description
    override var description: String { return "\(address):\(port)" }
}
