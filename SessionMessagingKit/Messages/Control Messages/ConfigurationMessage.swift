import SessionUtilitiesKit

@objc(SNConfigurationMessage)
public final class ConfigurationMessage : ControlMessage {
    public var closedGroups: Set<ClosedGroup> = []
    public var openGroups: Set<String> = []
    
    public override var ttl: UInt64 { 4 * 24 * 60 * 60 * 1000 }

    public override var isSelfSendValid: Bool { true }
    
    // MARK: Initialization
    public override init() { super.init() }

    public init(closedGroups: Set<ClosedGroup>, openGroups: Set<String>) {
        super.init()
        self.closedGroups = closedGroups
        self.openGroups = openGroups
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let closedGroups = coder.decodeObject(forKey: "closedGroups") as! Set<ClosedGroup>? { self.closedGroups = closedGroups }
        if let openGroups = coder.decodeObject(forKey: "openGroups") as! Set<String>? { self.openGroups = openGroups }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(closedGroups, forKey: "closedGroups")
        coder.encode(openGroups, forKey: "openGroups")
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> ConfigurationMessage? {
        guard let configurationProto = proto.configurationMessage else { return nil }
        let closedGroups = Set(configurationProto.closedGroups.compactMap { ClosedGroup.fromProto($0) })
        let openGroups = Set(configurationProto.openGroups)
        return ConfigurationMessage(closedGroups: closedGroups, openGroups: openGroups)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        let configurationProto = SNProtoConfigurationMessage.builder()
        configurationProto.setClosedGroups(closedGroups.compactMap { $0.toProto() })
        configurationProto.setOpenGroups([String](openGroups))
        let contentProto = SNProtoContent.builder()
        do {
            contentProto.setConfigurationMessage(try configurationProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct configuration proto from: \(self).")
            return nil
        }
    }

    // MARK: Description
    public override var description: String {
        """
        ConfigurationMessage(
            closedGroups: \([ClosedGroup](closedGroups).prettifiedDescription)
            openGroups: \([String](openGroups).prettifiedDescription)
        )
        """
    }
}

// MARK: Closed Group
extension ConfigurationMessage {

    @objc(SNClosedGroup)
    public final class ClosedGroup : NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
        public let publicKey: String
        public let name: String
        public let encryptionKeyPair: ECKeyPair
        public let members: Set<String>
        public let admins: Set<String>

        public var isValid: Bool { !members.isEmpty && !admins.isEmpty }

        public init(publicKey: String, name: String, encryptionKeyPair: ECKeyPair, members: Set<String>, admins: Set<String>) {
            self.publicKey = publicKey
            self.name = name
            self.encryptionKeyPair = encryptionKeyPair
            self.members = members
            self.admins = admins
        }

        public required init?(coder: NSCoder) {
            guard let publicKey = coder.decodeObject(forKey: "publicKey") as! String?,
                let name = coder.decodeObject(forKey: "name") as! String?,
                let encryptionKeyPair = coder.decodeObject(forKey: "encryptionKeyPair") as! ECKeyPair?,
                let members = coder.decodeObject(forKey: "members") as! Set<String>?,
                let admins = coder.decodeObject(forKey: "admins") as! Set<String>? else { return nil }
            self.publicKey = publicKey
            self.name = name
            self.encryptionKeyPair = encryptionKeyPair
            self.members = members
            self.admins = admins
        }

        public func encode(with coder: NSCoder) {
            coder.encode(publicKey, forKey: "publicKey")
            coder.encode(name, forKey: "name")
            coder.encode(encryptionKeyPair, forKey: "encryptionKeyPair")
            coder.encode(members, forKey: "members")
            coder.encode(admins, forKey: "admins")
        }

        public static func fromProto(_ proto: SNProtoConfigurationMessageClosedGroup) -> ClosedGroup? {
            guard let publicKey = proto.publicKey?.toHexString(),
                let name = proto.name,
                let encryptionKeyPairAsProto = proto.encryptionKeyPair else { return nil }
            let encryptionKeyPair: ECKeyPair
            do {
                encryptionKeyPair = try ECKeyPair(publicKeyData: encryptionKeyPairAsProto.publicKey, privateKeyData: encryptionKeyPairAsProto.privateKey)
            } catch {
                SNLog("Couldn't construct closed group from proto: \(self).")
                return nil
            }
            let members = Set(proto.members.map { $0.toHexString() })
            let admins = Set(proto.admins.map { $0.toHexString() })
            return ClosedGroup(publicKey: publicKey, name: name, encryptionKeyPair: encryptionKeyPair, members: members, admins: admins)
        }

        public func toProto() -> SNProtoConfigurationMessageClosedGroup? {
            let result = SNProtoConfigurationMessageClosedGroup.builder()
            result.setPublicKey(Data(hex: publicKey))
            result.setName(name)
            do {
                let encryptionKeyPairAsProto = try SNProtoKeyPair.builder(publicKey: encryptionKeyPair.publicKey, privateKey: encryptionKeyPair.privateKey).build()
                result.setEncryptionKeyPair(encryptionKeyPairAsProto)
            } catch {
                SNLog("Couldn't construct closed group proto from: \(self).")
                return nil
            }
            result.setMembers(members.map { Data(hex: $0) })
            result.setAdmins(admins.map { Data(hex: $0) })
            do {
                return try result.build()
            } catch {
                SNLog("Couldn't construct closed group proto from: \(self).")
                return nil
            }
        }

        public override var description: String { name }
    }
}
