
final class InfoMessageCell : MessageCell {
    private lazy var iconImageViewWidthConstraint = iconImageView.set(.width, to: InfoMessageCell.iconSize)
    private lazy var iconImageViewHeightConstraint = iconImageView.set(.height, to: InfoMessageCell.iconSize)
    
    // MARK: UI Components
    private lazy var iconImageView = UIImageView()
    
    private lazy var label: UILabel = {
        let result = UILabel()
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        result.textColor = Colors.text
        result.textAlignment = .center
        return result
    }()
    
    private lazy var stackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ iconImageView, label ])
        result.axis = .vertical
        result.alignment = .center
        result.spacing = Values.smallSpacing
        return result
    }()
    
    // MARK: Settings
    private static let iconSize: CGFloat = 16
    private static let inset = Values.mediumSpacing
    
    override class var identifier: String { "InfoMessageCell" }
    
    // MARK: Lifecycle
    override func setUpViewHierarchy() {
        super.setUpViewHierarchy()
        iconImageViewWidthConstraint.isActive = true
        iconImageViewHeightConstraint.isActive = true
        addSubview(stackView)
        stackView.pin(.left, to: .left, of: self, withInset: InfoMessageCell.inset)
        stackView.pin(.top, to: .top, of: self, withInset: InfoMessageCell.inset)
        stackView.pin(.right, to: .right, of: self, withInset: -InfoMessageCell.inset)
        stackView.pin(.bottom, to: .bottom, of: self, withInset: -InfoMessageCell.inset)
    }
    
    // MARK: Updating
    override func update() {
        guard let message = viewItem?.interaction as? TSInfoMessage else { return }
        let icon: UIImage?
        switch message.messageType {
        case .disappearingMessagesUpdate:
            var configuration: OWSDisappearingMessagesConfiguration?
            Storage.read { transaction in
                configuration = message.thread(with: transaction).disappearingMessagesConfiguration(with: transaction)
            }
            if let configuration = configuration {
                icon = configuration.isEnabled ? UIImage(named: "ic_timer") : UIImage(named: "ic_timer_disabled")
            } else {
                icon = nil
            }
        case .mediaSavedNotification: icon = UIImage(named: "ic_download")
        default: icon = nil
        }
        if let icon = icon {
            iconImageView.image = icon.withTint(Colors.text)
        }
        iconImageViewWidthConstraint.constant = (icon != nil) ? InfoMessageCell.iconSize : 0
        iconImageViewHeightConstraint.constant = (icon != nil) ? InfoMessageCell.iconSize : 0
        Storage.read { transaction in
            self.label.text = message.previewText(with: transaction)
        }
    }
}
