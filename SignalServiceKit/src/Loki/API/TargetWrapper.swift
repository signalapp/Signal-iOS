
@objc internal final class TargetWrapper : NSObject, NSCoding {
    internal let address: String
    internal let port: UInt16
    
    internal init(from target: LokiAPI.Target) {
        address = target.address
        port = target.port
        super.init()
    }
    
    internal init?(coder: NSCoder) {
        address = coder.decodeObject(forKey: "address") as! String
        port = coder.decodeObject(forKey: "port") as! UInt16
        super.init()
    }
    
    internal func encode(with coder: NSCoder) {
        coder.encode(address, forKey: "address")
        coder.encode(port, forKey: "port")
    }
}
