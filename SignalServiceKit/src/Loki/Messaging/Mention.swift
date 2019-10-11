
@objc(LKMention)
public final class Mention : NSObject {
    @objc public let hexEncodedPublicKey: String
    @objc public let displayName: String
    
    @objc public init(hexEncodedPublicKey: String, displayName: String) {
        self.hexEncodedPublicKey = hexEncodedPublicKey
        self.displayName = displayName
    }
    
    @objc public func isContained(in string: String) -> Bool {
        return string.contains(displayName)
    }
}
