
@objc(LKMention)
public final class Mention : NSObject {
    @objc public let locationInString: UInt
    @objc public let hexEncodedPublicKey: String
    @objc public let displayName: String
    
    @objc public init(locationInString: UInt, hexEncodedPublicKey: String, displayName: String) {
        self.locationInString = locationInString
        self.hexEncodedPublicKey = hexEncodedPublicKey
        self.displayName = displayName
    }
}
