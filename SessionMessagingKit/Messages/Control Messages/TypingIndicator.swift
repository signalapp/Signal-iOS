import SessionUtilitiesKit

@objc(SNTypingIndicator)
public final class TypingIndicator : ControlMessage {
    public var kind: Kind?

    public override var ttl: UInt64 { 20 * 1000 }

    // MARK: Kind
    public enum Kind : Int, CustomStringConvertible {
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
        
        public var description: String {
            switch self {
            case .started: return "started"
            case .stopped: return "stopped"
            }
        }
    }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid else { return false }
        return kind != nil
    }

    // MARK: Initialization
    public override init() { super.init() }

    internal init(kind: Kind) {
        super.init()
        self.kind = kind
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let rawKind = coder.decodeObject(forKey: "action") as! Int? { kind = Kind(rawValue: rawKind) }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(kind?.rawValue, forKey: "action")
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> TypingIndicator? {
        guard let typingIndicatorProto = proto.typingMessage else { return nil }
        let kind = Kind.fromProto(typingIndicatorProto.action)
        return TypingIndicator(kind: kind)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        guard let timestamp = sentTimestamp, let kind = kind else {
            SNLog("Couldn't construct typing indicator proto from: \(self).")
            return nil
        }
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
    
    // MARK: Description
    public override var description: String {
        """
        TypingIndicator(
            kind: \(kind?.description ?? "null")
        )
        """
    }
}
