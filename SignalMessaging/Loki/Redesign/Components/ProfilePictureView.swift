
@objc(LKProfilePictureView)
public final class ProfilePictureView : UIView {
    private var imageViewWidthConstraint: NSLayoutConstraint!
    private var imageViewHeightConstraint: NSLayoutConstraint!
    private var additionalImageViewWidthConstraint: NSLayoutConstraint!
    private var additionalImageViewHeightConstraint: NSLayoutConstraint!
    private var hasTappableProfilePicture: Bool = false
    @objc public var size: CGFloat = 0 // Not an implicitly unwrapped optional due to Obj-C limitations
    @objc public var isRSSFeed = false
    @objc public var hexEncodedPublicKey: String!
    @objc public var additionalHexEncodedPublicKey: String?
    @objc public var openGroupProfilePicture: UIImage?
    
    // MARK: Components
    private lazy var imageView = getImageView()
    private lazy var additionalImageView = getImageView()
    
    // MARK: Lifecycle
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViewHierarchy()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        // Set up image view
        addSubview(imageView)
        imageView.pin(.leading, to: .leading, of: self)
        imageView.pin(.top, to: .top, of: self)
        let imageViewSize = CGFloat(Values.mediumProfilePictureSize)
        imageViewWidthConstraint = imageView.set(.width, to: imageViewSize)
        imageViewHeightConstraint = imageView.set(.height, to: imageViewSize)
        // Set up additional image view
        addSubview(additionalImageView)
        additionalImageView.pin(.trailing, to: .trailing, of: self)
        additionalImageView.pin(.bottom, to: .bottom, of: self)
        let additionalImageViewSize = CGFloat(Values.smallProfilePictureSize)
        additionalImageViewWidthConstraint = additionalImageView.set(.width, to: additionalImageViewSize)
        additionalImageViewHeightConstraint = additionalImageView.set(.height, to: additionalImageViewSize)
        additionalImageView.layer.cornerRadius = additionalImageViewSize / 2
    }
    
    // MARK: Updating
    @objc(updateForContact:)
    public func update(for publicKey: String) {
        openGroupProfilePicture = nil
        hexEncodedPublicKey = publicKey
        additionalHexEncodedPublicKey = nil
        isRSSFeed = false
        update()
    }

    @objc(updateForThread:)
    public func update(for thread: TSThread) {
        openGroupProfilePicture = nil
        if let thread = thread as? TSGroupThread {
            if thread.name() == "Loki Public Chat"
                || thread.name() == "Session Public Chat" { // Override the profile picture for the Loki Public Chat and the Session Public Chat
                hexEncodedPublicKey = ""
                isRSSFeed = true
            } else if let openGroupProfilePicture = thread.groupModel.groupImage { // An open group with a profile picture
                self.openGroupProfilePicture = openGroupProfilePicture
                isRSSFeed = false
                hasTappableProfilePicture = true
            } else if thread.groupModel.groupType == .openGroup
                || thread.groupModel.groupType == .rssFeed { // An open group without a profile picture or an RSS feed
                hexEncodedPublicKey = ""
                isRSSFeed = true
            } else { // A closed group
                var users = MentionsManager.userPublicKeyCache[thread.uniqueId!] ?? []
                users.remove(getUserHexEncodedPublicKey())
                var randomUsers = users.sorted() // Sort to provide a level of stability
                if users.count == 1 {
                    randomUsers.insert(getUserHexEncodedPublicKey(), at: 0) // Ensure the current user is at the back visually
                }
                hexEncodedPublicKey = randomUsers.count >= 1 ? randomUsers[0] : ""
                additionalHexEncodedPublicKey = randomUsers.count >= 2 ? randomUsers[1] : ""
                isRSSFeed = false
            }
            update()
        } else { // A one-to-one chat
            hasTappableProfilePicture = OWSProfileManager.shared().profileAvatar(forRecipientId: thread.contactIdentifier()!) != nil
            update(for: thread.contactIdentifier()!)
        }
    }

    @objc public func update() {
        AssertIsOnMainThread()
        func getProfilePicture(of size: CGFloat, for publicKey: String) -> UIImage? {
            guard !publicKey.isEmpty else { return nil }
            if let profilePicture = OWSProfileManager.shared().profileAvatar(forRecipientId: publicKey) {
                return profilePicture
            } else {
                let displayName = OWSProfileManager.shared().profileNameForRecipient(withID: publicKey) ?? publicKey
                return Identicon.generatePlaceholderIcon(seed: publicKey, text: displayName, size: size)
            }
        }
        let size: CGFloat
        if let additionalHexEncodedPublicKey = additionalHexEncodedPublicKey, !isRSSFeed, openGroupProfilePicture == nil {
            if self.size == 40 {
                size = 32
            } else if self.size == Values.largeProfilePictureSize {
                size = 56
            } else {
                size = Values.smallProfilePictureSize
            }
            imageViewWidthConstraint.constant = size
            imageViewHeightConstraint.constant = size
            additionalImageViewWidthConstraint.constant = size
            additionalImageViewHeightConstraint.constant = size
            additionalImageView.isHidden = false
            additionalImageView.image = getProfilePicture(of: size, for: additionalHexEncodedPublicKey)
        } else {
            size = self.size
            imageViewWidthConstraint.constant = size
            imageViewHeightConstraint.constant = size
            additionalImageView.isHidden = true
            additionalImageView.image = nil
        }
        guard hexEncodedPublicKey != nil || openGroupProfilePicture != nil else { return }
        imageView.image = isRSSFeed ? nil : (openGroupProfilePicture ?? getProfilePicture(of: size, for: hexEncodedPublicKey))
        imageView.backgroundColor = isRSSFeed ? UIColor(rgbHex: 0x353535) : Colors.unimportant
        imageView.layer.cornerRadius = size / 2
        additionalImageView.layer.cornerRadius = size / 2
        imageView.contentMode = isRSSFeed ? .center : .scaleAspectFit
        if isRSSFeed {
            switch size {
            case Values.smallProfilePictureSize..<Values.mediumProfilePictureSize: imageView.image = #imageLiteral(resourceName: "SessionWhite16")
            case Values.mediumProfilePictureSize..<Values.largeProfilePictureSize: imageView.image = #imageLiteral(resourceName: "SessionWhite24")
            default: imageView.image = #imageLiteral(resourceName: "SessionWhite40")
            }
        }
    }
    
    // MARK: Convenience
    private func getImageView() -> UIImageView {
        let result = UIImageView()
        result.layer.masksToBounds = true
        result.backgroundColor = Colors.unimportant
        result.layer.borderColor = Colors.text.withAlphaComponent(0.35).cgColor
        result.layer.borderWidth = Values.borderThickness
        result.contentMode = .scaleAspectFit
        return result
    }
    
    @objc public func getProfilePicture() -> UIImage? {
        return hasTappableProfilePicture ? imageView.image : nil
    }
}
