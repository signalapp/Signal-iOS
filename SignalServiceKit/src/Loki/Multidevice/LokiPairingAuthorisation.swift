@objc(LKPairingAuthorisation)
public final class LokiPairingAuthorisation : NSObject, NSCoding {
    @objc public let primaryDevicePubKey: String
    @objc public let secondaryDevicePubKey: String
    @objc public let requestSignature: Data?
    @objc public let grantSignature: Data?
    
    @objc public var isGranted: Bool {
        return grantSignature != nil
    }
    
    @objc public init(primaryDevicePubKey: String, secondaryDevicePubKey: String, requestSignature: Data? = nil, grantSignature: Data? = nil) {
        self.primaryDevicePubKey = primaryDevicePubKey
        self.secondaryDevicePubKey = secondaryDevicePubKey
        self.requestSignature = requestSignature
        self.grantSignature = grantSignature
    }
    
    public convenience init?(coder aDecoder: NSCoder) {
        guard let primaryDevicePubKey = aDecoder.decodeObject(forKey: "primaryDevicePubKey") as? String,
            let secondaryDevicePubKey = aDecoder.decodeObject(forKey: "secondaryDevicePubKey") as? String  else {
                return nil
        }
        
        let requestSignature = aDecoder.decodeObject(forKey: "requestSignature") as? Data
        let grantSignature = aDecoder.decodeObject(forKey: "grantSignature") as? Data
        
        self.init(primaryDevicePubKey: primaryDevicePubKey, secondaryDevicePubKey: secondaryDevicePubKey, requestSignature: requestSignature, grantSignature: grantSignature)
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(primaryDevicePubKey, forKey: "primaryDevicePubKey")
        aCoder.encode(secondaryDevicePubKey, forKey: "secondaryDevicePubKey")
        aCoder.encode(requestSignature, forKey: "requestSignature")
        aCoder.encode(grantSignature, forKey: "grantSignature")
    }
}
