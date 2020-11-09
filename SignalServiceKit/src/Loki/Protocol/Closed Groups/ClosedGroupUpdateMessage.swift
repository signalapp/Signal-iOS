
@objc(LKClosedGroupUpdateMessage)
internal final class ClosedGroupUpdateMessage : TSOutgoingMessage {
    private let kind: Kind

    // MARK: Settings
    @objc internal override var ttl: UInt32 { return UInt32(TTLUtilities.getTTL(for: .closedGroupUpdate)) }

    @objc internal override func shouldBeSaved() -> Bool { return false }
    @objc internal override func shouldSyncTranscript() -> Bool { return false }

    // MARK: Kind
    internal enum Kind {
        case new(groupPublicKey: Data, name: String, groupPrivateKey: Data, senderKeys: [ClosedGroupSenderKey], members: [Data], admins: [Data])
        case info(groupPublicKey: Data, name: String, senderKeys: [ClosedGroupSenderKey], members: [Data], admins: [Data])
        case senderKeyRequest(groupPublicKey: Data)
        case senderKey(groupPublicKey: Data, senderKey: ClosedGroupSenderKey)
    }

    // MARK: Initialization
    internal init(thread: TSThread, kind: Kind) {
        self.kind = kind
        super.init(outgoingMessageWithTimestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageBody: "",
            attachmentIds: NSMutableArray(), expiresInSeconds: 0, expireStartedAt: 0, isVoiceMessage: false,
            groupMetaMessage: .unspecified, quotedMessage: nil, contactShare: nil, linkPreview: nil)
    }

    required init(dictionary: [String:Any]) throws {
        preconditionFailure("Use init(thread:kind:) instead.")
    }

    // MARK: Coding
    internal required init?(coder: NSCoder) {
        guard let thread = coder.decodeObject(forKey: "thread") as? TSThread,
            let timestamp = coder.decodeObject(forKey: "timestamp") as? UInt64,
            let groupPublicKey = coder.decodeObject(forKey: "groupPublicKey") as? Data,
            let rawKind = coder.decodeObject(forKey: "kind") as? String else { return nil }
        switch rawKind {
        case "new":
            guard let name = coder.decodeObject(forKey: "name") as? String,
                let groupPrivateKey = coder.decodeObject(forKey: "groupPrivateKey") as? Data,
                let senderKeys = coder.decodeObject(forKey: "senderKeys") as? [ClosedGroupSenderKey],
                let members = coder.decodeObject(forKey: "members") as? [Data],
                let admins = coder.decodeObject(forKey: "admins") as? [Data] else { return nil }
            self.kind = .new(groupPublicKey: groupPublicKey, name: name, groupPrivateKey: groupPrivateKey, senderKeys: senderKeys, members: members, admins: admins)
        case "info":
            guard let name = coder.decodeObject(forKey: "name") as? String,
                let senderKeys = coder.decodeObject(forKey: "senderKeys") as? [ClosedGroupSenderKey],
                let members = coder.decodeObject(forKey: "members") as? [Data],
                let admins = coder.decodeObject(forKey: "admins") as? [Data] else { return nil }
            self.kind = .info(groupPublicKey: groupPublicKey, name: name, senderKeys: senderKeys, members: members, admins: admins)
        case "senderKeyRequest":
            self.kind = .senderKeyRequest(groupPublicKey: groupPublicKey)
        case "senderKey":
            guard let senderKeys = coder.decodeObject(forKey: "senderKeys") as? [ClosedGroupSenderKey],
                let senderKey = senderKeys.first else { return nil }
            self.kind = .senderKey(groupPublicKey: groupPublicKey, senderKey: senderKey)
        default: return nil
        }
        super.init(outgoingMessageWithTimestamp: timestamp, in: thread, messageBody: "",
            attachmentIds: NSMutableArray(), expiresInSeconds: 0, expireStartedAt: 0, isVoiceMessage: false,
            groupMetaMessage: .unspecified, quotedMessage: nil, contactShare: nil, linkPreview: nil)
    }

    internal override func encode(with coder: NSCoder) {
        coder.encode(thread, forKey: "thread")
        coder.encode(timestamp, forKey: "timestamp")
        switch kind {
        case .new(let groupPublicKey, let name, let groupPrivateKey, let senderKeys, let members, let admins):
            coder.encode("new", forKey: "kind")
            coder.encode(groupPublicKey, forKey: "groupPublicKey")
            coder.encode(name, forKey: "name")
            coder.encode(groupPrivateKey, forKey: "groupPrivateKey")
            coder.encode(senderKeys, forKey: "senderKeys")
            coder.encode(members, forKey: "members")
            coder.encode(admins, forKey: "admins")
        case .info(let groupPublicKey, let name, let senderKeys, let members, let admins):
            coder.encode("info", forKey: "kind")
            coder.encode(groupPublicKey, forKey: "groupPublicKey")
            coder.encode(name, forKey: "name")
            coder.encode(senderKeys, forKey: "senderKeys")
            coder.encode(members, forKey: "members")
            coder.encode(admins, forKey: "admins")
        case .senderKeyRequest(let groupPublicKey):
            coder.encode(groupPublicKey, forKey: "groupPublicKey")
        case .senderKey(let groupPublicKey, let senderKey):
            coder.encode("senderKey", forKey: "kind")
            coder.encode(groupPublicKey, forKey: "groupPublicKey")
            coder.encode([ senderKey ], forKey: "senderKeys")
        }
    }

    // MARK: Building
    @objc internal override func dataMessageBuilder() -> Any? {
        guard let builder = super.dataMessageBuilder() as? SSKProtoDataMessage.SSKProtoDataMessageBuilder else { return nil }
        do {
            let closedGroupUpdate: SSKProtoDataMessageClosedGroupUpdate.SSKProtoDataMessageClosedGroupUpdateBuilder
            switch kind {
            case .new(let groupPublicKey, let name, let groupPrivateKey, let senderKeys, let members, let admins):
                closedGroupUpdate = SSKProtoDataMessageClosedGroupUpdate.builder(groupPublicKey: groupPublicKey, type: .new)
                closedGroupUpdate.setName(name)
                closedGroupUpdate.setGroupPrivateKey(groupPrivateKey)
                closedGroupUpdate.setSenderKeys(try senderKeys.map { try $0.toProto() })
                closedGroupUpdate.setMembers(members)
                closedGroupUpdate.setAdmins(admins)
            case .info(let groupPublicKey, let name, let senderKeys, let members, let admins):
                closedGroupUpdate = SSKProtoDataMessageClosedGroupUpdate.builder(groupPublicKey: groupPublicKey, type: .info)
                closedGroupUpdate.setName(name)
                closedGroupUpdate.setSenderKeys(try senderKeys.map { try $0.toProto() })
                closedGroupUpdate.setMembers(members)
                closedGroupUpdate.setAdmins(admins)
            case .senderKeyRequest(let groupPublicKey):
                closedGroupUpdate = SSKProtoDataMessageClosedGroupUpdate.builder(groupPublicKey: groupPublicKey, type: .senderKeyRequest)
            case .senderKey(let groupPublicKey, let senderKey):
                closedGroupUpdate = SSKProtoDataMessageClosedGroupUpdate.builder(groupPublicKey: groupPublicKey, type: .senderKey)
                closedGroupUpdate.setSenderKeys([ try senderKey.toProto() ])
            }
            builder.setClosedGroupUpdate(try closedGroupUpdate.build())
        } catch {
            owsFailDebug("Failed to build closed group update due to error: \(error).")
            return nil
        }
        return builder
    }
}
