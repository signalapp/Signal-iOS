// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

// MARK: - VisibleMessage.VMProfile

public extension VisibleMessage {
    struct VMProfile: Codable {
        public let displayName: String?
        public let profileKey: Data?
        public let profilePictureUrl: String?
        
        // MARK: - Initialization

        internal init(displayName: String, profileKey: Data? = nil, profilePictureUrl: String? = nil) {
            let hasUrlAndKey: Bool = (profileKey != nil && profilePictureUrl != nil)
            
            self.displayName = displayName
            self.profileKey = (hasUrlAndKey ? profileKey : nil)
            self.profilePictureUrl = (hasUrlAndKey ? profilePictureUrl : nil)
        }

        // MARK: - Proto Conversion

        public static func fromProto(_ proto: SNProtoDataMessage) -> VMProfile? {
            guard
                let profileProto = proto.profile,
                let displayName = profileProto.displayName
            else { return nil }
            
            return VMProfile(
                displayName: displayName,
                profileKey: proto.profileKey,
                profilePictureUrl: profileProto.profilePicture
            )
        }

        public func toProto() -> SNProtoDataMessage? {
            guard let displayName = displayName else {
                SNLog("Couldn't construct profile proto from: \(self).")
                return nil
            }
            let dataMessageProto = SNProtoDataMessage.builder()
            let profileProto = SNProtoLokiProfile.builder()
            profileProto.setDisplayName(displayName)
            
            if let profileKey = profileKey, let profilePictureUrl = profilePictureUrl {
                dataMessageProto.setProfileKey(profileKey)
                profileProto.setProfilePicture(profilePictureUrl)
            }
            do {
                dataMessageProto.setProfile(try profileProto.build())
                return try dataMessageProto.build()
            } catch {
                SNLog("Couldn't construct profile proto from: \(self).")
                return nil
            }
        }
        
        public static func fromProto(_ proto: SNProtoMessageRequestResponse) -> VMProfile? {
            guard
                let profileProto = proto.profile,
                let displayName = profileProto.displayName
            else { return nil }
            
            return VMProfile(
                displayName: displayName,
                profileKey: proto.profileKey,
                profilePictureUrl: profileProto.profilePicture
            )
        }
        
        public func toProto(isApproved: Bool) -> SNProtoMessageRequestResponse? {
            guard let displayName = displayName else {
                SNLog("Couldn't construct profile proto from: \(self).")
                return nil
            }
            let messageRequestResponseProto = SNProtoMessageRequestResponse.builder(
                isApproved: isApproved
            )
            let profileProto = SNProtoLokiProfile.builder()
            profileProto.setDisplayName(displayName)
            
            if let profileKey = profileKey, let profilePictureUrl = profilePictureUrl {
                messageRequestResponseProto.setProfileKey(profileKey)
                profileProto.setProfilePicture(profilePictureUrl)
            }
            do {
                messageRequestResponseProto.setProfile(try profileProto.build())
                return try messageRequestResponseProto.build()
            } catch {
                SNLog("Couldn't construct profile proto from: \(self).")
                return nil
            }
        }
        
        // MARK: Description
        
        public var description: String {
            """
            Profile(
                displayName: \(displayName ?? "null"),
                profileKey: \(profileKey?.description ?? "null"),
                profilePictureUrl: \(profilePictureUrl ?? "null")
            )
            """
        }
    }
}

// MARK: - Conversion

extension VisibleMessage.VMProfile {
    init(profile: Profile) {
        self.displayName = profile.name
        self.profileKey = profile.profileEncryptionKey?.keyData
        self.profilePictureUrl = profile.profilePictureUrl
    }
}

// MARK: - MessageWithProfile

public protocol MessageWithProfile {
    var profile: VisibleMessage.VMProfile? { get set }
}

extension VisibleMessage: MessageWithProfile {}
extension MessageRequestResponse: MessageWithProfile {}
