import SessionUtilities

@objc(SNExpirationTimerUpdate)
public final class ExpirationTimerUpdate : ControlMessage {
    public var duration: UInt32?

    // MARK: Initialization
    init(duration: UInt32) {
        super.init()
        self.duration = duration
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let duration = coder.decodeObject(forKey: "duration") as! UInt32? { self.duration = duration }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(duration, forKey: "duration")
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> ExpirationTimerUpdate? {
        guard let dataMessageProto = proto.dataMessage else { return nil }
        let isExpirationTimerUpdate = (dataMessageProto.flags & UInt32(SNProtoDataMessage.SNProtoDataMessageFlags.expirationTimerUpdate.rawValue)) != 0
        guard isExpirationTimerUpdate else { return nil }
        let duration = dataMessageProto.expireTimer
        return ExpirationTimerUpdate(duration: duration)
    }

    public override func toProto() -> SNProtoContent? {
        guard let duration = duration else {
            SNLog("Couldn't construct expiration timer update proto from: \(self).")
            return nil
        }
        let dataMessageProto = SNProtoDataMessage.builder()
        dataMessageProto.setFlags(UInt32(SNProtoDataMessage.SNProtoDataMessageFlags.expirationTimerUpdate.rawValue))
        dataMessageProto.setExpireTimer(duration)
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setDataMessage(try dataMessageProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct expiration timer update proto from: \(self).")
            return nil
        }
    }
}
