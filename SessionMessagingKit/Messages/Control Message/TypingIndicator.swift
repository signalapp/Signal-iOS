import SessionUtilities

@objc(SNTypingIndicator)
public final class TypingIndicator : ControlMessage {
    public var kind: Kind?

    public enum Kind {
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

    convenience init(sentTimestamp: UInt64, receivedTimestamp: UInt64, kind: Kind) {
        self.init()
        self.sentTimestamp = sentTimestamp
        self.receivedTimestamp = receivedTimestamp
        self.kind = kind
    }

    public override class func fromSerializedProto(_ serializedProto: Data) -> TypingIndicator? {
        do {
            let contentProto = try SNProtoContent.parseData(serializedProto)
            guard let typingIndicatorProto = contentProto.typingMessage else {
                SNLog("Couldn't parse typing indicator from: \(contentProto).")
                return nil
            }
            let timestamp = typingIndicatorProto.timestamp
            let now = NSDate.millisecondTimestamp()
            let kind = Kind.fromProto(typingIndicatorProto.action)
            return TypingIndicator(sentTimestamp: timestamp, receivedTimestamp: now, kind: kind)
        } catch {
            SNLog("Couldn't deserialize typing indicator.")
            return nil
        }
    }

    public override func toSerializedProto() -> Data? {
        guard let timestamp = sentTimestamp, let kind = kind else { return nil }
        let typingIndicatorProto = SNProtoTypingMessage.builder(timestamp: timestamp, action: kind.toProto())
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setTypingMessage(try typingIndicatorProto.build())
            return try contentProto.buildSerializedData()
        } catch {
            SNLog("Couldn't construct typing indicator proto from: \(self).")
            return nil
        }
    }
}
