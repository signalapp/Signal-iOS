import SessionUtilities

@objc(SNTypingIndicator)
public final class TypingIndicator : ControlMessage {
    public var kind: Kind?

    // MARK: Kind
    public enum Kind : String {
        case started, stopped

        static func fromProto(_ proto: SNProtoTypingMessage.SNProtoTypingMessageAction) -> Kind {
            switch proto {
            case .started: return .started
            case .stopped: return .stopped
            }
        }

        func toProto() -> SNProtoTypingMessage.SNProtoTypingMessageAction {
            switch self {
            case .started: return .started
            case .stopped: return .stopped
            }
        }
    }

    // MARK: Initialization
    init(sentTimestamp: UInt64, receivedTimestamp: UInt64, kind: Kind) {
        super.init()
        self.sentTimestamp = sentTimestamp
        self.receivedTimestamp = receivedTimestamp
        self.kind = kind
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let rawKind = coder.decodeObject(forKey: "kind") as! String? { kind = Kind(rawValue: rawKind) }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(kind?.rawValue, forKey: "kind")
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> TypingIndicator? {
        guard let typingIndicatorProto = proto.typingMessage else { return nil }
        let timestamp = typingIndicatorProto.timestamp
        let now = NSDate.millisecondTimestamp()
        let kind = Kind.fromProto(typingIndicatorProto.action)
        return TypingIndicator(sentTimestamp: timestamp, receivedTimestamp: now, kind: kind)
    }

    public override func toProto() -> SNProtoContent? {
        guard let timestamp = sentTimestamp, let kind = kind else { return nil }
        let typingIndicatorProto = SNProtoTypingMessage.builder(timestamp: timestamp, action: kind.toProto())
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setTypingMessage(try typingIndicatorProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct typing indicator proto from: \(self).")
            return nil
        }
    }
}
