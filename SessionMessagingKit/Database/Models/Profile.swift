// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SignalCoreKit
import SessionUtilitiesKit

public struct Profile: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible, CustomStringConvertible {
    public static var databaseTableName: String { "profile" }
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        
        case name = "displayName"
        case nickname
        
        case profilePictureUrl = "profilePictureURL"
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
    
    // MARK: - Description
    
    public var description: String {
        """
        Profile(
            displayName: \(name),
            profileKey: \(profileEncryptionKey?.keyData.description ?? "null"),
            profilePictureURL: \(profilePictureUrl ?? "null")
        )
        """
    }
    
    // MARK: - PersistableRecord
    
    public func save(_ db: Database) throws {
        let oldProfile: Profile? = try? Profile.fetchOne(db, id: id)
        
        try performSave(db)
        
        db.afterNextTransactionCommit { db in
            // Delete old profile picture if needed
            if let oldProfilePictureFileName: String = oldProfile?.profilePictureFileName, oldProfilePictureFileName != profilePictureFileName {
                let path: String = OWSUserProfile.profileAvatarFilepath(withFilename: oldProfilePictureFileName)
                DispatchQueue.global(qos: .default).async {
                    OWSFileSystem.deleteFileIfExists(path)
                }
            }
            NotificationCenter.default.post(name: .profileUpdated, object: id)
            
            if id == getUserHexEncodedPublicKey(db) {
                NotificationCenter.default.post(name: .localProfileDidChange, object: nil)
            }
            else {
                let userInfo = [ Notification.Key.profileRecipientId.rawValue: id ]
                NotificationCenter.default.post(name: .otherUsersProfileDidChange, object: nil, userInfo: userInfo)
            }
        }
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
                throw GRDBStorageError.decodingFailed
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

// MARK: - Convenience

public extension Profile {
    func with(
        name: String? = nil,
        nickname: Updatable<String> = .existing,
        profilePictureUrl: Updatable<String> = .existing,
        profilePictureFileName: Updatable<String> = .existing,
        profileEncryptionKey: Updatable<OWSAES256Key> = .existing
    ) -> Profile {
        return Profile(
            id: id,
            name: (name ?? self.name),
            nickname: (nickname ?? self.nickname),
            profilePictureUrl: (profilePictureUrl ?? self.profilePictureUrl),
            profilePictureFileName: (profilePictureFileName ?? self.profilePictureFileName),
            profileEncryptionKey: (profileEncryptionKey ?? self.profileEncryptionKey)
        )
    }
    
    // MARK: - Context
    
    @objc enum Context: Int {
        case regular
        case openGroup
    }

    /// The name to display in the UI. For local use only.
    func displayName(for context: Context = .regular) -> String {
        if let nickname: String = nickname { return nickname }
        
        switch context {
            case .regular: return name
                
            case .openGroup:
                // In open groups, where it's more likely that multiple users have the same name, we display a bit of the Session ID after
                // a user's display name for added context.
                let endIndex = id.endIndex
                let cutoffIndex = id.index(endIndex, offsetBy: -8)
                return "\(name) (...\(id[cutoffIndex..<endIndex]))"
            }
    }
}

// MARK: - GRDB Interactions

public extension Profile {
    static func displayName(for id: ID, thread: TSThread, customFallback: String? = nil) -> String {
        return displayName(
            for: id,
            context: ((thread as? TSGroupThread)?.isOpenGroup == true ? .openGroup : .regular),
            customFallback: customFallback
        )
    }
    
    static func displayName(for id: ID, context: Context = .regular, customFallback: String? = nil) -> String {
        let existingDisplayName: String? = GRDBStorage.shared
            .read { db in try Profile.fetchOne(db, id: id) }?
            .displayName(for: context)
        
        return (existingDisplayName ?? (customFallback ?? id))
    }
    
    static func displayNameNoFallback(for id: ID, thread: TSThread) -> String? {
        return displayName(
            for: id,
            context: ((thread as? TSGroupThread)?.isOpenGroup == true ? .openGroup : .regular)
        )
    }
    
    static func displayNameNoFallback(for id: ID, context: Context = .regular) -> String? {
        return GRDBStorage.shared
            .read { db in try Profile.fetchOne(db, id: id) }?
            .displayName(for: context)
    }
    
    // MARK: - Fetch or Create
    
    private static func defaultFor(_ id: String) -> Profile {
        return Profile(
            id: id,
            name: id,
            nickname: nil,
            profilePictureUrl: nil,
            profilePictureFileName: nil,
            profileEncryptionKey: nil
        )
    }
    
    static func fetchOrCreateCurrentUser() -> Profile {
        var userPublicKey: String = ""
        
        let exisingProfile: Profile? = GRDBStorage.shared.read { db in
            userPublicKey = getUserHexEncodedPublicKey(db)
            
            return try Profile.fetchOne(db, id: userPublicKey)
        }
        
        return (exisingProfile ?? defaultFor(userPublicKey))
    }
    
    static func fetchOrCreateCurrentUser(_ db: Database) -> Profile {
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        
        return (
            (try? Profile.fetchOne(db, id: userPublicKey)) ??
            defaultFor(userPublicKey)
        )
    }
    
    static func fetchOrCreate(id: String) -> Profile {
        let exisingProfile: Profile? = GRDBStorage.shared.read { db in
            try Profile.fetchOne(db, id: id)
        }
        
        return (exisingProfile ?? defaultFor(id))
    }
    
    static func fetchOrCreate(_ db: Database, id: String) -> Profile {
        return (
            (try? Profile.fetchOne(db, id: id)) ??
            defaultFor(id)
        )
    }
}

// MARK: - Objective-C Support
@objc(SMKProfile)
public class SMKProfile: NSObject {
    var id: String
    @objc var name: String
    @objc var nickname: String?
    
    init(id: String, name: String, nickname: String?) {
        self.id = id
        self.name = name
        self.nickname = nickname
    }
    
    @objc public static func fetchCurrentUserName() -> String {
        let existingProfile: Profile? = GRDBStorage.shared.read { db in
            Profile.fetchOrCreateCurrentUser(db)
        }
        
        return (existingProfile?.name ?? "")
    }
    
    @objc public static func fetchOrCreate(id: String) -> SMKProfile {
        let profile: Profile = Profile.fetchOrCreate(id: id)
        
        return SMKProfile(
            id: id,
            name: profile.name,
            nickname: profile.nickname
        )
    }
    
    @objc public static func saveProfile(_ profile: SMKProfile) {
        GRDBStorage.shared.write { db in
            try? Profile
                .fetchOrCreate(db, id: profile.id)
                .with(nickname: .updateTo(profile.nickname))
                .save(db)
        }
    }
    
    @objc public static func displayName(id: String) -> String {
        return Profile.displayName(for: id)
    }
    
    @objc public static func displayName(id: String, customFallback: String) -> String {
        return Profile.displayName(for: id, customFallback: customFallback)
    }
    
    @objc public static func displayName(id: String, context: Profile.Context = .regular) -> String {
        let existingProfile: Profile? = GRDBStorage.shared.read { db in
            Profile.fetchOrCreateCurrentUser(db)
        }
        
        return (existingProfile?.name ?? id)
    }
    
    @objc public static func displayName(id: String, thread: TSThread) -> String {
        return Profile.displayName(for: id, thread: thread)
    }
    
    @objc public static var localProfileKey: OWSAES256Key? {
        Profile.fetchOrCreateCurrentUser().profileEncryptionKey
    }
}
