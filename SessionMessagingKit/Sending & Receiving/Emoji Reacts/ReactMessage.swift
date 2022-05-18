
@objc(SNReactMessage)
public final class ReactMessage : MTLModel {
    
    public var timestamp: UInt64?
    public var authorId: String?
    
    @objc
    public var emoji: String?
    
    @objc
    public var sender: String?
    
    @objc
    public var messageId: String?
    
    @objc
    public init(timestamp: UInt64, authorId: String, emoji: String?) {
        self.timestamp = timestamp
        self.authorId = authorId
        self.emoji = emoji
        super.init()
    }
    
    @objc
    public override init() {
        super.init()
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }
}
