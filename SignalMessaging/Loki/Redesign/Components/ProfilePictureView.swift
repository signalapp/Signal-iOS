
@objc(LKProfilePictureView)
public final class ProfilePictureView : UIView {
    private var imageViewWidthConstraint: NSLayoutConstraint!
    private var imageViewHeightConstraint: NSLayoutConstraint!
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
        additionalImageView.set(.width, to: additionalImageViewSize)
        additionalImageView.set(.height, to: additionalImageViewSize)
        additionalImageView.layer.cornerRadius = additionalImageViewSize / 2
    }
    
    // MARK: Updating
    @objc(updateForThread:)
    public func update(for thread: TSThread) {
        openGroupProfilePicture = nil
        if thread.isGroupThread() {
            if thread.name() == "Loki Public Chat"
                || thread.name() == "Session Public Chat" { // Override the profile picture for the Loki Public Chat and the Session Public Chat
                hexEncodedPublicKey = ""
                isRSSFeed = true
            } else if let openGroupProfilePicture = (thread as! TSGroupThread).groupModel.groupImage { // An open group with a profile picture
                self.openGroupProfilePicture = openGroupProfilePicture
                isRSSFeed = false
            } else if (thread as! TSGroupThread).groupModel.groupType == .openGroup
                || (thread as! TSGroupThread).groupModel.groupType == .rssFeed { // An open group without a profile picture or an RSS feed
                hexEncodedPublicKey = ""
                isRSSFeed = true
            } else { // A closed group
                var users = MentionsManager.userPublicKeyCache[thread.uniqueId!] ?? []
                users.remove(getUserHexEncodedPublicKey())
                let randomUsers = users.sorted().prefix(2) // Sort to provide a level of stability
                hexEncodedPublicKey = randomUsers.count >= 1 ? randomUsers[0] : ""
                additionalHexEncodedPublicKey = randomUsers.count >= 2 ? randomUsers[1] : ""
                isRSSFeed = false
            }
        } else { // A one-on-one chat
            hexEncodedPublicKey = thread.contactIdentifier()!
            additionalHexEncodedPublicKey = nil
            isRSSFeed = false
        }
        update()
    }

    @objc public func update() {
        AssertIsOnMainThread()
        func getProfilePicture(of size: CGFloat, for hexEncodedPublicKey: String) -> UIImage? {
            guard !hexEncodedPublicKey.isEmpty else { return nil }
            return OWSProfileManager.shared().profileAvatar(forRecipientId: hexEncodedPublicKey) ?? Identicon.generatePlaceholderIcon(seed: hexEncodedPublicKey, text: OWSProfileManager.shared().profileNameForRecipient(withID: hexEncodedPublicKey) ?? hexEncodedPublicKey, size: size)
        }
        let size: CGFloat
        if let additionalHexEncodedPublicKey = additionalHexEncodedPublicKey, !isRSSFeed, openGroupProfilePicture == nil {
            size = Values.smallProfilePictureSize
            imageViewWidthConstraint.constant = size
            imageViewHeightConstraint.constant = size
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
        imageView.contentMode = isRSSFeed ? .center : .scaleAspectFit
        if isRSSFeed {
            imageView.image = (size == 45) ? #imageLiteral(resourceName: "SessionWhite24") : #imageLiteral(resourceName: "SessionWhite40")
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
}
