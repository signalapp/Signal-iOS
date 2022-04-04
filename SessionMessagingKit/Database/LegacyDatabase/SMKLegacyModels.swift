// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum Legacy {
    // MARK: - Collections and Keys
    
    internal static let contactThreadPrefix = "c"
    internal static let threadCollection = "TSThread"
    internal static let contactCollection = "LokiContactCollection"
    
    // MARK: - Types
    
    public typealias Contact = _LegacyContact

    @objc(SNProfile)
    public class Profile: NSObject, NSCoding {
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

// Note: Looks like Swift doesn't expose nested types well (in the `-Swift` header this was
// appearing with `SWIFT_CLASS_NAME("Contact")` which conflicts with the new type and has a
// different structure) as a result we cannot nest this cleanly
@objc(SNContact)
public class _LegacyContact: NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    @objc public let sessionID: String
    /// The URL from which to fetch the contact's profile picture.
    @objc public var profilePictureURL: String?
    /// The file name of the contact's profile picture on local storage.
    @objc public var profilePictureFileName: String?
    /// The key with which the profile is encrypted.
    @objc public var profileEncryptionKey: OWSAES256Key?
    /// The ID of the thread associated with this contact.
    @objc public var threadID: String?
    /// This flag is used to determine whether we should auto-download files sent by this contact.
    @objc public var isTrusted = false
    /// This flag is used to determine whether message requests from this contact are approved
    @objc public var isApproved = false
    /// This flag is used to determine whether message requests from this contact are blocked
    @objc public var isBlocked = false {
        didSet {
            if isBlocked {
                hasBeenBlocked = true
            }
        }
    }
    /// This flag is used to determine whether this contact has approved the current users message request
    @objc public var didApproveMe = false
    /// This flag is used to determine whether this contact has ever been blocked (will be included in the config message if so)
    @objc public var hasBeenBlocked = false
    
    // MARK: Name
    /// The name of the contact. Use this whenever you need the "real", underlying name of a user (e.g. when sending a message).
    @objc public var name: String?
    /// The contact's nickname, if the user set one.
    @objc public var nickname: String?
    /// The name to display in the UI. For local use only.
    @objc public func displayName(for context: Context) -> String? {
        if let nickname = nickname { return nickname }
        switch context {
        case .regular: return name
        case .openGroup:
            // In open groups, where it's more likely that multiple users have the same name, we display a bit of the Session ID after
            // a user's display name for added context.
            guard let name = name else { return nil }
            let endIndex = sessionID.endIndex
            let cutoffIndex = sessionID.index(endIndex, offsetBy: -8)
            return "\(name) (...\(sessionID[cutoffIndex..<endIndex]))"
        }
    }
    
    // MARK: Context
    @objc(SNContactContext)
    public enum Context : Int {
        case regular, openGroup
    }
    
    // MARK: Initialization
    @objc public init(sessionID: String) {
        self.sessionID = sessionID
        super.init()
    }

    private override init() { preconditionFailure("Use init(sessionID:) instead.") }

    // MARK: Validation
    public var isValid: Bool {
        if profilePictureURL != nil { return (profileEncryptionKey != nil) }
        if profileEncryptionKey != nil { return (profilePictureURL != nil) }
        return true
    }
    
    // MARK: Coding
    
    public required init?(coder: NSCoder) {
        guard let sessionID = coder.decodeObject(forKey: "sessionID") as! String? else { return nil }
        self.sessionID = sessionID
        isTrusted = coder.decodeBool(forKey: "isTrusted")
        if let name = coder.decodeObject(forKey: "displayName") as! String? { self.name = name }
        if let nickname = coder.decodeObject(forKey: "nickname") as! String? { self.nickname = nickname }
        if let profilePictureURL = coder.decodeObject(forKey: "profilePictureURL") as! String? { self.profilePictureURL = profilePictureURL }
        if let profilePictureFileName = coder.decodeObject(forKey: "profilePictureFileName") as! String? { self.profilePictureFileName = profilePictureFileName }
        if let profileEncryptionKey = coder.decodeObject(forKey: "profilePictureEncryptionKey") as! OWSAES256Key? { self.profileEncryptionKey = profileEncryptionKey }
        if let threadID = coder.decodeObject(forKey: "threadID") as! String? { self.threadID = threadID }
        
        let isBlockedFlag: Bool = coder.decodeBool(forKey: "isBlocked")
        isApproved = coder.decodeBool(forKey: "isApproved")
        isBlocked = isBlockedFlag
        didApproveMe = coder.decodeBool(forKey: "didApproveMe")
        hasBeenBlocked = (coder.decodeBool(forKey: "hasBeenBlocked") || isBlockedFlag)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(sessionID, forKey: "sessionID")
        coder.encode(name, forKey: "displayName")
        coder.encode(nickname, forKey: "nickname")
        coder.encode(profilePictureURL, forKey: "profilePictureURL")
        coder.encode(profilePictureFileName, forKey: "profilePictureFileName")
        coder.encode(profileEncryptionKey, forKey: "profilePictureEncryptionKey")
        coder.encode(threadID, forKey: "threadID")
        coder.encode(isTrusted, forKey: "isTrusted")
        coder.encode(isApproved, forKey: "isApproved")
        coder.encode(isBlocked, forKey: "isBlocked")
        coder.encode(didApproveMe, forKey: "didApproveMe")
        coder.encode(hasBeenBlocked, forKey: "hasBeenBlocked")
    }
    
    // MARK: Equality
    override public func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? _LegacyContact else { return false }
        return sessionID == other.sessionID
    }

    // MARK: Hashing
    override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
        return sessionID.hash
    }

    // MARK: Description
    override public var description: String {
        nickname ?? name ?? sessionID
    }
    
    // MARK: Convenience
    @objc(contextForThread:)
    public static func context(for thread: TSThread) -> Context {
        return ((thread as? TSGroupThread)?.isOpenGroup == true) ? .openGroup : .regular
    }
}
