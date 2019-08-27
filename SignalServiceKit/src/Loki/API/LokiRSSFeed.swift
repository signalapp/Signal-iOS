
@objc(LKRSSFeed)
public final class LokiRSSFeed : NSObject {
    @objc public let id: String
    @objc public let server: String
    @objc public let displayName: String
    @objc public let isDeletable: Bool
    
    @objc public init(id: String, server: String, displayName: String, isDeletable: Bool) {
        self.id = id
        self.server = server
        self.displayName = displayName
        self.isDeletable = isDeletable
    }
    
    override public var description: String { return displayName }
}
