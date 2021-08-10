
/// Abstract base class for `VisibleMessage` and `ControlMessage`.
@objc(SNMessage)
public class Message : NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public var id: String?
    @objc public var threadID: String?
    public var sentTimestamp: UInt64?
    public var receivedTimestamp: UInt64?
    public var recipient: String?
    public var sender: String?
    public var groupPublicKey: String?
    public var openGroupServerMessageID: UInt64?
    public var openGroupServerTimestamp: UInt64?
    public var serverHash: String?

    public var ttl: UInt64 { 14 * 24 * 60 * 60 * 1000 }
    public var isSelfSendValid: Bool { false }

    public override init() { }

    // MARK: Validation
    public var isValid: Bool {
        if let sentTimestamp = sentTimestamp { guard sentTimestamp > 0 else { return false } }
        if let receivedTimestamp = receivedTimestamp { guard receivedTimestamp > 0 else { return false } }
        return sender != nil && recipient != nil
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        if let id = coder.decodeObject(forKey: "id") as! String? { self.id = id }
        if let threadID = coder.decodeObject(forKey: "threadID") as! String? { self.threadID = threadID }
        if let sentTimestamp = coder.decodeObject(forKey: "sentTimestamp") as! UInt64? { self.sentTimestamp = sentTimestamp }
        if let receivedTimestamp = coder.decodeObject(forKey: "receivedTimestamp") as! UInt64? { self.receivedTimestamp = receivedTimestamp }
        if let recipient = coder.decodeObject(forKey: "recipient") as! String? { self.recipient = recipient }
        if let sender = coder.decodeObject(forKey: "sender") as! String? { self.sender = sender }
        if let groupPublicKey = coder.decodeObject(forKey: "groupPublicKey") as! String? { self.groupPublicKey = groupPublicKey }
        if let openGroupServerMessageID = coder.decodeObject(forKey: "openGroupServerMessageID") as! UInt64? { self.openGroupServerMessageID = openGroupServerMessageID }
        if let openGroupServerTimestamp = coder.decodeObject(forKey: "openGroupServerTimestamp") as! UInt64? { self.openGroupServerTimestamp = openGroupServerTimestamp }
        if let serverHash = coder.decodeObject(forKey: "serverHash") as! String? { self.serverHash = serverHash }
    }

    public func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(threadID, forKey: "threadID")
        coder.encode(sentTimestamp, forKey: "sentTimestamp")
        coder.encode(receivedTimestamp, forKey: "receivedTimestamp")
        coder.encode(recipient, forKey: "recipient")
        coder.encode(sender, forKey: "sender")
        coder.encode(groupPublicKey, forKey: "groupPublicKey")
        coder.encode(openGroupServerMessageID, forKey: "openGroupServerMessageID")
        coder.encode(openGroupServerTimestamp, forKey: "openGroupServerTimestamp")
        coder.encode(serverHash, forKey: "serverHash")
    }

    // MARK: Proto Conversion
    public class func fromProto(_ proto: SNProtoContent) -> Self? {
        preconditionFailure("fromProto(_:) is abstract and must be overridden.")
    }

    public func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        preconditionFailure("toProto(using:) is abstract and must be overridden.")
    }

    public func setGroupContextIfNeeded(on dataMessage: SNProtoDataMessage.SNProtoDataMessageBuilder, using transaction: YapDatabaseReadTransaction) throws {
        guard let thread = TSThread.fetch(uniqueId: threadID!, transaction: transaction) as? TSGroupThread, thread.isClosedGroup else { return }
        // Android needs a group context or it'll interpret the message as a one-to-one message
        let groupProto = SNProtoGroupContext.builder(id: thread.groupModel.groupId, type: .deliver)
        dataMessage.setGroup(try groupProto.build())
    }
    
    // MARK: General
    @objc public func setSentTimestamp(_ sentTimestamp: UInt64) {
        self.sentTimestamp = sentTimestamp
    }
}
