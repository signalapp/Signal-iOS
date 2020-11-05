import SessionUtilities

@objc(SNExpirationTimerUpdate)
public final class ExpirationTimerUpdate : ControlMessage {
    public var duration: UInt32?

    // MARK: Initialization
    init(sentTimestamp: UInt64, receivedTimestamp: UInt64, duration: UInt32) {
        super.init()
        self.sentTimestamp = sentTimestamp
        self.receivedTimestamp = receivedTimestamp
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
        guard let data = proto.dataMessage else { return nil }
        let isExpirationTimerUpdate = (data.flags & UInt32(SNProtoDataMessage.SNProtoDataMessageFlags.expirationTimerUpdate.rawValue)) != 0
        guard isExpirationTimerUpdate else { return nil }
        let timestamp = data.timestamp
        let now = NSDate.millisecondTimestamp()
        let duration = data.expireTimer
        return ExpirationTimerUpdate(sentTimestamp: timestamp, receivedTimestamp: now, duration: duration)
    }

    public override func toProto() -> SNProtoContent? {
        guard let duration = duration else { return nil }
        let expirationTimerUpdateProto = SNProtoDataMessage.builder()
        expirationTimerUpdateProto.setFlags(UInt32(SNProtoDataMessage.SNProtoDataMessageFlags.expirationTimerUpdate.rawValue))
        expirationTimerUpdateProto.setExpireTimer(duration)
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setDataMessage(try expirationTimerUpdateProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct expiration timer update proto from: \(self).")
            return nil
        }
    }
}
