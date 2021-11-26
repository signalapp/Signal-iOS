import UIKit

final class CallMessageCell : MessageCell {
    private lazy var iconImageViewWidthConstraint = iconImageView.set(.width, to: CallMessageCell.iconSize)
    private lazy var iconImageViewHeightConstraint = iconImageView.set(.height, to: CallMessageCell.iconSize)
    
    // MARK: UI Components
    private lazy var iconImageView = UIImageView()
    
    private lazy var label: UILabel = {
        let result = UILabel()
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.textColor = Colors.text
        result.textAlignment = .center
        return result
    }()
    
    private lazy var container: UIView = {
        let result = UIView()
        result.set(.height, to: 50)
        result.layer.cornerRadius = 18
        result.backgroundColor = Colors.callMessageBackground
        result.addSubview(label)
        label.autoCenterInSuperview()
        result.addSubview(iconImageView)
        iconImageView.autoVCenterInSuperview()
        iconImageView.pin(.left, to: .left, of: result, withInset: CallMessageCell.inset)
        return result
    }()
    
    // MARK: Settings
    private static let iconSize: CGFloat = 16
    private static let inset = Values.mediumSpacing
    private static let margin = UIScreen.main.bounds.width * 0.1
    
    override class var identifier: String { "CallMessageCell" }
    
    // MARK: Lifecycle
    override func setUpViewHierarchy() {
        super.setUpViewHierarchy()
        iconImageViewWidthConstraint.isActive = true
        iconImageViewHeightConstraint.isActive = true
        addSubview(container)
        container.pin(.left, to: .left, of: self, withInset: CallMessageCell.margin)
        container.pin(.top, to: .top, of: self, withInset: CallMessageCell.inset)
        container.pin(.right, to: .right, of: self, withInset: -CallMessageCell.margin)
        container.pin(.bottom, to: .bottom, of: self, withInset: -CallMessageCell.inset)
    }
    
    // MARK: Updating
    override func update() {
        guard let message = viewItem?.interaction as? TSMessage, message.isCallMessage else { return }
        let icon: UIImage?
        switch message.interactionType() {
        case .outgoingMessage: icon = UIImage(named: "CallOutgoing")
        case .incomingMessage: icon = UIImage(named: "CallIncoming")
        default: icon = nil
        }
        if let icon = icon {
            iconImageView.image = icon.withTint(Colors.text)
        }
        iconImageViewWidthConstraint.constant = (icon != nil) ? CallMessageCell.iconSize : 0
        iconImageViewHeightConstraint.constant = (icon != nil) ? CallMessageCell.iconSize : 0
        Storage.read { transaction in
            self.label.text = message.previewText(with: transaction)
        }
    }
}
