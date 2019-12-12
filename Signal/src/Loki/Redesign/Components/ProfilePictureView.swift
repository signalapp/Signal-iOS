
@objc(LKProfilePictureView)
final class ProfilePictureView : UIView {
    private var imageViewWidthConstraint: NSLayoutConstraint!
    private var imageViewHeightConstraint: NSLayoutConstraint!
    @objc var size: CGFloat = 0 // Not an implicitly unwrapped optional due to Obj-C limitations
    @objc var isRSSFeed = false
    @objc var hexEncodedPublicKey: String!
    @objc var additionalHexEncodedPublicKey: String?
    
    // MARK: Components
    private lazy var imageView = getImageView()
    private lazy var additionalImageView = getImageView()
    
    private lazy var rssLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.textAlignment = .center
        result.text = "RSS"
        return result
    }()
    
    // MARK: Lifecycle
    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViewHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        // Set up image view
        addSubview(imageView)
        imageView.pin(.leading, to: .leading, of: self)
        imageView.pin(.top, to: .top, of: self)
        // Set up additional image view
        addSubview(additionalImageView)
        additionalImageView.pin(.trailing, to: .trailing, of: self)
        additionalImageView.pin(.bottom, to: .bottom, of: self)
        let additionalImageViewSize = Values.smallProfilePictureSize
        additionalImageView.set(.width, to: additionalImageViewSize)
        additionalImageView.set(.height, to: additionalImageViewSize)
        additionalImageView.layer.cornerRadius = additionalImageViewSize / 2
        // Set up RSS label
        addSubview(rssLabel)
        rssLabel.pin(.leading, to: .leading, of: self)
        rssLabel.pin(.top, to: .top, of: self)
        rssLabel.autoPinWidth(toWidthOf: imageView)
        rssLabel.autoPinHeight(toHeightOf: imageView)
    }
    
    // MARK: Updating
    @objc func update() {
        if let imageViewWidthConstraint = imageViewWidthConstraint, let imageViewHeightConstraint = imageViewHeightConstraint {
            imageView.removeConstraint(imageViewWidthConstraint)
            imageView.removeConstraint(imageViewHeightConstraint)
        }
        func getProfilePicture(of size: CGFloat, for hexEncodedPublicKey: String) -> UIImage {
            return OWSProfileManager.shared().profileAvatar(forRecipientId: hexEncodedPublicKey) ?? Identicon.generateIcon(string: hexEncodedPublicKey, size: size)
        }
        let size: CGFloat
        if let additionalHexEncodedPublicKey = additionalHexEncodedPublicKey, !isRSSFeed {
            size = Values.smallProfilePictureSize
            imageViewWidthConstraint = imageView.set(.width, to: size)
            imageViewHeightConstraint = imageView.set(.height, to: size)
            additionalImageView.isHidden = false
            additionalImageView.image = getProfilePicture(of: size, for: additionalHexEncodedPublicKey)
        } else {
            size = self.size
            imageViewWidthConstraint = imageView.pin(.trailing, to: .trailing, of: self)
            imageViewHeightConstraint = imageView.pin(.bottom, to: .bottom, of: self)
            additionalImageView.isHidden = true
            additionalImageView.image = nil
        }
        imageView.image = isRSSFeed ? nil : getProfilePicture(of: size, for: hexEncodedPublicKey)
        imageView.backgroundColor = isRSSFeed ? UIColor(hex: 0x353535) : Colors.unimportant
        imageView.layer.cornerRadius = size / 2
        rssLabel.isHidden = !isRSSFeed
    }
    
    // MARK: Convenience
    private func getImageView() -> UIImageView {
        let result = UIImageView()
        result.layer.masksToBounds = true
        result.backgroundColor = Colors.unimportant
        result.layer.borderColor = Colors.border.cgColor
        result.layer.borderWidth = Values.borderThickness
        result.contentMode = .scaleAspectFit
        return result
    }
}
