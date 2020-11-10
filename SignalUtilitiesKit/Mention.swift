
@objc(LKMention)
public final class Mention : NSObject {
    @objc public let publicKey: String
    @objc public let displayName: String
    
    @objc public init(publicKey: String, displayName: String) {
        self.publicKey = publicKey
        self.displayName = displayName
    }
    
    @objc public func isContained(in string: String) -> Bool {
        return string.contains(displayName)
    }
}
