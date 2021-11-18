import WebRTC

/// See https://developer.mozilla.org/en-US/docs/Web/API/RTCSessionDescription for more information.
@objc(SNCallMessage)
public final class CallMessage : ControlMessage {
    public var uuid: String?
    public var kind: Kind?
    /// See https://developer.mozilla.org/en-US/docs/Glossary/SDP for more information.
    public var sdps: [String]?
        
    public override var ttl: UInt64 { 2 * 60 * 1000 }
    public override var isSelfSendValid: Bool { true }
    
    // NOTE: Multiple ICE candidates may be batched together for performance
    
    // MARK: Kind
    public enum Kind : Codable, CustomStringConvertible {
        case preOffer
        case offer
        case answer
        case provisionalAnswer
        case iceCandidates(sdpMLineIndexes: [UInt32], sdpMids: [String])
        case endCall
        
        public var description: String {
            switch self {
            case .preOffer: return "preOffer"
            case .offer: return "offer"
            case .answer: return "answer"
            case .provisionalAnswer: return "provisionalAnswer"
            case .iceCandidates(_, _): return "iceCandidates"
            case .endCall: return "endCall"
            }
        }
    }
    
    // MARK: Initialization
    public override init() { super.init() }
    
    internal init(uuid: String, kind: Kind, sdps: [String]) {
        super.init()
        self.uuid = uuid
        self.kind = kind
        self.sdps = sdps
    }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid else { return false }
        return kind != nil && uuid != nil
    }
    
    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        guard let rawKind = coder.decodeObject(forKey: "kind") as! String? else { return nil }
        switch rawKind {
        case "preOffer": kind = .preOffer
        case "offer": kind = .offer
        case "answer": kind = .answer
        case "provisionalAnswer": kind = .provisionalAnswer
        case "iceCandidates":
            guard let sdpMLineIndexes = coder.decodeObject(forKey: "sdpMLineIndexes") as? [UInt32],
                let sdpMids = coder.decodeObject(forKey: "sdpMids") as? [String] else { return nil }
            kind = .iceCandidates(sdpMLineIndexes: sdpMLineIndexes, sdpMids: sdpMids)
        case "endCall": kind = .endCall
        default: preconditionFailure()
        }
        if let sdps = coder.decodeObject(forKey: "sdps") as! [String]? { self.sdps = sdps }
        if let uuid = coder.decodeObject(forKey: "uuid") as! String? { self.uuid = uuid }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        switch kind {
        case .preOffer: coder.encode("preOffer", forKey: "kind")
        case .offer: coder.encode("offer", forKey: "kind")
        case .answer: coder.encode("answer", forKey: "kind")
        case .provisionalAnswer: coder.encode("provisionalAnswer", forKey: "kind")
        case let .iceCandidates(sdpMLineIndexes, sdpMids):
            coder.encode("iceCandidates", forKey: "kind")
            coder.encode(sdpMLineIndexes, forKey: "sdpMLineIndexes")
            coder.encode(sdpMids, forKey: "sdpMids")
        case .endCall: coder.encode("endCall", forKey: "kind")
        default: preconditionFailure()
        }
        coder.encode(sdps, forKey: "sdps")
        coder.encode(uuid, forKey: "uuid")
    }
    
    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> CallMessage? {
        guard let callMessageProto = proto.callMessage else { return nil }
        let kind: Kind
        switch callMessageProto.type {
        case .preOffer: kind = .preOffer
        case .offer: kind = .offer
        case .answer: kind = .answer
        case .provisionalAnswer: kind = .provisionalAnswer
        case .iceCandidates:
            let sdpMLineIndexes = callMessageProto.sdpMlineIndexes
            let sdpMids = callMessageProto.sdpMids
            kind = .iceCandidates(sdpMLineIndexes: sdpMLineIndexes, sdpMids: sdpMids)
        case .endCall: kind = .endCall
        }
        let sdps = callMessageProto.sdps
        let uuid = callMessageProto.uuid
        return CallMessage(uuid: uuid, kind: kind, sdps: sdps)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        guard let kind = kind, let uuid = uuid else {
            SNLog("Couldn't construct call message proto from: \(self).")
            return nil
        }
        let type: SNProtoCallMessage.SNProtoCallMessageType
        switch kind {
        case .preOffer: type = .preOffer
        case .offer: type = .offer
        case .answer: type = .answer
        case .provisionalAnswer: type = .provisionalAnswer
        case .iceCandidates(_, _): type = .iceCandidates
        case .endCall: type = .endCall
        }
        let callMessageProto = SNProtoCallMessage.builder(type: type, uuid: uuid)
        if let sdps = sdps, !sdps.isEmpty {
            callMessageProto.setSdps(sdps)
        }
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
            uuid: \(uuid ?? "null"),
            kind: \(kind?.description ?? "null"),
            sdps: \(sdps?.description ?? "null")
        )
        """
    }
}
