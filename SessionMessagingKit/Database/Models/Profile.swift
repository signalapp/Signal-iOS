// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SignalCoreKit
import SessionUtilitiesKit

public struct Profile: Codable, Identifiable, Equatable, Hashable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible, CustomStringConvertible, Differentiable {
    public static var databaseTableName: String { "profile" }
    internal static let interactionForeignKey = ForeignKey([Columns.id], to: [Interaction.Columns.authorId])
    internal static let contactForeignKey = ForeignKey([Columns.id], to: [Contact.Columns.id])
    internal static let groupMemberForeignKey = ForeignKey([Columns.id], to: [GroupMember.Columns.profileId])
    internal static let contact = hasOne(Contact.self, using: contactForeignKey)
    public static let groupMembers = hasMany(GroupMember.self, using: groupMemberForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        
        case name
        case nickname
        
        case profilePictureUrl
        case profilePictureFileName
        case profileEncryptionKey
    }

    /// The id for the user that owns the profile (Note: This could be a sessionId, a blindedId or some future variant)
    public let id: String
    
    /// The name of the contact. Use this whenever you need the "real", underlying name of a user (e.g. when sending a message).
    public let name: String
    
    /// A custom name for the profile set by the current user
    public let nickname: String?

    /// The URL from which to fetch the contact's profile picture.
    public let profilePictureUrl: String?

    /// The file name of the contact's profile picture on local storage.
    public let profilePictureFileName: String?

    /// The key with which the profile is encrypted.
    public let profileEncryptionKey: OWSAES256Key?
    
    // MARK: - Initialization
    
    public init(
        id: String,
        name: String,
        nickname: String? = nil,
        profilePictureUrl: String? = nil,
        profilePictureFileName: String? = nil,
        profileEncryptionKey: OWSAES256Key? = nil
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.profilePictureUrl = profilePictureUrl
        self.profilePictureFileName = profilePictureFileName
        self.profileEncryptionKey = profileEncryptionKey
    }
    
    // MARK: - Description
    
    public var description: String {
        """
        Profile(
            name: \(name),
            profileKey: \(profileEncryptionKey?.keyData.description ?? "null"),
            profilePictureUrl: \(profilePictureUrl ?? "null")
        )
        """
    }
}

// MARK: - Codable

public extension Profile {
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        var profileKey: OWSAES256Key?
        var profilePictureUrl: String?
        
        // If we have both a `profileKey` and a `profilePicture` then the key MUST be valid
        if
            let profileKeyData: Data = try? container.decode(Data.self, forKey: .profileEncryptionKey),
            let profilePictureUrlValue: String = try? container.decode(String.self, forKey: .profilePictureUrl)
        {
            guard let validProfileKey: OWSAES256Key = OWSAES256Key(data: profileKeyData) else {
                owsFailDebug("Failed to make profile key for key data")
                throw StorageError.decodingFailed
            }
            
            profileKey = validProfileKey
            profilePictureUrl = profilePictureUrlValue
        }
        
        self = Profile(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            nickname: try? container.decode(String.self, forKey: .nickname),
            profilePictureUrl: profilePictureUrl,
            profilePictureFileName: try? container.decode(String.self, forKey: .profilePictureFileName),
            profileEncryptionKey: profileKey
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(nickname, forKey: .nickname)
        try container.encode(profilePictureUrl, forKey: .profilePictureUrl)
        try container.encode(profilePictureFileName, forKey: .profilePictureFileName)
        try container.encode(profileEncryptionKey?.keyData, forKey: .profileEncryptionKey)
    }
}

// MARK: - Protobuf

public extension Profile {
    static func fromProto(_ proto: SNProtoDataMessage, id: String) -> Profile? {
        guard let profileProto = proto.profile, let displayName = profileProto.displayName else { return nil }
        
        var profileKey: OWSAES256Key?
        var profilePictureUrl: String?
        
        // If we have both a `profileKey` and a `profilePicture` then the key MUST be valid
        if let profileKeyData: Data = proto.profileKey, profileProto.profilePicture != nil {
            guard let validProfileKey: OWSAES256Key = OWSAES256Key(data: profileKeyData) else {
                owsFailDebug("Failed to make profile key for key data")
                return nil
            }
            
            profileKey = validProfileKey
            profilePictureUrl = profileProto.profilePicture
        }
        
        return Profile(
            id: id,
            name: displayName,
            nickname: nil,
            profilePictureUrl: profilePictureUrl,
            profilePictureFileName: nil,
            profileEncryptionKey: profileKey
        )
    }

    func toProto() -> SNProtoDataMessage? {
        let dataMessageProto = SNProtoDataMessage.builder()
        let profileProto = SNProtoDataMessageLokiProfile.builder()
        profileProto.setDisplayName(name)
        
        if let profileKey: OWSAES256Key = profileEncryptionKey, let profilePictureUrl: String = profilePictureUrl {
            dataMessageProto.setProfileKey(profileKey.keyData)
            profileProto.setProfilePicture(profilePictureUrl)
        }
        
        do {
            dataMessageProto.setProfile(try profileProto.build())
            return try dataMessageProto.build()
        }
        catch {
            SNLog("Couldn't construct profile proto from: \(self).")
            return nil
        }
    }
}

// MARK: - Mutation

public extension Profile {
    func with(
        name: String? = nil,
        profilePictureUrl: Updatable<String?> = .existing,
        profilePictureFileName: Updatable<String?> = .existing,
        profileEncryptionKey: Updatable<OWSAES256Key> = .existing
    ) -> Profile {
        return Profile(
            id: id,
            name: (name ?? self.name),
            nickname: self.nickname,
            profilePictureUrl: (profilePictureUrl ?? self.profilePictureUrl),
            profilePictureFileName: (profilePictureFileName ?? self.profilePictureFileName),
            profileEncryptionKey: (profileEncryptionKey ?? self.profileEncryptionKey)
        )
    }
}

// MARK: - GRDB Interactions

public extension Profile {
    static func allContactProfiles(excluding idsToExclude: Set<String> = []) -> QueryInterfaceRequest<Profile> {
        return Profile
            .filter(!idsToExclude.contains(Profile.Columns.id))
            .joining(
                required: Profile.contact
                    .filter(Contact.Columns.isApproved == true)
                    .filter(Contact.Columns.didApproveMe == true)
            )
    }
    
    static func fetchAllContactProfiles(excluding: Set<String> = [], excludeCurrentUser: Bool = true) -> [Profile] {
        return Storage.shared
            .read { db in
                // Sort the contacts by their displayName value
                try Profile
                    .allContactProfiles(
                        excluding: excluding
                            .inserting(excludeCurrentUser ? getUserHexEncodedPublicKey(db) : nil)
                    )
                    .fetchAll(db)
                    .sorted(by: { lhs, rhs -> Bool in lhs.displayName() < rhs.displayName() })
            }
            .defaulting(to: [])
    }
    
    static func displayName(_ db: Database? = nil, id: ID, threadVariant: SessionThread.Variant = .contact, customFallback: String? = nil) -> String {
        guard let db: Database = db else {
            return Storage.shared
                .read { db in displayName(db, id: id, threadVariant: threadVariant, customFallback: customFallback) }
                .defaulting(to: (customFallback ?? id))
        }
        
        let existingDisplayName: String? = (try? Profile.fetchOne(db, id: id))?
            .displayName(for: threadVariant)
        
        return (existingDisplayName ?? (customFallback ?? id))
    }
    
    static func displayNameNoFallback(_ db: Database? = nil, id: ID, threadVariant: SessionThread.Variant = .contact) -> String? {
        guard let db: Database = db else {
            return Storage.shared.read { db in displayNameNoFallback(db, id: id, threadVariant: threadVariant) }
        }
        
        return (try? Profile.fetchOne(db, id: id))?
            .displayName(for: threadVariant)
    }
    
    // MARK: - Fetch or Create
    
    private static func defaultFor(_ id: String) -> Profile {
        return Profile(
            id: id,
            name: "",
            nickname: nil,
            profilePictureUrl: nil,
            profilePictureFileName: nil,
            profileEncryptionKey: nil
        )
    }
    
    /// Fetches or creates a Profile for the current user
    ///
    /// **Note:** This method intentionally does **not** save the newly created Profile,
    /// it will need to be explicitly saved after calling
    static func fetchOrCreateCurrentUser() -> Profile {
        var userPublicKey: String = ""
        
        let exisingProfile: Profile? = Storage.shared.read { db in
            userPublicKey = getUserHexEncodedPublicKey(db)
            
            return try Profile.fetchOne(db, id: userPublicKey)
        }
        
        return (exisingProfile ?? defaultFor(userPublicKey))
    }
    
    /// Fetches or creates a Profile for the current user
    ///
    /// **Note:** This method intentionally does **not** save the newly created Profile,
    /// it will need to be explicitly saved after calling
    static func fetchOrCreateCurrentUser(_ db: Database) -> Profile {
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        
        return (
            (try? Profile.fetchOne(db, id: userPublicKey)) ??
            defaultFor(userPublicKey)
        )
    }
    
    /// Fetches or creates a Profile for the specified user
    ///
    /// **Note:** This method intentionally does **not** save the newly created Profile,
    /// it will need to be explicitly saved after calling
    static func fetchOrCreate(id: String) -> Profile {
        let exisingProfile: Profile? = Storage.shared.read { db in
            try Profile.fetchOne(db, id: id)
        }
        
        return (exisingProfile ?? defaultFor(id))
    }
    
    /// Fetches or creates a Profile for the specified user
    ///
    /// **Note:** This method intentionally does **not** save the newly created Profile,
    /// it will need to be explicitly saved after calling
    static func fetchOrCreate(_ db: Database, id: String) -> Profile {
        return (
            (try? Profile.fetchOne(db, id: id)) ??
            defaultFor(id)
        )
    }
}

// MARK: - Convenience

public extension Profile {
    // MARK: - Truncation
    
    enum Truncation {
        case start
        case middle
        case end
    }
    
    /// A standardised mechanism for truncating a user id for a given thread
    static func truncated(id: String, threadVariant: SessionThread.Variant) -> String {
        return truncated(id: id, truncating: .middle)
    }
    
    /// A standardised mechanism for truncating a user id
    static func truncated(id: String, truncating: Truncation) -> String {
        guard id.count > 8 else { return id }
        
        switch truncating {
            case .start: return "...\(id.suffix(8))"
            case .middle: return "\(id.prefix(4))...\(id.suffix(4))"
            case .end: return "\(id.prefix(8))..."
        }
    }
    
    /// The name to display in the UI for a given thread variant
    func displayName(for threadVariant: SessionThread.Variant = .contact) -> String {
        return Profile.displayName(for: threadVariant, id: id, name: name, nickname: nickname)
    }
    
    static func displayName(
        for threadVariant: SessionThread.Variant,
        id: String,
        name: String?,
        nickname: String?,
        customFallback: String? = nil
    ) -> String {
        if let nickname: String = nickname { return nickname }
        
        guard let name: String = name, name != id else {
            return (customFallback ?? Profile.truncated(id: id, threadVariant: threadVariant))
        }
        
        switch threadVariant {
            case .contact, .closedGroup: return name
                
            case .openGroup:
                // In open groups, where it's more likely that multiple users have the same name,
                // we display a bit of the Session ID after a user's display name for added context
                return "\(name) (\(Profile.truncated(id: id, truncating: .middle)))"
        }
    }
}

// MARK: - Objective-C Support

// FIXME: Remove when possible

@objc(SMKProfile)
public class SMKProfile: NSObject {
    @objc public static func displayName(id: String) -> String {
        return Profile.displayName(id: id)
    }
    
    @objc public static func displayName(id: String, customFallback: String) -> String {
        return Profile.displayName(id: id, customFallback: customFallback)
    }
    
    @objc(displayNameAfterSavingNickname:forProfileId:)
    public static func displayNameAfterSaving(nickname: String?, for profileId: String) -> String {
        return Storage.shared.write { db in
            let profile: Profile = Profile.fetchOrCreate(id: profileId)
            let targetNickname: String? = ((nickname ?? "").count > 0 ? nickname : nil)
            
            try Profile
                .filter(id: profile.id)
                .updateAll(db, Profile.Columns.nickname.set(to: targetNickname))
            
            return (targetNickname ?? profile.name)
        }
        .defaulting(to: "")
    }
}
