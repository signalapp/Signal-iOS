
/// Abstract base class for `VisibleMessage` and `ControlMessage`.
@objc(SNMessage)
public class Message : NSObject, NSCoding { // Not a protocol for YapDatabase compatibility
    public var id: String?
    public var threadID: String?
    public var sentTimestamp: UInt64?
    public var receivedTimestamp: UInt64?

    public override init() { }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        preconditionFailure("init?(coder:) is abstract and must be overridden.")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(threadID, forKey: "threadID")
        coder.encode(sentTimestamp, forKey: "sentTimestamp")
        coder.encode(receivedTimestamp, forKey: "receivedTimestamp")
    }

    // MARK: Proto Conversion
    public class func fromProto(_ proto: SNProtoContent) -> Self? {
        preconditionFailure("fromProto(_:) is abstract and must be overridden.")
    }

    public func toProto() -> SNProtoContent? {
        preconditionFailure("toProto() is abstract and must be overridden.")
    }
}
