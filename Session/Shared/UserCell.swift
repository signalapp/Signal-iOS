import UIKit

final class UserCell : UITableViewCell {
    var accessory = Accessory.none
    var publicKey = ""
    var isZombie = false

    // MARK: Accessory
    enum Accessory {
        case none
        case lock
        case tick(isSelected: Bool)
    }

    // MARK: Components
    private lazy var profilePictureView = ProfilePictureView()

    private lazy var displayNameLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.lineBreakMode = .byTruncatingTail
        return result
    }()

    private lazy var accessoryImageView: UIImageView = {
        let result = UIImageView()
        result.contentMode = .scaleAspectFit
        let size: CGFloat = 24
        result.set(.width, to: size)
        result.set(.height, to: size)
        return result
    }()

    private lazy var separator: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.separator
        result.set(.height, to: Values.separatorThickness)
        return result
    }()

    // MARK: Initialization
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUpViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }

    private func setUpViewHierarchy() {
        // Background color
        backgroundColor = Colors.cellBackground
        // Highlight color
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = .clear // Disabled for now
        self.selectedBackgroundView = selectedBackgroundView
        // Profile picture image view
        let profilePictureViewSize = Values.smallProfilePictureSize
        profilePictureView.set(.width, to: profilePictureViewSize)
        profilePictureView.set(.height, to: profilePictureViewSize)
        profilePictureView.size = profilePictureViewSize
        // Main stack view
        let spacer = UIView.hStretchingSpacer()
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: Values.mediumSpacing).isActive = true
        let stackView = UIStackView(arrangedSubviews: [ profilePictureView, UIView.hSpacer(Values.mediumSpacing), displayNameLabel, spacer, accessoryImageView ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(uniform: Values.mediumSpacing)
        contentView.addSubview(stackView)
        stackView.pin(to: contentView)
        stackView.set(.width, to: UIScreen.main.bounds.width)
        // Set up the separator
        contentView.addSubview(separator)
        separator.pin([ UIView.HorizontalEdge.leading, UIView.VerticalEdge.bottom, UIView.HorizontalEdge.trailing ], to: contentView)
    }

    // MARK: Updating
    func update() {
        profilePictureView.publicKey = publicKey
        profilePictureView.update()
        displayNameLabel.text = Storage.shared.getContact(with: publicKey)?.displayName(for: .regular) ?? publicKey
        switch accessory {
        case .none: accessoryImageView.isHidden = true
        case .lock:
            accessoryImageView.isHidden = false
            accessoryImageView.image = #imageLiteral(resourceName: "ic_lock_outline").asTintedImage(color: Colors.text.withAlphaComponent(Values.mediumOpacity))!
        case .tick(let isSelected):
            accessoryImageView.isHidden = false
            let icon = isSelected ? #imageLiteral(resourceName: "CircleCheck") : #imageLiteral(resourceName: "Circle")
            accessoryImageView.image = isDarkMode ? icon : icon.asTintedImage(color: Colors.text)!
        }
        let alpha: CGFloat = isZombie ? 0.5 : 1
        [ profilePictureView, displayNameLabel, accessoryImageView ].forEach { $0.alpha = alpha }
    }
}
