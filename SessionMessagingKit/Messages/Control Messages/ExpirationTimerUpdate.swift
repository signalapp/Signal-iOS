import SessionUtilitiesKit

@objc(SNExpirationTimerUpdate)
public final class ExpirationTimerUpdate : ControlMessage {
    /// In the case of a sync message, the public key of the person the message was targeted at.
    ///
    /// - Note: `nil` if this isn't a sync message.
    public var syncTarget: String?
    public var duration: UInt32?

    public override var isSelfSendValid: Bool { true }

    // MARK: Initialization
    public override init() { super.init() }
    
    internal init(syncTarget: String?, duration: UInt32) {
        super.init()
        self.syncTarget = syncTarget
        self.duration = duration
    }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid else { return false }
        return duration != nil
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let syncTarget = coder.decodeObject(forKey: "syncTarget") as! String? { self.syncTarget = syncTarget }
        if let duration = coder.decodeObject(forKey: "durationSeconds") as! UInt32? { self.duration = duration }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(syncTarget, forKey: "syncTarget")
        coder.encode(duration, forKey: "durationSeconds")
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> ExpirationTimerUpdate? {
        guard let dataMessageProto = proto.dataMessage else { return nil }
        let isExpirationTimerUpdate = (dataMessageProto.flags & UInt32(SNProtoDataMessage.SNProtoDataMessageFlags.expirationTimerUpdate.rawValue)) != 0
        guard isExpirationTimerUpdate else { return nil }
        let syncTarget = dataMessageProto.syncTarget
        let duration = dataMessageProto.expireTimer
        return ExpirationTimerUpdate(syncTarget: syncTarget, duration: duration)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        guard let duration = duration else {
            SNLog("Couldn't construct expiration timer update proto from: \(self).")
            return nil
        }
        let dataMessageProto = SNProtoDataMessage.builder()
        dataMessageProto.setFlags(UInt32(SNProtoDataMessage.SNProtoDataMessageFlags.expirationTimerUpdate.rawValue))
        dataMessageProto.setExpireTimer(duration)
        if let syncTarget = syncTarget { dataMessageProto.setSyncTarget(syncTarget) }
        // Group context
        do {
            try setGroupContextIfNeeded(on: dataMessageProto, using: transaction)
        } catch {
            SNLog("Couldn't construct expiration timer update proto from: \(self).")
            return nil
        }
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setDataMessage(try dataMessageProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct expiration timer update proto from: \(self).")
            return nil
        }
    }
    
    // MARK: Description
    public override var description: String {
        """
        ExpirationTimerUpdate(
            syncTarget: \(syncTarget ?? "null"),
            duration: \(duration?.description ?? "null")
        )
        """
    }
    
    // MARK: Convenience
    @objc public func setDuration(_ duration: UInt32) {
        self.duration = duration
    }
}
