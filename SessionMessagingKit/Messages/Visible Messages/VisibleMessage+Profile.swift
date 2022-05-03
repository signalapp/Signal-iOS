// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

public extension VisibleMessage {
    struct Profile: Codable {
        public let displayName: String?
        public let profileKey: Data?
        public let profilePictureUrl: String?

        internal init(displayName: String, profileKey: Data? = nil, profilePictureUrl: String? = nil) {
            self.displayName = displayName
            self.profileKey = profileKey
            self.profilePictureUrl = profilePictureUrl
        }

        // MARK: - Proto Conversion

        public static func fromProto(_ proto: SNProtoDataMessage) -> Profile? {
            guard
                let profileProto = proto.profile,
                let displayName = profileProto.displayName
            else { return nil }
            
            return Profile(
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
            let profileProto = SNProtoDataMessageLokiProfile.builder()
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
