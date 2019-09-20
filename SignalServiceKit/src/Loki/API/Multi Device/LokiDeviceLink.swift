
@objc(LKDeviceLink)
public final class LokiDeviceLink : NSObject, NSCoding {
    public let master: Device
    public let slave: Device
    
    public var isAuthorized: Bool { return master.signature != nil }
    
    // MARK: Types
    @objc(LKDevice)
    public final class Device : NSObject, NSCoding {
        public let hexEncodedPublicKey: String
        public let signature: Data?
        
        public init(hexEncodedPublicKey: String, signature: Data? = nil) {
            self.hexEncodedPublicKey = hexEncodedPublicKey
            self.signature = signature
        }
        
        public init?(coder: NSCoder) {
            hexEncodedPublicKey = coder.decodeObject(forKey: "hexEncodedPublicKey") as! String
            signature = coder.decodeObject(forKey: "signature") as! Data?
        }
        
        public func encode(with coder: NSCoder) {
            coder.encode(hexEncodedPublicKey, forKey: "hexEncodedPublicKey")
            if let signature = signature { coder.encode(signature, forKey: "signature") }
        }
        
        public override func isEqual(_ other: Any?) -> Bool {
            guard let other = other as? Device else { return false }
            return hexEncodedPublicKey == other.hexEncodedPublicKey && signature == other.signature
        }
        
        override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
            var result = hexEncodedPublicKey.hashValue
            if let signature = signature { result = result ^ signature.hashValue }
            return result
        }
        
        override public var description: String { return hexEncodedPublicKey }
    }
    
    // MARK: Lifecycle
    public init(between master: Device, and slave: Device) {
        self.master = master
        self.slave = slave
    }
    
    // MARK: Coding
    public init?(coder: NSCoder) {
        master = coder.decodeObject(forKey: "master") as! Device
        slave = coder.decodeObject(forKey: "slave") as! Device
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(master, forKey: "master")
        coder.encode(slave, forKey: "slave")
    }
    
    // MARK: Equality
    override public func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? LokiDeviceLink else { return false }
        return master == other.master && slave == other.slave
    }
    
    // MARK: Hashing
    override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
        return master.hash ^ slave.hash
    }
    
    // MARK: Description
    override public var description: String { return "\(master) - \(slave)" }
}
