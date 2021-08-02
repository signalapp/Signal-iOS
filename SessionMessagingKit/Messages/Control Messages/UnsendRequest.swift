import SessionUtilitiesKit

@objc(SNUnsendRequest)
public final class UnsendRequest: ControlMessage {
    public var timestamp: UInt64?
    public var author: String?
    
    public override var isSelfSendValid: Bool { true }
    
    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid else { return false }
        return timestamp != nil && author != nil
    }
    
    // MARK: Initialization
    public override init() { super.init() }

    internal init(timestamp: UInt64, author: String) {
        super.init()
        self.timestamp = timestamp
        self.author = author
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let timestamp = coder.decodeObject(forKey: "timestamp") as! UInt64? { self.timestamp = timestamp }
        if let author = coder.decodeObject(forKey: "author") as! String? { self.author = author }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(timestamp, forKey: "timestamp")
        coder.encode(author, forKey: "author")
    }
    
    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> UnsendRequest? {
        guard let unsendRequestProto = proto.unsendRequest else { return nil }
        let timestamp = unsendRequestProto.timestamp
        let author = unsendRequestProto.author
        return UnsendRequest(timestamp: timestamp, author: author)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        guard let timestamp = timestamp, let author = author else {
            SNLog("Couldn't construct unsend request proto from: \(self).")
            return nil
        }
        let unsendRequestProto = SNProtoUnsendRequest.builder(timestamp: timestamp, author: author)
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setUnsendRequest(try unsendRequestProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct unsend request proto from: \(self).")
            return nil
        }
    }
    
    // MARK: Description
    public override var description: String {
        """
        UnsendRequest(
            timestamp: \(timestamp?.description ?? "null")
            author: \(author?.description ?? "null")
        )
        """
    }
}
