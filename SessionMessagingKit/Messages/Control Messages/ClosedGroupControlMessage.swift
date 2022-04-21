// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Sodium
import Curve25519Kit
import SessionUtilitiesKit

public final class ClosedGroupControlMessage : ControlMessage {
    private enum CodingKeys: String, CodingKey {
        case kind
    }
    
    public var kind: Kind?

    public override var ttl: UInt64 {
        switch kind {
        case .encryptionKeyPair: return 14 * 24 * 60 * 60 * 1000
        default: return 14 * 24 * 60 * 60 * 1000
        }
    }
    
    public override var isSelfSendValid: Bool { true }
    
    // MARK: Kind
    public enum Kind: CustomStringConvertible, Codable {
        private enum CodingKeys: String, CodingKey {
            case description
            case publicKey
            case name
            case encryptionPublicKey
            case encryptionSecretKey
            case members
            case admins
            case expirationTimer
            case wrappers
        }
        
        case new(publicKey: Data, name: String, encryptionKeyPair: Box.KeyPair, members: [Data], admins: [Data], expirationTimer: UInt32)
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
            case .encryptionKeyPair: return "encryptionKeyPair"
            case .nameChange: return "nameChange"
            case .membersAdded: return "membersAdded"
            case .membersRemoved: return "membersRemoved"
            case .memberLeft: return "memberLeft"
            case .encryptionKeyPairRequest: return "encryptionKeyPairRequest"
            }
        }
        
        public init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            
            // Compare the descriptions to find the appropriate case
            let description: String = try container.decode(String.self, forKey: .description)
            let newDescription: String = Kind.new(
                publicKey: Data(),
                name: "",
                encryptionKeyPair: Box.KeyPair(publicKey: [], secretKey: []),
                members: [],
                admins: [],
                expirationTimer: 0
            ).description
            
            switch description {
                case newDescription:
                    self = .new(
                        publicKey: try container.decode(Data.self, forKey: .publicKey),
                        name: try container.decode(String.self, forKey: .name),
                        encryptionKeyPair: Box.KeyPair(
                            publicKey: try container.decode([UInt8].self, forKey: .encryptionPublicKey),
                            secretKey: try container.decode([UInt8].self, forKey: .encryptionSecretKey)
                        ),
                        members: try container.decode([Data].self, forKey: .members),
                        admins: try container.decode([Data].self, forKey: .admins),
                        expirationTimer: try container.decode(UInt32.self, forKey: .expirationTimer)
                    )
                    
                case Kind.encryptionKeyPair(publicKey: nil, wrappers: []).description:
                    self = .encryptionKeyPair(
                        publicKey: try? container.decode(Data.self, forKey: .publicKey),
                        wrappers: try container.decode([ClosedGroupControlMessage.KeyPairWrapper].self, forKey: .wrappers)
                    )
                    
                case Kind.nameChange(name: "").description:
                    self = .nameChange(
                        name: try container.decode(String.self, forKey: .name)
                    )
                    
                case Kind.membersAdded(members: []).description:
                    self = .membersAdded(
                        members: try container.decode([Data].self, forKey: .members)
                    )
                    
                case Kind.membersRemoved(members: []).description:
                    self = .membersRemoved(
                        members: try container.decode([Data].self, forKey: .members)
                    )
                    
                case Kind.memberLeft.description:
                    self = .memberLeft
                    
                case Kind.encryptionKeyPairRequest.description:
                    self = .encryptionKeyPairRequest
                    
                default: fatalError("Invalid case when trying to decode ClosedGroupControlMessage.Kind")
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(description, forKey: .description)
            
            // Note: If you modify the below make sure to update the above 'init(from:)' method
            switch self {
                case .new(let publicKey, let name, let encryptionKeyPair, let members, let admins, let expirationTimer):
                    try container.encode(publicKey, forKey: .publicKey)
                    try container.encode(name, forKey: .name)
                    try container.encode(encryptionKeyPair.publicKey, forKey: .encryptionPublicKey)
                    try container.encode(encryptionKeyPair.secretKey, forKey: .encryptionSecretKey)
                    try container.encode(members, forKey: .members)
                    try container.encode(admins, forKey: .admins)
                    try container.encode(expirationTimer, forKey: .expirationTimer)
                    
                case .encryptionKeyPair(let publicKey, let wrappers):
                    try container.encode(publicKey, forKey: .publicKey)
                    try container.encode(wrappers, forKey: .wrappers)
                    
                case .nameChange(let name):
                    try container.encode(name, forKey: .name)
                    
                case .membersAdded(let members), .membersRemoved(let members):
                    try container.encode(members, forKey: .members)
                    
                case .memberLeft: break                 // Only 'description'
                case .encryptionKeyPairRequest: break   // Only 'description'
            }
        }
    }

    // MARK: Key Pair Wrapper
    @objc(SNKeyPairWrapper)
    public final class KeyPairWrapper: NSObject, Codable, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
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
        case .new(let publicKey, let name, let encryptionKeyPair, let members, let admins, let expirationTimer):
            return !publicKey.isEmpty && !name.isEmpty && !encryptionKeyPair.publicKey.isEmpty
                && !encryptionKeyPair.secretKey.isEmpty && !members.isEmpty && !admins.isEmpty
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
                let encryptionKeyPair = coder.decodeObject(forKey: "encryptionKeyPair") as? SessionUtilitiesKit.Legacy.KeyPair,
                let members = coder.decodeObject(forKey: "members") as? [Data],
                let admins = coder.decodeObject(forKey: "admins") as? [Data] else { return nil }
            let expirationTimer = coder.decodeObject(forKey: "expirationTimer") as? UInt32 ?? 0
            let keyPair: Box.KeyPair = Box.KeyPair(
                publicKey: encryptionKeyPair.publicKey.bytes,
                secretKey: encryptionKeyPair.privateKey.bytes
            )
            self.kind = .new(publicKey: publicKey, name: name, encryptionKeyPair: keyPair, members: members, admins: admins, expirationTimer: expirationTimer)
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
        case .new(let publicKey, let name, let encryptionKeyPair, let members, let admins, let expirationTimer):
            coder.encode("new", forKey: "kind")
            coder.encode(publicKey, forKey: "publicKey")
            coder.encode(name, forKey: "name")
            coder.encode(encryptionKeyPair, forKey: "encryptionKeyPair")
            coder.encode(members, forKey: "members")
            coder.encode(admins, forKey: "admins")
            coder.encode(expirationTimer, forKey: "expirationTimer")
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
    
    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        kind = try container.decode(Kind.self, forKey: .kind)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(kind, forKey: .kind)
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> ClosedGroupControlMessage? {
        guard let closedGroupControlMessageProto = proto.dataMessage?.closedGroupControlMessage else { return nil }
        let kind: Kind
        switch closedGroupControlMessageProto.type {
        case .new:
            guard let publicKey = closedGroupControlMessageProto.publicKey, let name = closedGroupControlMessageProto.name,
                let encryptionKeyPairAsProto = closedGroupControlMessageProto.encryptionKeyPair else { return nil }
            let expirationTimer = closedGroupControlMessageProto.expirationTimer
            let encryptionKeyPair = Box.KeyPair(publicKey: encryptionKeyPairAsProto.publicKey.removing05PrefixIfNeeded().bytes, secretKey: encryptionKeyPairAsProto.privateKey.bytes)
            kind = .new(publicKey: publicKey, name: name, encryptionKeyPair: encryptionKeyPair,
                members: closedGroupControlMessageProto.members, admins: closedGroupControlMessageProto.admins, expirationTimer: expirationTimer)
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

    public override func toProto(_ db: Database) -> SNProtoContent? {
        guard let kind = kind else {
            SNLog("Couldn't construct closed group update proto from: \(self).")
            return nil
        }
        do {
            let closedGroupControlMessage: SNProtoDataMessageClosedGroupControlMessage.SNProtoDataMessageClosedGroupControlMessageBuilder
            switch kind {
            case .new(let publicKey, let name, let encryptionKeyPair, let members, let admins, let expirationTimer):
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .new)
                closedGroupControlMessage.setPublicKey(publicKey)
                closedGroupControlMessage.setName(name)
                let encryptionKeyPairAsProto = SNProtoKeyPair.builder(publicKey: Data(encryptionKeyPair.publicKey), privateKey: Data(encryptionKeyPair.secretKey))
                do {
                    closedGroupControlMessage.setEncryptionKeyPair(try encryptionKeyPairAsProto.build())
                } catch {
                    SNLog("Couldn't construct closed group update proto from: \(self).")
                    return nil
                }
                closedGroupControlMessage.setMembers(members)
                closedGroupControlMessage.setAdmins(admins)
                closedGroupControlMessage.setExpirationTimer(expirationTimer)
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
            try setGroupContextIfNeeded(db, on: dataMessageProto)
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

// MARK: - Convenience

public extension ClosedGroupControlMessage.Kind {
    func infoMessage(_ db: Database, sender: String) throws -> String? {
        switch self {
            case .nameChange(let name):
                return String(format: "GROUP_TITLE_CHANGED".localized(), name)
                
            case .membersAdded(let membersAsData):
                let addedMemberNames: [String] = try Profile
                    .fetchAll(db, ids: membersAsData.map { $0.toHexString() })
                    .map { $0.displayName() }
                
                return String(
                    format: "GROUP_MEMBER_JOINED".localized(),
                    addedMemberNames.joined(separator: ", ")
                )
                
            case .membersRemoved(let membersAsData):
                let userPublicKey: String = getUserHexEncodedPublicKey(db)
                let memberIds: Set<String> = membersAsData
                    .map { $0.toHexString() }
                    .asSet()
                
                var infoMessage: String = ""
                
                if !memberIds.removing(userPublicKey).isEmpty {
                    let removedMemberNames: [String] = try Profile
                        .fetchAll(db, ids: memberIds.removing(userPublicKey))
                        .map { $0.displayName() }
                    let format: String = (removedMemberNames.count > 1 ?
                        "GROUP_MEMBERS_REMOVED".localized() :
                        "GROUP_MEMBER_REMOVED".localized()
                    )

                    infoMessage = infoMessage.appending(
                        String(format: format, removedMemberNames.joined(separator: ", "))
                    )
                }
                
                if memberIds.contains(userPublicKey) {
                    infoMessage = infoMessage.appending("YOU_WERE_REMOVED".localized())
                }
                
                return infoMessage
                
            case .memberLeft:
                let userPublicKey: String = getUserHexEncodedPublicKey(db)
                
                guard sender != userPublicKey else { return "GROUP_YOU_LEFT".localized() }
                
                if let displayName: String = Profile.displayNameNoFallback(db, id: sender) {
                    return String(format: "GROUP_MEMBER_LEFT".localized(), displayName)
                }
                
                return "GROUP_UPDATED".localized()
                
            default: return nil
        }
    }
}
