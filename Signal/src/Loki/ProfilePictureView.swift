
public final class ProfilePictureView : UIView {
    private var imageViewWidthConstraint: NSLayoutConstraint!
    private var imageViewHeightConstraint: NSLayoutConstraint!
    public var size: CGFloat!
    public var hexEncodedPublicKey: String!
    public var additionalHexEncodedPublicKey: String?
    
    // MARK: Components
    private lazy var imageView = getImageView()
    private lazy var additionalImageView = getImageView()
    
    // MARK: Lifecycle
    public override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        initialize()
    }
    
    private func initialize() {
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
    }
    
    // MARK: Updating
    public func update() {
        if let imageViewWidthConstraint = imageViewWidthConstraint, let imageViewHeightConstraint = imageViewHeightConstraint {
            imageView.removeConstraint(imageViewWidthConstraint)
            imageView.removeConstraint(imageViewHeightConstraint)
        }
        let size: CGFloat
        if let additionalHexEncodedPublicKey = additionalHexEncodedPublicKey {
            size = Values.smallProfilePictureSize
            imageViewWidthConstraint = imageView.set(.width, to: size)
            imageViewHeightConstraint = imageView.set(.height, to: size)
            additionalImageView.isHidden = false
            additionalImageView.image = Identicon.generateIcon(string: additionalHexEncodedPublicKey, size: size)
        } else {
            size = self.size
            imageViewWidthConstraint = imageView.pin(.trailing, to: .trailing, of: self)
            imageViewHeightConstraint = imageView.pin(.bottom, to: .bottom, of: self)
            additionalImageView.isHidden = true
            additionalImageView.image = nil
        }
        imageView.image = Identicon.generateIcon(string: hexEncodedPublicKey, size: size)
        imageView.layer.cornerRadius = size / 2
    }
    
    // MARK: Convenience
    private func getImageView() -> UIImageView {
        let result = UIImageView()
        result.layer.masksToBounds = true
        result.backgroundColor = Colors.unimportant
        result.layer.borderColor = Colors.border.cgColor
        result.layer.borderWidth = Values.profilePictureBorderThickness
        return result
    }
}
