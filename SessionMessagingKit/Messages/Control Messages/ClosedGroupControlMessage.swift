import SessionProtocolKit
import SessionUtilitiesKit

public final class ClosedGroupControlMessage : ControlMessage {
    public var kind: Kind?

    public override var ttl: UInt64 {
        switch kind {
        case .encryptionKeyPair: return 4 * 24 * 60 * 60 * 1000
        default: return 2 * 24 * 60 * 60 * 1000
        }
    }
    
    public override var isSelfSendValid: Bool {
        switch kind {
        case .new: return false
        default: return true
        }
    }
    
    // MARK: Kind
    public enum Kind : CustomStringConvertible {
        case new(publicKey: Data, name: String, encryptionKeyPair: ECKeyPair, members: [Data], admins: [Data])
        /// - Note: Deprecated in favor of more explicit group updates.
        case update(name: String, members: [Data])
        /// An encryption key pair encrypted for each member individually.
        ///
        /// - Note: `publicKey` is only set when an encryption key pair is sent in a one-to-one context (i.e. not in a group).
        case encryptionKeyPair(publicKey: Data?, wrappers: [KeyPairWrapper])
        case nameChange(name: String)
        case membersAdded(members: [Data])
        case membersRemoved(members: [Data])
        case memberLeft
        case encryptionKeyPairRequest

        public var description: String {
            switch self {
            case .new: return "new"
            case .update: return "update"
            case .encryptionKeyPair: return "encryptionKeyPair"
            case .nameChange: return "nameChange"
            case .membersAdded: return "membersAdded"
            case .membersRemoved: return "membersRemoved"
            case .memberLeft: return "memberLeft"
            case .encryptionKeyPairRequest: return "encryptionKeyPairRequest"
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

        public static func fromProto(_ proto: SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper) -> KeyPairWrapper? {
            return KeyPairWrapper(publicKey: proto.publicKey.toHexString(), encryptedKeyPair: proto.encryptedKeyPair)
        }

        public func toProto() -> SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper? {
            guard let publicKey = publicKey, let encryptedKeyPair = encryptedKeyPair else { return nil }
            let result = SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper.builder(publicKey: Data(hex: publicKey), encryptedKeyPair: encryptedKeyPair)
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
        case .update(let name, _):
            return !name.isEmpty
        case .encryptionKeyPair: return true
        case .nameChange(let name): return !name.isEmpty
        case .membersAdded(let members): return !members.isEmpty
        case .membersRemoved(let members): return !members.isEmpty
        case .memberLeft: return true
        case .encryptionKeyPairRequest: return true
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
            let publicKey = coder.decodeObject(forKey: "publicKey") as? Data
            guard let wrappers = coder.decodeObject(forKey: "wrappers") as? [KeyPairWrapper] else { return nil }
            self.kind = .encryptionKeyPair(publicKey: publicKey, wrappers: wrappers)
        case "nameChange":
            guard let name = coder.decodeObject(forKey: "name") as? String else { return nil }
            self.kind = .nameChange(name: name)
        case "membersAdded":
            guard let members = coder.decodeObject(forKey: "members") as? [Data] else { return nil }
            self.kind = .membersAdded(members: members)
        case "membersRemoved":
            guard let members = coder.decodeObject(forKey: "members") as? [Data] else { return nil }
            self.kind = .membersRemoved(members: members)
        case "memberLeft":
            self.kind = .memberLeft
        case "encryptionKeyPairRequest":
            self.kind = .encryptionKeyPairRequest
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
        case .encryptionKeyPair(let publicKey, let wrappers):
            coder.encode("encryptionKeyPair", forKey: "kind")
            coder.encode(publicKey, forKey: "publicKey")
            coder.encode(wrappers, forKey: "wrappers")
        case .nameChange(let name):
            coder.encode("nameChange", forKey: "kind")
            coder.encode(name, forKey: "name")
        case .membersAdded(let members):
            coder.encode("membersAdded", forKey: "kind")
            coder.encode(members, forKey: "members")
        case .membersRemoved(let members):
            coder.encode("membersRemoved", forKey: "kind")
            coder.encode(members, forKey: "members")
        case .memberLeft:
            coder.encode("memberLeft", forKey: "kind")
        case .encryptionKeyPairRequest:
            coder.encode("encryptionKeyPairRequest", forKey: "kind")
        }
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> ClosedGroupControlMessage? {
        guard let closedGroupControlMessageProto = proto.dataMessage?.closedGroupControlMessage else { return nil }
        let kind: Kind
        switch closedGroupControlMessageProto.type {
        case .new:
            guard let publicKey = closedGroupControlMessageProto.publicKey, let name = closedGroupControlMessageProto.name,
                let encryptionKeyPairAsProto = closedGroupControlMessageProto.encryptionKeyPair else { return nil }
            do {
                let encryptionKeyPair = try ECKeyPair(publicKeyData: encryptionKeyPairAsProto.publicKey.removing05PrefixIfNeeded(), privateKeyData: encryptionKeyPairAsProto.privateKey)
                kind = .new(publicKey: publicKey, name: name, encryptionKeyPair: encryptionKeyPair,
                    members: closedGroupControlMessageProto.members, admins: closedGroupControlMessageProto.admins)
            } catch {
                SNLog("Couldn't parse key pair.")
                return nil
            }
        case .update:
            guard let name = closedGroupControlMessageProto.name else { return nil }
            kind = .update(name: name, members: closedGroupControlMessageProto.members)
        case .encryptionKeyPair:
            let publicKey = closedGroupControlMessageProto.publicKey
            let wrappers = closedGroupControlMessageProto.wrappers.compactMap { KeyPairWrapper.fromProto($0) }
            kind = .encryptionKeyPair(publicKey: publicKey, wrappers: wrappers)
        case .nameChange:
            guard let name = closedGroupControlMessageProto.name else { return nil }
            kind = .nameChange(name: name)
        case .membersAdded:
            kind = .membersAdded(members: closedGroupControlMessageProto.members)
        case .membersRemoved:
            kind = .membersRemoved(members: closedGroupControlMessageProto.members)
        case .memberLeft:
            kind = .memberLeft
        case .encryptionKeyPairRequest:
            kind = .encryptionKeyPairRequest
        }
        return ClosedGroupControlMessage(kind: kind)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        guard let kind = kind else {
            SNLog("Couldn't construct closed group update proto from: \(self).")
            return nil
        }
        do {
            let closedGroupControlMessage: SNProtoDataMessageClosedGroupControlMessage.SNProtoDataMessageClosedGroupControlMessageBuilder
            switch kind {
            case .new(let publicKey, let name, let encryptionKeyPair, let members, let admins):
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .new)
                closedGroupControlMessage.setPublicKey(publicKey)
                closedGroupControlMessage.setName(name)
                let encryptionKeyPairAsProto = SNProtoKeyPair.builder(publicKey: encryptionKeyPair.publicKey, privateKey: encryptionKeyPair.privateKey)
                do {
                    closedGroupControlMessage.setEncryptionKeyPair(try encryptionKeyPairAsProto.build())
                } catch {
                    SNLog("Couldn't construct closed group update proto from: \(self).")
                    return nil
                }
                closedGroupControlMessage.setMembers(members)
                closedGroupControlMessage.setAdmins(admins)
            case .update(let name, let members):
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .update)
                closedGroupControlMessage.setName(name)
                closedGroupControlMessage.setMembers(members)
            case .encryptionKeyPair(let publicKey, let wrappers):
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .encryptionKeyPair)
                if let publicKey = publicKey {
                    closedGroupControlMessage.setPublicKey(publicKey)
                }
                closedGroupControlMessage.setWrappers(wrappers.compactMap { $0.toProto() })
            case .nameChange(let name):
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .nameChange)
                closedGroupControlMessage.setName(name)
            case .membersAdded(let members):
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .membersAdded)
                closedGroupControlMessage.setMembers(members)
            case .membersRemoved(let members):
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .membersRemoved)
                closedGroupControlMessage.setMembers(members)
            case .memberLeft:
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .memberLeft)
            case .encryptionKeyPairRequest:
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .encryptionKeyPairRequest)
            }
            let contentProto = SNProtoContent.builder()
            let dataMessageProto = SNProtoDataMessage.builder()
            dataMessageProto.setClosedGroupControlMessage(try closedGroupControlMessage.build())
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
        ClosedGroupControlMessage(
            kind: \(kind?.description ?? "null")
        )
        """
    }
}
