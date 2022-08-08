// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import GRDB
import Curve25519Kit
import SessionUtilitiesKit

public final class ConfigurationMessage: ControlMessage {
    private enum CodingKeys: String, CodingKey {
        case closedGroups
        case openGroups
        case displayName
        case profilePictureUrl
        case profileKey
        case contacts
    }
    
    public var closedGroups: Set<CMClosedGroup> = []
    public var openGroups: Set<String> = []
    public var displayName: String?
    public var profilePictureUrl: String?
    public var profileKey: Data?
    public var contacts: Set<CMContact> = []

    public override var isSelfSendValid: Bool { true }
    
    // MARK: - Initialization

    public init(
        displayName: String?,
        profilePictureUrl: String?,
        profileKey: Data?,
        closedGroups: Set<CMClosedGroup>,
        openGroups: Set<String>,
        contacts: Set<CMContact>
    ) {
        super.init()
        
        self.displayName = displayName
        self.profilePictureUrl = profilePictureUrl
        self.profileKey = profileKey
        self.closedGroups = closedGroups
        self.openGroups = openGroups
        self.contacts = contacts
    }
    
    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        closedGroups = ((try? container.decode(Set<CMClosedGroup>.self, forKey: .closedGroups)) ?? [])
        openGroups = ((try? container.decode(Set<String>.self, forKey: .openGroups)) ?? [])
        displayName = try? container.decode(String.self, forKey: .displayName)
        profilePictureUrl = try? container.decode(String.self, forKey: .profilePictureUrl)
        profileKey = try? container.decode(Data.self, forKey: .profileKey)
        contacts = ((try? container.decode(Set<CMContact>.self, forKey: .contacts)) ?? [])
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(closedGroups, forKey: .closedGroups)
        try container.encodeIfPresent(openGroups, forKey: .openGroups)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(profilePictureUrl, forKey: .profilePictureUrl)
        try container.encodeIfPresent(profileKey, forKey: .profileKey)
        try container.encodeIfPresent(contacts, forKey: .contacts)
    }

    // MARK: - Proto Conversion
    
    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> ConfigurationMessage? {
        guard let configurationProto = proto.configurationMessage else { return nil }
        let displayName = configurationProto.displayName
        let profilePictureUrl = configurationProto.profilePicture
        let profileKey = configurationProto.profileKey
        let closedGroups = Set(configurationProto.closedGroups.compactMap { CMClosedGroup.fromProto($0) })
        let openGroups = Set(configurationProto.openGroups)
        let contacts = Set(configurationProto.contacts.compactMap { CMContact.fromProto($0) })
        
        return ConfigurationMessage(
            displayName: displayName,
            profilePictureUrl: profilePictureUrl,
            profileKey: profileKey,
            closedGroups: closedGroups,
            openGroups: openGroups,
            contacts: contacts
        )
    }

    public override func toProto(_ db: Database) -> SNProtoContent? {
        let configurationProto = SNProtoConfigurationMessage.builder()
        if let displayName = displayName { configurationProto.setDisplayName(displayName) }
        if let profilePictureUrl = profilePictureUrl { configurationProto.setProfilePicture(profilePictureUrl) }
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

    // MARK: - Description
    
    public var description: String {
        """
        ConfigurationMessage(
            closedGroups: \([CMClosedGroup](closedGroups).prettifiedDescription),
            openGroups: \([String](openGroups).prettifiedDescription),
            displayName: \(displayName ?? "null"),
            profilePictureUrl: \(profilePictureUrl ?? "null"),
            profileKey: \(profileKey?.toHexString() ?? "null"),
            contacts: \([CMContact](contacts).prettifiedDescription)
        )
        """
    }
}

// MARK: - Closed Group

extension ConfigurationMessage {
    public struct CMClosedGroup: Codable, Hashable, CustomStringConvertible {
        private enum CodingKeys: String, CodingKey {
            case publicKey
            case name
            case encryptionKeyPublicKey
            case encryptionKeySecretKey
            case members
            case admins
            case expirationTimer
        }
        
        public let publicKey: String
        public let name: String
        public let encryptionKeyPublicKey: Data
        public let encryptionKeySecretKey: Data
        public let members: Set<String>
        public let admins: Set<String>
        public let expirationTimer: UInt32

        public var isValid: Bool { !members.isEmpty && !admins.isEmpty }
        
        // MARK: - Initialization
        
        public init(
            publicKey: String,
            name: String,
            encryptionKeyPublicKey: Data,
            encryptionKeySecretKey: Data,
            members: Set<String>,
            admins: Set<String>,
            expirationTimer: UInt32
        ) {
            self.publicKey = publicKey
            self.name = name
            self.encryptionKeyPublicKey = encryptionKeyPublicKey
            self.encryptionKeySecretKey = encryptionKeySecretKey
            self.members = members
            self.admins = admins
            self.expirationTimer = expirationTimer
        }

        // MARK: - Codable
        
        public init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            
            publicKey = try container.decode(String.self, forKey: .publicKey)
            name = try container.decode(String.self, forKey: .name)
            encryptionKeyPublicKey = try container.decode(Data.self, forKey: .encryptionKeyPublicKey)
            encryptionKeySecretKey = try container.decode(Data.self, forKey: .encryptionKeySecretKey)
            members = try container.decode(Set<String>.self, forKey: .members)
            admins = try container.decode(Set<String>.self, forKey: .admins)
            expirationTimer = try container.decode(UInt32.self, forKey: .expirationTimer)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(publicKey, forKey: .publicKey)
            try container.encode(name, forKey: .name)
            try container.encode(encryptionKeyPublicKey, forKey: .encryptionKeyPublicKey)
            try container.encode(encryptionKeySecretKey, forKey: .encryptionKeySecretKey)
            try container.encode(members, forKey: .members)
            try container.encode(admins, forKey: .admins)
            try container.encode(expirationTimer, forKey: .expirationTimer)
        }

        public static func fromProto(_ proto: SNProtoConfigurationMessageClosedGroup) -> CMClosedGroup? {
            guard
                let publicKey = proto.publicKey?.toHexString(),
                let name = proto.name,
                let encryptionKeyPairAsProto = proto.encryptionKeyPair
            else { return nil }
            
            let members = Set(proto.members.map { $0.toHexString() })
            let admins = Set(proto.admins.map { $0.toHexString() })
            let expirationTimer = proto.expirationTimer
            let result = CMClosedGroup(
                publicKey: publicKey,
                name: name,
                encryptionKeyPublicKey: encryptionKeyPairAsProto.publicKey,
                encryptionKeySecretKey: encryptionKeyPairAsProto.privateKey,
                members: members,
                admins: admins,
                expirationTimer: expirationTimer
            )
            
            guard result.isValid else { return nil }
            return result
        }

        public func toProto() -> SNProtoConfigurationMessageClosedGroup? {
            guard isValid else { return nil }
            let result = SNProtoConfigurationMessageClosedGroup.builder()
            result.setPublicKey(Data(hex: publicKey))
            result.setName(name)
            do {
                let encryptionKeyPairAsProto = try SNProtoKeyPair.builder(
                    publicKey: encryptionKeyPublicKey,
                    privateKey: encryptionKeySecretKey
                ).build()
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

        public var description: String { name }
    }
}

// MARK: - Contact

extension ConfigurationMessage {
    public struct CMContact: Codable, Hashable, CustomStringConvertible {
        private enum CodingKeys: String, CodingKey {
            case publicKey
            case displayName
            case profilePictureUrl
            case profileKey
            
            case hasIsApproved
            case isApproved
            case hasIsBlocked
            case isBlocked
            case hasDidApproveMe
            case didApproveMe
        }
        
        public var publicKey: String?
        public var displayName: String?
        public var profilePictureUrl: String?
        public var profileKey: Data?
        
        public var hasIsApproved: Bool
        public var isApproved: Bool
        public var hasIsBlocked: Bool
        public var isBlocked: Bool
        public var hasDidApproveMe: Bool
        public var didApproveMe: Bool

        public var isValid: Bool { publicKey != nil && displayName != nil }

        public init(
            publicKey: String?,
            displayName: String?,
            profilePictureUrl: String?,
            profileKey: Data?,
            hasIsApproved: Bool,
            isApproved: Bool,
            hasIsBlocked: Bool,
            isBlocked: Bool,
            hasDidApproveMe: Bool,
            didApproveMe: Bool
        ) {
            self.publicKey = publicKey
            self.displayName = displayName
            self.profilePictureUrl = profilePictureUrl
            self.profileKey = profileKey
            self.hasIsApproved = hasIsApproved
            self.isApproved = isApproved
            self.hasIsBlocked = hasIsBlocked
            self.isBlocked = isBlocked
            self.hasDidApproveMe = hasDidApproveMe
            self.didApproveMe = didApproveMe
        }
        
        // MARK: - Codable
        
        public init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            
            publicKey = try? container.decode(String.self, forKey: .publicKey)
            displayName = try? container.decode(String.self, forKey: .displayName)
            profilePictureUrl = try? container.decode(String.self, forKey: .profilePictureUrl)
            profileKey = try? container.decode(Data.self, forKey: .profileKey)
            
            hasIsApproved = try container.decode(Bool.self, forKey: .hasIsApproved)
            isApproved = try container.decode(Bool.self, forKey: .isApproved)
            hasIsBlocked = try container.decode(Bool.self, forKey: .hasIsBlocked)
            isBlocked = try container.decode(Bool.self, forKey: .isBlocked)
            hasDidApproveMe = try container.decode(Bool.self, forKey: .hasDidApproveMe)
            didApproveMe = try container.decode(Bool.self, forKey: .didApproveMe)
        }

        public static func fromProto(_ proto: SNProtoConfigurationMessageContact) -> CMContact? {
            let result: CMContact = CMContact(
                publicKey: proto.publicKey.toHexString(),
                displayName: proto.name,
                profilePictureUrl: proto.profilePicture,
                profileKey: proto.profileKey,
                hasIsApproved: proto.hasIsApproved,
                isApproved: proto.isApproved,
                hasIsBlocked: proto.hasIsBlocked,
                isBlocked: proto.isBlocked,
                hasDidApproveMe: proto.hasDidApproveMe,
                didApproveMe: proto.didApproveMe
            )
            
            guard result.isValid else { return nil }
            return result
        }

        public func toProto() -> SNProtoConfigurationMessageContact? {
            guard isValid else { return nil }
            guard let publicKey = publicKey, let displayName = displayName else { return nil }
            let result = SNProtoConfigurationMessageContact.builder(publicKey: Data(hex: publicKey), name: displayName)
            if let profilePictureUrl = profilePictureUrl { result.setProfilePicture(profilePictureUrl) }
            if let profileKey = profileKey { result.setProfileKey(profileKey) }
            
            if hasIsApproved { result.setIsApproved(isApproved) }
            if hasIsBlocked { result.setIsBlocked(isBlocked) }
            if hasDidApproveMe { result.setDidApproveMe(didApproveMe) }
            
            do {
                return try result.build()
            } catch {
                SNLog("Couldn't construct contact proto from: \(self).")
                return nil
            }
        }

        public var description: String { displayName ?? "" }
    }
}
