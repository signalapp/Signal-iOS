
public struct LokiDeviceLink : Hashable {
    public let master: Device
    public let slave: Device
    
    public var isAuthorized: Bool { return master.signature != nil }
    
    // MARK: Types
    public struct Device : Hashable {
        public let hexEncodedPublicKey: String
        public let signature: Data?
        
        public init(hexEncodedPublicKey: String, signature: Data? = nil) {
            self.hexEncodedPublicKey = hexEncodedPublicKey
            self.signature = signature
        }
        
        public func hash(into hasher: inout Hasher) {
            hexEncodedPublicKey.hash(into: &hasher)
            signature?.hash(into: &hasher)
        }
    }
    
    // MARK: Lifecycle
    public init(between master: Device, and slave: Device) {
        self.master = master
        self.slave = slave
    }
    
    // MARK: Hashing
    public func hash(into hasher: inout Hasher) {
        master.hash(into: &hasher)
        slave.hash(into: &hasher)
    }
}
