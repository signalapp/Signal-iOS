import WebRTC

// NOTE: Multiple ICE candidates may be batched together for performance

/// See https://developer.mozilla.org/en-US/docs/Web/API/RTCSessionDescription for more information.
@objc(SNCallMessage)
public final class CallMessage : ControlMessage {
    public var kind: Kind?
    /// See https://developer.mozilla.org/en-US/docs/Glossary/SDP for more information.
    public var sdps: [String]?
        
    // MARK: Kind
    public enum Kind : Codable, CustomStringConvertible {
        case offer
        case answer
        case provisionalAnswer
        case iceCandidates(sdpMLineIndexes: [UInt32], sdpMids: [String])
        
        public var description: String {
            switch self {
            case .offer: return "offer"
            case .answer: return "answer"
            case .provisionalAnswer: return "provisionalAnswer"
            case .iceCandidates(_, _): return "iceCandidates"
            }
        }
    }
    
    // MARK: Initialization
    public override init() { super.init() }
    
    internal init(kind: Kind, sdps: [String]) {
        super.init()
        self.kind = kind
        self.sdps = sdps
    }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid else { return false }
        guard let sdps = sdps, !sdps.isEmpty else { return false }
        return kind != nil
    }
    
    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        guard let rawKind = coder.decodeObject(forKey: "kind") as! String? else { return nil }
        switch rawKind {
        case "offer": kind = .offer
        case "answer": kind = .answer
        case "provisionalAnswer": kind = .provisionalAnswer
        case "iceCandidates":
            guard let sdpMLineIndexes = coder.decodeObject(forKey: "sdpMLineIndexes") as? [UInt32],
                let sdpMids = coder.decodeObject(forKey: "sdpMids") as? [String] else { return nil }
            kind = .iceCandidates(sdpMLineIndexes: sdpMLineIndexes, sdpMids: sdpMids)
        default: preconditionFailure()
        }
        if let sdps = coder.decodeObject(forKey: "sdps") as! [String]? { self.sdps = sdps }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        switch kind {
        case .offer: coder.encode("offer", forKey: "kind")
        case .answer: coder.encode("answer", forKey: "kind")
        case .provisionalAnswer: coder.encode("provisionalAnswer", forKey: "kind")
        case let .iceCandidates(sdpMLineIndexes, sdpMids):
            coder.encode("iceCandidates", forKey: "kind")
            coder.encode(sdpMLineIndexes, forKey: "sdpMLineIndexes")
            coder.encode(sdpMids, forKey: "sdpMids")
        default: preconditionFailure()
        }
        coder.encode(sdps, forKey: "sdps")
    }
    
    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> CallMessage? {
        guard let callMessageProto = proto.callMessage else { return nil }
        let kind: Kind
        switch callMessageProto.type {
        case .offer: kind = .offer
        case .answer: kind = .answer
        case .provisionalAnswer: kind = .provisionalAnswer
        case .iceCandidates:
            let sdpMLineIndexes = callMessageProto.sdpMlineIndexes
            let sdpMids = callMessageProto.sdpMids
            kind = .iceCandidates(sdpMLineIndexes: sdpMLineIndexes, sdpMids: sdpMids)
        }
        let sdps = callMessageProto.sdps
        return CallMessage(kind: kind, sdps: sdps)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        guard let kind = kind, let sdps = sdps, !sdps.isEmpty else {
            SNLog("Couldn't construct call message proto from: \(self).")
            return nil
        }
        let type: SNProtoCallMessage.SNProtoCallMessageType
        switch kind {
        case .offer: type = .offer
        case .answer: type = .answer
        case .provisionalAnswer: type = .provisionalAnswer
        case .iceCandidates(_, _): type = .iceCandidates
        }
        let callMessageProto = SNProtoCallMessage.builder(type: type)
        callMessageProto.setSdps(sdps)
        if case let .iceCandidates(sdpMLineIndexes, sdpMids) = kind {
            callMessageProto.setSdpMlineIndexes(sdpMLineIndexes)
            callMessageProto.setSdpMids(sdpMids)
        }
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setCallMessage(try callMessageProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct call message proto from: \(self).")
            return nil
        }
    }
    
    // MARK: Description
    public override var description: String {
        """
        CallMessage(
            kind: \(kind?.description ?? "null"),
            sdps: \(sdps?.description ?? "null")
        )
        """
    }
}
