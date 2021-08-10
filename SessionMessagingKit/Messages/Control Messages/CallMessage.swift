import WebRTC

/// See https://developer.mozilla.org/en-US/docs/Web/API/RTCSessionDescription for more information.
@objc(SNCallMessage)
public final class CallMessage : ControlMessage {
    public var type: RTCSdpType?
    /// See https://developer.mozilla.org/en-US/docs/Glossary/SDP for more information.
    public var sdp: String?
        
    // MARK: Initialization
    public override init() { super.init() }
    
    internal init(type: RTCSdpType, sdp: String) {
        super.init()
        self.type = type
        self.sdp = sdp
    }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid else { return false }
        return type != nil && sdp != nil
    }
    
    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let type = coder.decodeObject(forKey: "type") as! RTCSdpType? { self.type = type }
        if let sdp = coder.decodeObject(forKey: "sdp") as! String? { self.sdp = sdp }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(type, forKey: "type")
        coder.encode(sdp, forKey: "sdp")
    }
    
    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> CallMessage? {
        guard let callMessageProto = proto.callMessage else { return nil }
        let type = callMessageProto.type
        let sdp = callMessageProto.sdp
        return CallMessage(type: RTCSdpType.from(type), sdp: sdp)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        guard let type = type, let sdp = sdp else {
            SNLog("Couldn't construct call message proto from: \(self).")
            return nil
        }
        let callMessageProto = SNProtoCallMessage.builder(type: type.toProto(), sdp: sdp)
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
            type: \(type?.description ?? "null"),
            sdp: \(sdp ?? "null")
        )
        """
    }
}

// MARK: RTCSdpType + Utilities
extension RTCSdpType : CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .answer: return "answer"
        case .offer: return "offer"
        case .prAnswer: return "prAnswer"
        default: preconditionFailure()
        }
    }
    
    fileprivate static func from(_ type: SNProtoCallMessage.SNProtoCallMessageType) -> RTCSdpType {
        switch type {
        case .answer: return .answer
        case .offer: return .offer
        case .provisionalAnswer: return .prAnswer
        }
    }
    
    fileprivate func toProto() -> SNProtoCallMessage.SNProtoCallMessageType {
        switch self {
        case .answer: return .answer
        case .offer: return .offer
        case .prAnswer: return .provisionalAnswer
        default: preconditionFailure()
        }
    }
}
