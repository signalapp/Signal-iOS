
@objc(LKDeviceLink)
public final class DeviceLink : NSObject, NSCoding {
    @objc public let master: Device
    @objc public let slave: Device
    
    @objc public var isAuthorized: Bool { return master.signature != nil }
    
    // MARK: Types
    @objc(LKDevice)
    public final class Device : NSObject, NSCoding {
        @objc public let hexEncodedPublicKey: String
        @objc public let signature: Data?
        
        @objc public init(hexEncodedPublicKey: String, signature: Data? = nil) {
            self.hexEncodedPublicKey = hexEncodedPublicKey
            self.signature = signature
        }
        
        @objc public init?(coder: NSCoder) {
            hexEncodedPublicKey = coder.decodeObject(forKey: "hexEncodedPublicKey") as! String
            signature = coder.decodeObject(forKey: "signature") as! Data?
        }
        
        @objc public func encode(with coder: NSCoder) {
            coder.encode(hexEncodedPublicKey, forKey: "hexEncodedPublicKey")
            if let signature = signature { coder.encode(signature, forKey: "signature") }
        }
        
        @objc public override func isEqual(_ other: Any?) -> Bool {
            guard let other = other as? Device else { return false }
            return hexEncodedPublicKey == other.hexEncodedPublicKey && signature == other.signature
        }
        
        @objc override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
            var result = hexEncodedPublicKey.hashValue
            if let signature = signature { result = result ^ signature.hashValue }
            return result
        }
        
        @objc override public var description: String { return hexEncodedPublicKey }
    }
    
    // MARK: Lifecycle
    @objc public init(between master: Device, and slave: Device) {
        self.master = master
        self.slave = slave
    }
    
    // MARK: Coding
    @objc public init?(coder: NSCoder) {
        master = coder.decodeObject(forKey: "master") as! Device
        slave = coder.decodeObject(forKey: "slave") as! Device
        super.init()
    }

    @objc public func encode(with coder: NSCoder) {
        coder.encode(master, forKey: "master")
        coder.encode(slave, forKey: "slave")
    }
    
    // MARK: Equality
    @objc override public func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? DeviceLink else { return false }
        return master == other.master && slave == other.slave
    }
    
    // MARK: Hashing
    @objc override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
        return master.hash ^ slave.hash
    }
    
    // MARK: Description
    @objc override public var description: String { return "\(master) - \(slave)" }
}
