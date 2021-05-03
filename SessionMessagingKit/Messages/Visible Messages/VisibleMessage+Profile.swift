import SessionUtilitiesKit

public extension VisibleMessage {

    @objc(SNProfile)
    class Profile : NSObject, NSCoding {
        public var displayName: String?
        public var profileKey: Data?
        public var profilePictureURL: String?

        internal init(displayName: String, profileKey: Data? = nil, profilePictureURL: String? = nil) {
            self.displayName = displayName
            self.profileKey = profileKey
            self.profilePictureURL = profilePictureURL
        }

        public required init?(coder: NSCoder) {
            if let displayName = coder.decodeObject(forKey: "displayName") as! String? { self.displayName = displayName }
            if let profileKey = coder.decodeObject(forKey: "profileKey") as! Data? { self.profileKey = profileKey }
            if let profilePictureURL = coder.decodeObject(forKey: "profilePictureURL") as! String? { self.profilePictureURL = profilePictureURL }
        }

        public func encode(with coder: NSCoder) {
            coder.encode(displayName, forKey: "displayName")
            coder.encode(profileKey, forKey: "profileKey")
            coder.encode(profilePictureURL, forKey: "profilePictureURL")
        }

        public static func fromProto(_ proto: SNProtoDataMessage) -> Profile? {
            guard let profileProto = proto.profile, let displayName = profileProto.displayName else { return nil }
            let profileKey = proto.profileKey
            let profilePictureURL = profileProto.profilePicture
            if let profileKey = profileKey, let profilePictureURL = profilePictureURL {
                return Profile(displayName: displayName, profileKey: profileKey, profilePictureURL: profilePictureURL)
            } else {
                return Profile(displayName: displayName)
            }
        }

        public func toProto() -> SNProtoDataMessage? {
            guard let displayName = displayName else {
                SNLog("Couldn't construct profile proto from: \(self).")
                return nil
            }
            let dataMessageProto = SNProtoDataMessage.builder()
            let profileProto = SNProtoDataMessageLokiProfile.builder()
            profileProto.setDisplayName(displayName)
            if let profileKey = profileKey, let profilePictureURL = profilePictureURL {
                dataMessageProto.setProfileKey(profileKey)
                profileProto.setProfilePicture(profilePictureURL)
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
        public override var description: String {
            """
            Profile(
                displayName: \(displayName ?? "null"),
                profileKey: \(profileKey?.description ?? "null"),
                profilePictureURL: \(profilePictureURL ?? "null")
            )
            """
        }
    }
}
