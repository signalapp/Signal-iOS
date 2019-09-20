
public struct LokiDeviceLink {
    public let master: Device
    public let slave: Device
    
    public var isAuthorized: Bool { return master.signature != nil }
    
    // MARK: Types
    public struct Device {
        public let hexEncodedPublicKey: String
        public let signature: Data?
        
        public init(hexEncodedPublicKey: String, signature: Data? = nil) {
            self.hexEncodedPublicKey = hexEncodedPublicKey
            self.signature = signature
        }
    }
    
    // MARK: Lifecycle
    public init(between master: Device, and slave: Device) {
        self.master = master
        self.slave = slave
    }
}
