
internal final class ClosedGroupSenderKey : NSObject, NSCoding {
    internal let chainKey: Data
    internal let keyIndex: UInt

    // MARK: Initialization
    init(chainKey: Data, keyIndex: UInt) {
        self.chainKey = chainKey
        self.keyIndex = keyIndex
    }

    // MARK: Coding
    public init?(coder: NSCoder) {
        guard let chainKey = coder.decodeObject(forKey: "chainKey") as? Data,
            let keyIndex = coder.decodeObject(forKey: "keyIndex") as? UInt else { return nil }
        self.chainKey = chainKey
        self.keyIndex = UInt(keyIndex)
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(chainKey, forKey: "chainKey")
        coder.encode(keyIndex, forKey: "keyIndex")
    }

    // MARK: Proto Conversion
    internal func toProto() throws -> SSKProtoDataMessageClosedGroupUpdateSenderKey {
        return try SSKProtoDataMessageClosedGroupUpdateSenderKey.builder(chainKey: chainKey, keyIndex: UInt32(keyIndex)).build()
    }

    // MARK: Equality
    override public func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? ClosedGroupSenderKey else { return false }
        return chainKey == other.chainKey && keyIndex == other.keyIndex
    }

    // MARK: Hashing
    override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
        return chainKey.hashValue ^ keyIndex.hashValue
    }

    // MARK: Description
    override public var description: String { return "[ chainKey : \(chainKey), keyIndex : \(keyIndex) ]" }
}
