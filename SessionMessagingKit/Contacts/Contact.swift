
@objc(SNContact)
public class Contact : NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
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
    @objc public var isBlocked = false
    /// This flag is used to determine whether this contact has approved the current users message request
    @objc public var didApproveMe = false
    
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
        
        isApproved = coder.decodeBool(forKey: "isApproved")
        isBlocked = coder.decodeBool(forKey: "isBlocked")
        didApproveMe = coder.decodeBool(forKey: "didApproveMe")
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
    
    // MARK: Convenience
    @objc(contextForThread:)
    public static func context(for thread: TSThread) -> Context {
        return ((thread as? TSGroupThread)?.isOpenGroup == true) ? .openGroup : .regular
    }
}
