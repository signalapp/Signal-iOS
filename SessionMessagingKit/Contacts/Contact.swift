
@objc(SNContact)
public class Contact : NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    public let sessionID: String
    /// The display name of the contact.
    ///
    /// - Note: In open groups use `openGroupDisplayName`.
    public var displayName: String?
    /// The URL from which to fetch the contact's profile picture.
    public var profilePictureURL: String?
    /// The file name of the contact's profile picture on local storage.
    public var profilePictureFileName: String?
    /// The key with which the profile picture is encrypted.
    public var profilePictureEncryptionKey: OWSAES256Key?
    /// The ID of the thread associated with this contact.
    public var threadID: String?
    
    /// In open groups, where it's more likely that multiple users have the same name, we display a bit of the Session ID after
    /// a user's display name for added context.
    public var openGroupDisplayName: String? {
        guard let displayName = displayName else { return nil }
        let endIndex = sessionID.endIndex
        let cutoffIndex = sessionID.index(endIndex, offsetBy: -8)
        return "\(displayName) (...\(sessionID[cutoffIndex..<endIndex]))"
    }
    
    // MARK: Initialization
    public init(sessionID: String) {
        self.sessionID = sessionID
        super.init()
    }

    private override init() { preconditionFailure("Use init(sessionID:) instead.") }

    // MARK: Validation
    public var isValid: Bool {
        if profilePictureURL != nil { return (profilePictureEncryptionKey != nil) }
        if profilePictureEncryptionKey != nil { return (profilePictureURL != nil) }
        return true
    }
    
    // MARK: Coding
    public required init?(coder: NSCoder) {
        guard let sessionID = coder.decodeObject(forKey: "sessionID") as! String? else { return nil }
        self.sessionID = sessionID
        if let displayName = coder.decodeObject(forKey: "displayName") as! String? { self.displayName = displayName }
        if let profilePictureURL = coder.decodeObject(forKey: "profilePictureURL") as! String? { self.profilePictureURL = profilePictureURL }
        if let profilePictureFileName = coder.decodeObject(forKey: "profilePictureFileName") as! String? { self.profilePictureFileName = profilePictureFileName }
        if let profilePictureEncryptionKey = coder.decodeObject(forKey: "profilePictureEncryptionKey") as! OWSAES256Key? { self.profilePictureEncryptionKey = profilePictureEncryptionKey }
        if let threadID = coder.decodeObject(forKey: "threadID") as! String? { self.threadID = threadID }
    }

    public func encode(with coder: NSCoder) {
        coder.encode(sessionID, forKey: "sessionID")
        coder.encode(displayName, forKey: "displayName")
        coder.encode(profilePictureURL, forKey: "profilePictureURL")
        coder.encode(profilePictureFileName, forKey: "profilePictureFileName")
        coder.encode(profilePictureEncryptionKey, forKey: "profilePictureEncryptionKey")
        coder.encode(threadID, forKey: "threadID")
    }
    
    // MARK: Equality
    override public func isEqual(_ other: Any?) -> Bool {
        guard let other = other as? Contact else { return false }
        return sessionID == other.sessionID
    }

    // MARK: Hashing
    override public var hash: Int { // Override NSObject.hash and not Hashable.hashValue or Hashable.hash(into:)
        return sessionID.hash
    }

    // MARK: Description
    override public var description: String {
        if let displayName = displayName {
            return displayName
        } else {
            return sessionID
        }
    }
}
