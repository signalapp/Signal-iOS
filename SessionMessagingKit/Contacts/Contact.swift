
@objc(SNContact)
public class Contact : NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
    @objc public let sessionID: String
    /// The name of the contact.
    ///
    /// - Note: In open groups use `openGroupDisplayName`.
    @objc public var name: String?
    /// The contact's nickname.
    @objc public var nickname: String?
    /// The URL from which to fetch the contact's profile picture.
    @objc public var profilePictureURL: String?
    /// The file name of the contact's profile picture on local storage.
    @objc public var profilePictureFileName: String?
    /// The key with which the profile picture is encrypted.
    @objc public var profilePictureEncryptionKey: OWSAES256Key?
    /// The ID of the thread associated with this contact.
    @objc public var threadID: String?
    
    /// In open groups, where it's more likely that multiple users have the same name, we display a bit of the Session ID after
    /// a user's display name for added context.
    @objc public var openGroupDisplayName: String? {
        guard let name = name else { return nil }
        let endIndex = sessionID.endIndex
        let cutoffIndex = sessionID.index(endIndex, offsetBy: -8)
        return "\(name) (...\(sessionID[cutoffIndex..<endIndex]))"
    }
    
    @objc public func displayName(for context: Context) -> String? {
        if let nickname = nickname { return nickname }
        switch context {
        case .regular: return name
        case .openGroup: return openGroupDisplayName
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
        if profilePictureURL != nil { return (profilePictureEncryptionKey != nil) }
        if profilePictureEncryptionKey != nil { return (profilePictureURL != nil) }
        return true
    }
    
    // MARK: Coding
    public required init?(coder: NSCoder) {
        guard let sessionID = coder.decodeObject(forKey: "sessionID") as! String? else { return nil }
        self.sessionID = sessionID
        if let name = coder.decodeObject(forKey: "displayName") as! String? { self.name = name }
        if let nickname = coder.decodeObject(forKey: "nickname") as! String? { self.nickname = nickname }
        if let profilePictureURL = coder.decodeObject(forKey: "profilePictureURL") as! String? { self.profilePictureURL = profilePictureURL }
        if let profilePictureFileName = coder.decodeObject(forKey: "profilePictureFileName") as! String? { self.profilePictureFileName = profilePictureFileName }
        if let profilePictureEncryptionKey = coder.decodeObject(forKey: "profilePictureEncryptionKey") as! OWSAES256Key? { self.profilePictureEncryptionKey = profilePictureEncryptionKey }
        if let threadID = coder.decodeObject(forKey: "threadID") as! String? { self.threadID = threadID }
    }

    public func encode(with coder: NSCoder) {
        coder.encode(sessionID, forKey: "sessionID")
        coder.encode(name, forKey: "displayName")
        coder.encode(nickname, forKey: "nickname")
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
        nickname ?? name ?? sessionID
    }
}
