import SessionProtocolKit
import SessionUtilitiesKit

@objc(SNClosedGroupUpdate)
public final class ClosedGroupUpdate : ControlMessage {
    public var kind: Kind?

    // MARK: Kind
    public enum Kind : CustomStringConvertible {
        case new(groupPublicKey: Data, name: String, groupPrivateKey: Data, senderKeys: [ClosedGroupSenderKey], members: [Data], admins: [Data])
        case info(groupPublicKey: Data, name: String, senderKeys: [ClosedGroupSenderKey], members: [Data], admins: [Data])
        case senderKeyRequest(groupPublicKey: Data)
        case senderKey(groupPublicKey: Data, senderKey: ClosedGroupSenderKey)
        
        public var description: String {
            switch self {
            case .new: return "new"
            case .info: return "info"
            case .senderKeyRequest: return "senderKeyRequest"
            case .senderKey: return "senderKey"
            }
        }
    }

    // MARK: Initialization
    public override init() { super.init() }

    internal init(kind: Kind) {
        super.init()
        self.kind = kind
    }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid, let kind = kind else { return false }
        switch kind {
        case .new(let groupPublicKey, let name, let groupPrivateKey, _, let members, let admins):
            return !groupPublicKey.isEmpty && !name.isEmpty && !groupPrivateKey.isEmpty && !members.isEmpty && !admins.isEmpty // senderKeys may be empty
        case .info(let groupPublicKey, let name, _, let members, let admins):
            return !groupPublicKey.isEmpty && !name.isEmpty && !members.isEmpty && !admins.isEmpty // senderKeys may be empty
        case .senderKeyRequest(let groupPublicKey):
            return !groupPublicKey.isEmpty
        case .senderKey(let groupPublicKey, _):
            return !groupPublicKey.isEmpty
        }
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        guard let groupPublicKey = coder.decodeObject(forKey: "groupPublicKey") as? Data,
            let rawKind = coder.decodeObject(forKey: "kind") as? String else { return }
        switch rawKind {
        case "new":
            guard let name = coder.decodeObject(forKey: "name") as? String,
                let groupPrivateKey = coder.decodeObject(forKey: "groupPrivateKey") as? Data,
                let senderKeys = coder.decodeObject(forKey: "senderKeys") as? [ClosedGroupSenderKey],
                let members = coder.decodeObject(forKey: "members") as? [Data],
                let admins = coder.decodeObject(forKey: "admins") as? [Data] else { return }
            self.kind = .new(groupPublicKey: groupPublicKey, name: name, groupPrivateKey: groupPrivateKey, senderKeys: senderKeys, members: members, admins: admins)
        case "info":
            guard let name = coder.decodeObject(forKey: "name") as? String,
                let senderKeys = coder.decodeObject(forKey: "senderKeys") as? [ClosedGroupSenderKey],
                let members = coder.decodeObject(forKey: "members") as? [Data],
                let admins = coder.decodeObject(forKey: "admins") as? [Data] else { return }
            self.kind = .info(groupPublicKey: groupPublicKey, name: name, senderKeys: senderKeys, members: members, admins: admins)
        case "senderKeyRequest":
            self.kind = .senderKeyRequest(groupPublicKey: groupPublicKey)
        case "senderKey":
            guard let senderKeys = coder.decodeObject(forKey: "senderKeys") as? [ClosedGroupSenderKey],
                let senderKey = senderKeys.first else { return }
            self.kind = .senderKey(groupPublicKey: groupPublicKey, senderKey: senderKey)
        default: return
        }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        guard let kind = kind else { return }
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

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> ClosedGroupUpdate? {
        guard let closedGroupUpdateProto = proto.dataMessage?.closedGroupUpdate else { return nil }
        let groupPublicKey = closedGroupUpdateProto.groupPublicKey
        let kind: Kind
        switch closedGroupUpdateProto.type {
        case .new:
            guard let name = closedGroupUpdateProto.name, let groupPrivateKey = closedGroupUpdateProto.groupPrivateKey else { return nil }
            let senderKeys = closedGroupUpdateProto.senderKeys.map { ClosedGroupSenderKey.fromProto($0) }
            kind = .new(groupPublicKey: groupPublicKey, name: name, groupPrivateKey: groupPrivateKey,
                senderKeys: senderKeys, members: closedGroupUpdateProto.members, admins: closedGroupUpdateProto.admins)
        case .info:
            guard let name = closedGroupUpdateProto.name else { return nil }
            let senderKeys = closedGroupUpdateProto.senderKeys.map { ClosedGroupSenderKey.fromProto($0) }
            kind = .info(groupPublicKey: groupPublicKey, name: name, senderKeys: senderKeys, members: closedGroupUpdateProto.members, admins: closedGroupUpdateProto.admins)
        case .senderKeyRequest:
            kind = .senderKeyRequest(groupPublicKey: groupPublicKey)
        case .senderKey:
            guard let senderKeyProto = closedGroupUpdateProto.senderKeys.first else { return nil }
            kind = .senderKey(groupPublicKey: groupPublicKey, senderKey: ClosedGroupSenderKey.fromProto(senderKeyProto))
        }
        return ClosedGroupUpdate(kind: kind)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        guard let kind = kind else {
            SNLog("Couldn't construct closed group update proto from: \(self).")
            return nil
        }
        do {
            let closedGroupUpdate: SNProtoDataMessageClosedGroupUpdate.SNProtoDataMessageClosedGroupUpdateBuilder
            switch kind {
            case .new(let groupPublicKey, let name, let groupPrivateKey, let senderKeys, let members, let admins):
                closedGroupUpdate = SNProtoDataMessageClosedGroupUpdate.builder(groupPublicKey: groupPublicKey, type: .new)
                closedGroupUpdate.setName(name)
                closedGroupUpdate.setGroupPrivateKey(groupPrivateKey)
                closedGroupUpdate.setSenderKeys(try senderKeys.map { try $0.toProto() })
                closedGroupUpdate.setMembers(members)
                closedGroupUpdate.setAdmins(admins)
            case .info(let groupPublicKey, let name, let senderKeys, let members, let admins):
                closedGroupUpdate = SNProtoDataMessageClosedGroupUpdate.builder(groupPublicKey: groupPublicKey, type: .info)
                closedGroupUpdate.setName(name)
                closedGroupUpdate.setSenderKeys(try senderKeys.map { try $0.toProto() })
                closedGroupUpdate.setMembers(members)
                closedGroupUpdate.setAdmins(admins)
            case .senderKeyRequest(let groupPublicKey):
                closedGroupUpdate = SNProtoDataMessageClosedGroupUpdate.builder(groupPublicKey: groupPublicKey, type: .senderKeyRequest)
            case .senderKey(let groupPublicKey, let senderKey):
                closedGroupUpdate = SNProtoDataMessageClosedGroupUpdate.builder(groupPublicKey: groupPublicKey, type: .senderKey)
                closedGroupUpdate.setSenderKeys([ try senderKey.toProto() ])
            }
            let contentProto = SNProtoContent.builder()
            let dataMessageProto = SNProtoDataMessage.builder()
            dataMessageProto.setClosedGroupUpdate(try closedGroupUpdate.build())
            // Group context
            try setGroupContextIfNeeded(on: dataMessageProto, using: transaction)
            contentProto.setDataMessage(try dataMessageProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct closed group update proto from: \(self).")
            return nil
        }
    }
    
    // MARK: Description
    public override var description: String {
        """
        ClosedGroupUpdate(
            kind: \(kind?.description ?? "null")
        )
        """
    }
}

private extension ClosedGroupSenderKey {

    static func fromProto(_ proto: SNProtoDataMessageClosedGroupUpdateSenderKey) -> ClosedGroupSenderKey {
        return ClosedGroupSenderKey(chainKey: proto.chainKey, keyIndex: UInt(proto.keyIndex), publicKey: proto.publicKey)
    }
    
    func toProto() throws -> SNProtoDataMessageClosedGroupUpdateSenderKey {
        return try SNProtoDataMessageClosedGroupUpdateSenderKey.builder(chainKey: chainKey, keyIndex: UInt32(keyIndex), publicKey: publicKey).build()
    }
}

