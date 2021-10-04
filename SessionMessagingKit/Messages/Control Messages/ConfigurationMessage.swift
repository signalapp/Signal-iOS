import SessionUtilitiesKit

@objc(SNConfigurationMessage)
public final class ConfigurationMessage : ControlMessage {
    public var closedGroups: Set<ClosedGroup> = []
    public var openGroups: Set<String> = []
    public var displayName: String?
    public var profilePictureURL: String?
    public var profileKey: Data?
    public var contacts: Set<Contact> = []

    public override var isSelfSendValid: Bool { true }
    
    // MARK: Initialization
    public override init() { super.init() }

    public init(displayName: String?, profilePictureURL: String?, profileKey: Data?, closedGroups: Set<ClosedGroup>, openGroups: Set<String>, contacts: Set<Contact>) {
        super.init()
        self.displayName = displayName
        self.profilePictureURL = profilePictureURL
        self.profileKey = profileKey
        self.closedGroups = closedGroups
        self.openGroups = openGroups
        self.contacts = contacts
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let closedGroups = coder.decodeObject(forKey: "closedGroups") as! Set<ClosedGroup>? { self.closedGroups = closedGroups }
        if let openGroups = coder.decodeObject(forKey: "openGroups") as! Set<String>? { self.openGroups = openGroups }
        if let displayName = coder.decodeObject(forKey: "displayName") as! String? { self.displayName = displayName }
        if let profilePictureURL = coder.decodeObject(forKey: "profilePictureURL") as! String? { self.profilePictureURL = profilePictureURL }
        if let profileKey = coder.decodeObject(forKey: "profileKey") as! Data? { self.profileKey = profileKey }
        if let contacts = coder.decodeObject(forKey: "contacts") as! Set<Contact>? { self.contacts = contacts }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(closedGroups, forKey: "closedGroups")
        coder.encode(openGroups, forKey: "openGroups")
        coder.encode(displayName, forKey: "displayName")
        coder.encode(profilePictureURL, forKey: "profilePictureURL")
        coder.encode(profileKey, forKey: "profileKey")
        coder.encode(contacts, forKey: "contacts")
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> ConfigurationMessage? {
        guard let configurationProto = proto.configurationMessage else { return nil }
        let displayName = configurationProto.displayName
        let profilePictureURL = configurationProto.profilePicture
        let profileKey = configurationProto.profileKey
        let closedGroups = Set(configurationProto.closedGroups.compactMap { ClosedGroup.fromProto($0) })
        let openGroups = Set(configurationProto.openGroups)
        let contacts = Set(configurationProto.contacts.compactMap { Contact.fromProto($0) })
        return ConfigurationMessage(displayName: displayName, profilePictureURL: profilePictureURL, profileKey: profileKey,
            closedGroups: closedGroups, openGroups: openGroups, contacts: contacts)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        let configurationProto = SNProtoConfigurationMessage.builder()
        if let displayName = displayName { configurationProto.setDisplayName(displayName) }
        if let profilePictureURL = profilePictureURL { configurationProto.setProfilePicture(profilePictureURL) }
        if let profileKey = profileKey { configurationProto.setProfileKey(profileKey) }
        configurationProto.setClosedGroups(closedGroups.compactMap { $0.toProto() })
        configurationProto.setOpenGroups([String](openGroups))
        configurationProto.setContacts(contacts.compactMap { $0.toProto() })
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
            closedGroups: \([ClosedGroup](closedGroups).prettifiedDescription),
            openGroups: \([String](openGroups).prettifiedDescription),
            displayName: \(displayName ?? "null"),
            profilePictureURL: \(profilePictureURL ?? "null"),
            profileKey: \(profileKey?.toHexString() ?? "null"),
            contacts: \([Contact](contacts).prettifiedDescription)
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
        public let expirationTimer: UInt32

        public var isValid: Bool { !members.isEmpty && !admins.isEmpty }

        public init(publicKey: String, name: String, encryptionKeyPair: ECKeyPair, members: Set<String>, admins: Set<String>, expirationTimer: UInt32) {
            self.publicKey = publicKey
            self.name = name
            self.encryptionKeyPair = encryptionKeyPair
            self.members = members
            self.admins = admins
            self.expirationTimer = expirationTimer
        }

        public required init?(coder: NSCoder) {
            guard let publicKey = coder.decodeObject(forKey: "publicKey") as! String?,
                let name = coder.decodeObject(forKey: "name") as! String?,
                let encryptionKeyPair = coder.decodeObject(forKey: "encryptionKeyPair") as! ECKeyPair?,
                let members = coder.decodeObject(forKey: "members") as! Set<String>?,
                let admins = coder.decodeObject(forKey: "admins") as! Set<String>? else { return nil }
                let expirationTimer = coder.decodeObject(forKey: "expirationTimer") as? UInt32 ?? 0
            self.publicKey = publicKey
            self.name = name
            self.encryptionKeyPair = encryptionKeyPair
            self.members = members
            self.admins = admins
            self.expirationTimer = expirationTimer
        }

        public func encode(with coder: NSCoder) {
            coder.encode(publicKey, forKey: "publicKey")
            coder.encode(name, forKey: "name")
            coder.encode(encryptionKeyPair, forKey: "encryptionKeyPair")
            coder.encode(members, forKey: "members")
            coder.encode(admins, forKey: "admins")
            coder.encode(expirationTimer, forKey: "expirationTimer")
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
            let expirationTimer = proto.expirationTimer
            let result = ClosedGroup(publicKey: publicKey, name: name, encryptionKeyPair: encryptionKeyPair, members: members, admins: admins, expirationTimer: expirationTimer)
            guard result.isValid else { return nil }
            return result
        }

        public func toProto() -> SNProtoConfigurationMessageClosedGroup? {
            guard isValid else { return nil }
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
            result.setExpirationTimer(expirationTimer)
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

// MARK: Contact
extension ConfigurationMessage {

    @objc(SNConfigurationMessageContact)
    public final class Contact : NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
        public var publicKey: String?
        public var displayName: String?
        public var profilePictureURL: String?
        public var profileKey: Data?

        public var isValid: Bool { publicKey != nil && displayName != nil }

        public init(publicKey: String, displayName: String, profilePictureURL: String?, profileKey: Data?) {
            self.publicKey = publicKey
            self.displayName = displayName
            self.profilePictureURL = profilePictureURL
            self.profileKey = profileKey
        }

        public required init?(coder: NSCoder) {
            guard let publicKey = coder.decodeObject(forKey: "publicKey") as! String?,
                let displayName = coder.decodeObject(forKey: "displayName") as! String? else { return nil }
            self.publicKey = publicKey
            self.displayName = displayName
            self.profilePictureURL = coder.decodeObject(forKey: "profilePictureURL") as! String?
            self.profileKey = coder.decodeObject(forKey: "profileKey") as! Data?
        }

        public func encode(with coder: NSCoder) {
            coder.encode(publicKey, forKey: "publicKey")
            coder.encode(displayName, forKey: "displayName")
            coder.encode(profilePictureURL, forKey: "profilePictureURL")
            coder.encode(profileKey, forKey: "profileKey")
        }

        public static func fromProto(_ proto: SNProtoConfigurationMessageContact) -> Contact? {
            let publicKey = proto.publicKey.toHexString()
            let displayName = proto.name
            let profilePictureURL = proto.profilePicture
            let profileKey = proto.profileKey
            let result = Contact(publicKey: publicKey, displayName: displayName, profilePictureURL: profilePictureURL, profileKey: profileKey)
            guard result.isValid else { return nil }
            return result
        }

        public func toProto() -> SNProtoConfigurationMessageContact? {
            guard isValid else { return nil }
            guard let publicKey = publicKey, let displayName = displayName else { return nil }
            let result = SNProtoConfigurationMessageContact.builder(publicKey: Data(hex: publicKey), name: displayName)
            if let profilePictureURL = profilePictureURL { result.setProfilePicture(profilePictureURL) }
            if let profileKey = profileKey { result.setProfileKey(profileKey) }
            do {
                return try result.build()
            } catch {
                SNLog("Couldn't construct contact proto from: \(self).")
                return nil
            }
        }

        public override var description: String { displayName ?? "" }
    }
}
