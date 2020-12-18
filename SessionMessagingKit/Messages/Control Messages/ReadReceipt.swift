import SessionUtilitiesKit

@objc(SNReadReceipt)
public final class ReadReceipt : ControlMessage {
    @objc public var timestamps: [UInt64]?

    // MARK: Initialization
    public override init() { super.init() }
    
    internal init(timestamps: [UInt64]) {
        super.init()
        self.timestamps = timestamps
    }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid else { return false }
        if let timestamps = timestamps, !timestamps.isEmpty { return true }
        return false
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let timestamps = coder.decodeObject(forKey: "messageTimestamps") as! [UInt64]? { self.timestamps = timestamps }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(timestamps, forKey: "messageTimestamps")
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> ReadReceipt? {
        guard let receiptProto = proto.receiptMessage, receiptProto.type == .read else { return nil }
        let timestamps = receiptProto.timestamp
        guard !timestamps.isEmpty else { return nil }
        return ReadReceipt(timestamps: timestamps)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        guard let timestamps = timestamps else {
            SNLog("Couldn't construct read receipt proto from: \(self).")
            return nil
        }
        let receiptProto = SNProtoReceiptMessage.builder(type: .read)
        receiptProto.setTimestamp(timestamps)
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setReceiptMessage(try receiptProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct read receipt proto from: \(self).")
            return nil
        }
    }
    
    // MARK: Description
    public override var description: String {
        """
        ReadReceipt(
            timestamps: \(timestamps?.description ?? "null")
        )
        """
    }
}
