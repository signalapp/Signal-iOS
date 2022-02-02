import SessionUtilitiesKit

@objc(SNMessageRequestResponse)
public final class MessageRequestResponse: ControlMessage {
    public var publicKey: String
    public var isApproved: Bool
    
    // MARK: - Initialization
    
    public init(publicKey: String, isApproved: Bool) {
        self.publicKey = publicKey
        self.isApproved = isApproved
        
        super.init()
    }
    
    // MARK: - Coding

    public required init?(coder: NSCoder) {
        guard let publicKey: String = coder.decodeObject(forKey: "publicKey") as? String else { return nil }
        guard let isApproved: Bool = coder.decodeObject(forKey: "isApproved") as? Bool else { return nil }
        
        self.publicKey = publicKey
        self.isApproved = isApproved
        
        super.init(coder: coder)
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        
        coder.encode(publicKey, forKey: "publicKey")
        coder.encode(isApproved, forKey: "isApproved")
    }
    
    // MARK: - Proto Conversion

    public override class func fromProto(_ proto: SNProtoContent) -> MessageRequestResponse? {
        guard let messageRequestResponseProto = proto.messageRequestResponse else { return nil }
        
        let publicKey = messageRequestResponseProto.publicKey.toHexString()
        let isApproved = messageRequestResponseProto.isApproved

        return MessageRequestResponse(publicKey: publicKey, isApproved: isApproved)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        let messageRequestResponseProto = SNProtoMessageRequestResponse.builder(publicKey: Data(hex: publicKey), isApproved: isApproved)
        let contentProto = SNProtoContent.builder()
        
        do {
            contentProto.setMessageRequestResponse(try messageRequestResponseProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct unsend request proto from: \(self).")
            return nil
        }
    }
    
    // MARK: - Description
    
    public override var description: String {
        """
        MessageRequestResponse(
            publicKey: \(publicKey),
            isApproved: \(isApproved)
        )
        """
    }
}
