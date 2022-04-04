// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Profile: Codable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible, CustomStringConvertible {
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
    public var name: String
    
    /// A custom name for the profile set by the current user
    public var nickname: String?

    /// The URL from which to fetch the contact's profile picture.
    public var profilePictureUrl: String?

    /// The file name of the contact's profile picture on local storage.
    public var profilePictureFileName: String?

    /// The key with which the profile is encrypted.
    public var profileEncryptionKey: OWSAES256Key?
    
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
    // MARK: - Context
    
    enum Context: Int {
        case regular
        case openGroup
    }

    /// The name to display in the UI. For local use only.
    func displayName(for context: Context) -> String? {
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
