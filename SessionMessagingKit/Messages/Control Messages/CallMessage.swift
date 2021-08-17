import WebRTC

/// See https://developer.mozilla.org/en-US/docs/Web/API/RTCSessionDescription for more information.
@objc(SNCallMessage)
public final class CallMessage : ControlMessage {
    public var kind: Kind?
    /// See https://developer.mozilla.org/en-US/docs/Glossary/SDP for more information.
    public var sdp: String?
        
    // MARK: Kind
    public enum Kind : Codable, CustomStringConvertible {
        case offer
        case answer
        case provisionalAnswer
        case iceCandidate(sdpMLineIndex: UInt32, sdpMid: String)
        
        public var description: String {
            switch self {
            case .offer: return "offer"
            case .answer: return "answer"
            case .provisionalAnswer: return "provisionalAnswer"
            case .iceCandidate(_, _): return "iceCandidate"
            }
        }
    }
    
    // MARK: Initialization
    public override init() { super.init() }
    
    internal init(kind: Kind, sdp: String) {
        super.init()
        self.kind = kind
        self.sdp = sdp
    }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid else { return false }
        return kind != nil && sdp != nil
    }
    
    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        guard let rawKind = coder.decodeObject(forKey: "kind") as! String? else { return nil }
        switch rawKind {
        case "offer": kind = .offer
        case "answer": kind = .answer
        case "provisionalAnswer": kind = .provisionalAnswer
        case "iceCandidate":
            guard let sdpMLineIndex = coder.decodeObject(forKey: "sdpMLineIndex") as? UInt32,
                let sdpMid = coder.decodeObject(forKey: "sdpMid") as? String else { return nil }
            kind = .iceCandidate(sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        default: preconditionFailure()
        }
        if let sdp = coder.decodeObject(forKey: "sdp") as! String? { self.sdp = sdp }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        switch kind {
        case .offer: coder.encode("offer", forKey: "kind")
        case .answer: coder.encode("answer", forKey: "kind")
        case .provisionalAnswer: coder.encode("provisionalAnswer", forKey: "kind")
        case let .iceCandidate(sdpMLineIndex, sdpMid):
            coder.encode("iceCandidate", forKey: "kind")
            coder.encode(sdpMLineIndex, forKey: "sdpMLineIndex")
            coder.encode(sdpMid, forKey: "sdpMid")
        default: preconditionFailure()
        }
        coder.encode(sdp, forKey: "sdp")
    }
    
    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> CallMessage? {
        guard let callMessageProto = proto.callMessage else { return nil }
        let kind: Kind
        switch callMessageProto.type {
        case .offer: kind = .offer
        case .answer: kind = .answer
        case .provisionalAnswer: kind = .provisionalAnswer
        case .iceCandidate:
            let sdpMLineIndex = callMessageProto.sdpMlineIndex
            guard let sdpMid = callMessageProto.sdpMid else { return nil }
            kind = .iceCandidate(sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        }
        let sdp = callMessageProto.sdp
        return CallMessage(kind: kind, sdp: sdp)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        guard let kind = kind, let sdp = sdp else {
            SNLog("Couldn't construct call message proto from: \(self).")
            return nil
        }
        if case .offer = kind {
            print("[Calls] Converting offer message to proto.")
        }
        let type: SNProtoCallMessage.SNProtoCallMessageType
        switch kind {
        case .offer: type = .offer
        case .answer: type = .answer
        case .provisionalAnswer: type = .provisionalAnswer
        case .iceCandidate(_, _): type = .iceCandidate
        }
        let callMessageProto = SNProtoCallMessage.builder(type: type, sdp: sdp)
        if case let .iceCandidate(sdpMLineIndex, sdpMid) = kind {
            callMessageProto.setSdpMlineIndex(sdpMLineIndex)
            callMessageProto.setSdpMid(sdpMid)
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
            sdp: \(sdp ?? "null")
        )
        """
    }
}
