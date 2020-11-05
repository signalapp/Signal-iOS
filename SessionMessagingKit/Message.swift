
/// Abstract base class for `VisibleMessage` and `ControlMessage`.
@objc(SNMessage)
public class Message : NSObject, NSCoding { // Not a protocol for YapDatabase compatibility
    public var id: String?
    public var threadID: String?
    public var sentTimestamp: UInt64?
    public var receivedTimestamp: UInt64?

    public required init?(coder: NSCoder) {
        preconditionFailure("init?(coder:) is abstract and must be overridden.")
    }

    public func encode(with coder: NSCoder) {
        preconditionFailure("encode(with:) is abstract and must be overridden.")
    }
}
