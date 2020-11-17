import UIKit

final class UserCell : UITableViewCell {
    var accessory = Accessory.none
    var publicKey = ""

    // MARK: Accessory
    enum Accessory {
        case none
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

    private lazy var tickImageView: UIImageView = {
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
        // Set the cell background color
        backgroundColor = Colors.cellBackground
        // Set up the highlight color
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = .clear // Disabled for now
        self.selectedBackgroundView = selectedBackgroundView
        // Set up the profile picture image view
        let profilePictureViewSize = Values.smallProfilePictureSize
        profilePictureView.set(.width, to: profilePictureViewSize)
        profilePictureView.set(.height, to: profilePictureViewSize)
        profilePictureView.size = profilePictureViewSize
        // Set up the main stack view
        let stackView = UIStackView(arrangedSubviews: [ profilePictureView, displayNameLabel, tickImageView ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Values.mediumSpacing
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.mediumSpacing)
        stackView.pin(.top, to: .top, of: contentView, withInset: Values.mediumSpacing)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.mediumSpacing)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: Values.mediumSpacing)
        stackView.set(.width, to: UIScreen.main.bounds.width - 2 * Values.mediumSpacing)
        // Set up the separator
        contentView.addSubview(separator)
        separator.pin(.leading, to: .leading, of: contentView)
        contentView.pin(.trailing, to: .trailing, of: separator)
        separator.pin(.bottom, to: .bottom, of: contentView)
        separator.set(.width, to: UIScreen.main.bounds.width)
    }

    // MARK: Updating
    func update() {
        profilePictureView.hexEncodedPublicKey = publicKey
        profilePictureView.update()
        displayNameLabel.text = UserDisplayNameUtilities.getPrivateChatDisplayName(for: publicKey) ?? publicKey
        switch accessory {
        case .none: tickImageView.isHidden = true
        case .tick(let isSelected):
            tickImageView.isHidden = false
            let icon = isSelected ? #imageLiteral(resourceName: "CircleCheck") : #imageLiteral(resourceName: "Circle")
            tickImageView.image = isDarkMode ? icon : icon.asTintedImage(color: Colors.text)!
        }
    }
}
