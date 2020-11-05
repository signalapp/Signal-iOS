import SessionUtilities

public final class ClosedGroupRatchet : NSObject, NSCoding { // Not a struct for YapDatabase compatibility
    public let chainKey: String
    public let keyIndex: UInt
    public let messageKeys: [String]

    // MARK: Initialization
    public init(chainKey: String, keyIndex: UInt, messageKeys: [String]) {
        self.chainKey = chainKey
        self.keyIndex = keyIndex
        self.messageKeys = messageKeys
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let chainKey = coder.decodeObject(forKey: "chainKey") as? String,
            let keyIndex = coder.decodeObject(forKey: "keyIndex") as? UInt,
            let messageKeys = coder.decodeObject(forKey: "messageKeys") as? [String] else { return nil }
        self.chainKey = chainKey
        self.keyIndex = UInt(keyIndex)
        self.messageKeys = messageKeys
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(chainKey, forKey: "chainKey")
        coder.encode(keyIndex, forKey: "keyIndex")
        coder.encode(messageKeys, forKey: "messageKeys")
    }

    // MARK: Equality
    override public func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? ClosedGroupRatchet else { return false }
        return chainKey == other.chainKey && keyIndex == other.keyIndex && messageKeys == other.messageKeys
    }

    // MARK: Hashing
    override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
        return chainKey.hashValue ^ keyIndex.hashValue ^ messageKeys.hashValue
    }

    // MARK: Description
    override public var description: String { "[ chainKey : \(chainKey), keyIndex : \(keyIndex), messageKeys : \(messageKeys.prettifiedDescription) ]" }
}
