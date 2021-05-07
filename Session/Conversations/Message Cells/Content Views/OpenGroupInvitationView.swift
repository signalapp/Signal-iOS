
final class OpenGroupInvitationView : UIView {
    private let name: String
    private let rawURL: String
    private let textColor: UIColor
    private let isOutgoing: Bool
    
    private lazy var url: String = {
        if let range = rawURL.range(of: "?public_key=") {
            return String(rawURL[..<range.lowerBound])
        } else {
            return rawURL
        }
    }()
    
    // MARK: Settings
    private static let iconSize: CGFloat = 24
    private static let iconImageViewSize: CGFloat = 48
    
    // MARK: Lifecycle
    init(name: String, url: String, textColor: UIColor, isOutgoing: Bool) {
        self.name = name
        self.rawURL = url
        self.textColor = textColor
        self.isOutgoing = isOutgoing
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(name:url:textColor:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(name:url:textColor:) instead.")
    }
    
    private func setUpViewHierarchy() {
        // Title
        let titleLabel = UILabel()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = name
        titleLabel.textColor = textColor
        titleLabel.font = .boldSystemFont(ofSize: Values.largeFontSize)
        // Subtitle
        let subtitleLabel = UILabel()
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.text = NSLocalizedString("view_open_group_invitation_description", comment: "")
        subtitleLabel.textColor = textColor
        subtitleLabel.font = .systemFont(ofSize: Values.smallFontSize)
        // URL
        let urlLabel = UILabel()
        urlLabel.lineBreakMode = .byCharWrapping
        urlLabel.text = url
        urlLabel.textColor = textColor
        urlLabel.numberOfLines = 0
        urlLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        // Label stack
        let labelStackView = UIStackView(arrangedSubviews: [ titleLabel, UIView.vSpacer(2), subtitleLabel, UIView.vSpacer(4), urlLabel ])
        labelStackView.axis = .vertical
        // Icon
        let iconSize = OpenGroupInvitationView.iconSize
        let iconName = isOutgoing ? "Globe" : "Plus"
        let icon = UIImage(named: iconName)?.withTint(.white)?.resizedImage(to: CGSize(width: iconSize, height: iconSize))
        let iconImageViewSize = OpenGroupInvitationView.iconImageViewSize
        let iconImageView = UIImageView(image: icon)
        iconImageView.contentMode = .center
        iconImageView.layer.cornerRadius = iconImageViewSize / 2
        iconImageView.layer.masksToBounds = true
        iconImageView.backgroundColor = Colors.accent
        iconImageView.set(.width, to: iconImageViewSize)
        iconImageView.set(.height, to: iconImageViewSize)
        // Main stack
        let mainStackView = UIStackView(arrangedSubviews: [ iconImageView, labelStackView ])
        mainStackView.axis = .horizontal
        mainStackView.spacing = Values.mediumSpacing
        mainStackView.alignment = .center
        addSubview(mainStackView)
        mainStackView.pin(to: self, withInset: Values.mediumSpacing)
    }
}
