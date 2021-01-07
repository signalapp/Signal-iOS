import SessionProtocolKit
import SessionUtilitiesKit

public final class ClosedGroupUpdateV2 : ControlMessage {
    public var kind: Kind?

    public override var ttl: UInt64 {
        switch kind {
        case .encryptionKeyPair: return 4 * 24 * 60 * 60 * 1000
        default: return 2 * 24 * 60 * 60 * 1000
        }
    }
    
    // MARK: Kind
    public enum Kind : CustomStringConvertible {
        case new(publicKey: Data, name: String, encryptionKeyPair: ECKeyPair, members: [Data], admins: [Data])
        case update(name: String, members: [Data])
        case encryptionKeyPair([KeyPairWrapper]) // The new encryption key pair encrypted for each member individually

        public var description: String {
            switch self {
            case .new: return "new"
            case .update: return "update"
            case .encryptionKeyPair: return "encryptionKeyPair"
            }
        }
    }

    // MARK: Key Pair Wrapper
    @objc(SNKeyPairWrapper)
    public final class KeyPairWrapper : NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
        public var publicKey: String?
        public var encryptedKeyPair: Data?

        public var isValid: Bool { publicKey != nil && encryptedKeyPair != nil }

        public init(publicKey: String, encryptedKeyPair: Data) {
            self.publicKey = publicKey
            self.encryptedKeyPair = encryptedKeyPair
        }

        public required init?(coder: NSCoder) {
            if let publicKey = coder.decodeObject(forKey: "publicKey") as! String? { self.publicKey = publicKey }
            if let encryptedKeyPair = coder.decodeObject(forKey: "encryptedKeyPair") as! Data? { self.encryptedKeyPair = encryptedKeyPair }
        }

        public func encode(with coder: NSCoder) {
            coder.encode(publicKey, forKey: "publicKey")
            coder.encode(encryptedKeyPair, forKey: "encryptedKeyPair")
        }

        public static func fromProto(_ proto: SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper) -> KeyPairWrapper? {
            return KeyPairWrapper(publicKey: proto.publicKey.toHexString(), encryptedKeyPair: proto.encryptedKeyPair)
        }

        public func toProto() -> SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper? {
            guard let publicKey = publicKey, let encryptedKeyPair = encryptedKeyPair else { return nil }
            let result = SNProtoDataMessageClosedGroupUpdateV2KeyPairWrapper.builder(publicKey: Data(hex: publicKey), encryptedKeyPair: encryptedKeyPair)
            do {
                return try result.build()
            } catch {
                SNLog("Couldn't construct key pair wrapper proto from: \(self).")
                return nil
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
        case .new(let publicKey, let name, let encryptionKeyPair, let members, let admins):
            return !publicKey.isEmpty && !name.isEmpty && !encryptionKeyPair.publicKey.isEmpty
                && !encryptionKeyPair.privateKey.isEmpty && !members.isEmpty && !admins.isEmpty
        case .update(let name, let members):
            return !name.isEmpty && !members.isEmpty
        case .encryptionKeyPair: return true
        }
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        guard let rawKind = coder.decodeObject(forKey: "kind") as? String else { return nil }
        switch rawKind {
        case "new":
            guard let publicKey = coder.decodeObject(forKey: "publicKey") as? Data,
                let name = coder.decodeObject(forKey: "name") as? String,
                let encryptionKeyPair = coder.decodeObject(forKey: "encryptionKeyPair") as? ECKeyPair,
                let members = coder.decodeObject(forKey: "members") as? [Data],
                let admins = coder.decodeObject(forKey: "admins") as? [Data] else { return nil }
            self.kind = .new(publicKey: publicKey, name: name, encryptionKeyPair: encryptionKeyPair, members: members, admins: admins)
        case "update":
            guard let name = coder.decodeObject(forKey: "name") as? String,
                let members = coder.decodeObject(forKey: "members") as? [Data] else { return nil }
            self.kind = .update(name: name, members: members)
        case "encryptionKeyPair":
            guard let wrappers = coder.decodeObject(forKey: "wrappers") as? [KeyPairWrapper] else { return nil }
            self.kind = .encryptionKeyPair(wrappers)
        default: return nil
        }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        guard let kind = kind else { return }
        switch kind {
        case .new(let publicKey, let name, let encryptionKeyPair, let members, let admins):
            coder.encode("new", forKey: "kind")
            coder.encode(publicKey, forKey: "publicKey")
            coder.encode(name, forKey: "name")
            coder.encode(encryptionKeyPair, forKey: "encryptionKeyPair")
            coder.encode(members, forKey: "members")
            coder.encode(admins, forKey: "admins")
        case .update(let name, let members):
            coder.encode("update", forKey: "kind")
            coder.encode(name, forKey: "name")
            coder.encode(members, forKey: "members")
        case .encryptionKeyPair(let wrappers):
            coder.encode("encryptionKeyPair", forKey: "kind")
            coder.encode(wrappers, forKey: "wrappers")
        }
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> ClosedGroupUpdateV2? {
        guard let closedGroupUpdateProto = proto.dataMessage?.closedGroupUpdateV2 else { return nil }
        let kind: Kind
        switch closedGroupUpdateProto.type {
        case .new:
            guard let publicKey = closedGroupUpdateProto.publicKey, let name = closedGroupUpdateProto.name,
                let encryptionKeyPairAsProto = closedGroupUpdateProto.encryptionKeyPair else { return nil }
            do {
                let encryptionKeyPair = try ECKeyPair(publicKeyData: encryptionKeyPairAsProto.publicKey.removing05PrefixIfNeeded(), privateKeyData: encryptionKeyPairAsProto.privateKey)
                kind = .new(publicKey: publicKey, name: name, encryptionKeyPair: encryptionKeyPair,
                    members: closedGroupUpdateProto.members, admins: closedGroupUpdateProto.admins)
            } catch {
                SNLog("Couldn't parse key pair.")
                return nil
            }
        case .update:
            guard let name = closedGroupUpdateProto.name else { return nil }
            kind = .update(name: name, members: closedGroupUpdateProto.members)
        case .encryptionKeyPair:
            let wrappers = closedGroupUpdateProto.wrappers.compactMap { KeyPairWrapper.fromProto($0) }
            kind = .encryptionKeyPair(wrappers)
        }
        return ClosedGroupUpdateV2(kind: kind)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        guard let kind = kind else {
            SNLog("Couldn't construct closed group update proto from: \(self).")
            return nil
        }
        do {
            let closedGroupUpdate: SNProtoDataMessageClosedGroupUpdateV2.SNProtoDataMessageClosedGroupUpdateV2Builder
            switch kind {
            case .new(let publicKey, let name, let encryptionKeyPair, let members, let admins):
                closedGroupUpdate = SNProtoDataMessageClosedGroupUpdateV2.builder(type: .new)
                closedGroupUpdate.setPublicKey(publicKey)
                closedGroupUpdate.setName(name)
                let encryptionKeyPairAsProto = SNProtoDataMessageClosedGroupUpdateV2KeyPair.builder(publicKey: encryptionKeyPair.publicKey, privateKey: encryptionKeyPair.privateKey)
                do {
                    closedGroupUpdate.setEncryptionKeyPair(try encryptionKeyPairAsProto.build())
                } catch {
                    SNLog("Couldn't construct closed group update proto from: \(self).")
                    return nil
                }
                closedGroupUpdate.setMembers(members)
                closedGroupUpdate.setAdmins(admins)
            case .update(let name, let members):
                closedGroupUpdate = SNProtoDataMessageClosedGroupUpdateV2.builder(type: .update)
                closedGroupUpdate.setName(name)
                closedGroupUpdate.setMembers(members)
            case .encryptionKeyPair(let wrappers):
                closedGroupUpdate = SNProtoDataMessageClosedGroupUpdateV2.builder(type: .encryptionKeyPair)
                closedGroupUpdate.setWrappers(wrappers.compactMap { $0.toProto() })
            }
            let contentProto = SNProtoContent.builder()
            let dataMessageProto = SNProtoDataMessage.builder()
            dataMessageProto.setClosedGroupUpdateV2(try closedGroupUpdate.build())
            // Group context
            try setGroupContextIfNeeded(on: dataMessageProto, using: transaction)
            // Expiration timer
            // TODO: We * want * expiration timer updates to be explicit. But currently Android will disable the expiration timer for a conversation
            // if it receives a message without the current expiration timer value attached to it...
            var expiration: UInt32 = 0
            if let disappearingMessagesConfiguration = OWSDisappearingMessagesConfiguration.fetch(uniqueId: threadID!, transaction: transaction) {
                expiration = disappearingMessagesConfiguration.isEnabled ? disappearingMessagesConfiguration.durationSeconds : 0
            }
            dataMessageProto.setExpireTimer(expiration)
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
