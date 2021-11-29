import UIKit

final class CallMessageCell : MessageCell {
    private lazy var iconImageViewWidthConstraint = iconImageView.set(.width, to: CallMessageCell.iconSize)
    private lazy var iconImageViewHeightConstraint = iconImageView.set(.height, to: CallMessageCell.iconSize)
    
    // MARK: UI Components
    private lazy var iconImageView = UIImageView()
    
    private lazy var timestampLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        result.textColor = Colors.text
        result.textAlignment = .center
        return result
    }()
    
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
    
    private lazy var stackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ timestampLabel, container ])
        result.axis = .vertical
        result.alignment = .center
        result.spacing = Values.smallSpacing
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
        addSubview(stackView)
        container.autoPinWidthToSuperview()
        stackView.pin(.left, to: .left, of: self, withInset: CallMessageCell.margin)
        stackView.pin(.top, to: .top, of: self, withInset: CallMessageCell.inset)
        stackView.pin(.right, to: .right, of: self, withInset: -CallMessageCell.margin)
        stackView.pin(.bottom, to: .bottom, of: self, withInset: -CallMessageCell.inset)
    }
    
    // MARK: Updating
    override func update() {
        guard let message = viewItem?.interaction as? TSInfoMessage, message.messageType == .call else { return }
        let icon: UIImage?
        switch message.callState {
        case .outgoing: icon = UIImage(named: "CallOutgoing")?.withTint(Colors.text)
        case .incoming: icon = UIImage(named: "CallIncoming")?.withTint(Colors.text)
        case .missed: icon = UIImage(named: "CallMissed")?.withTint(Colors.destructive)
        default: icon = nil
        }
        if let icon = icon {
            iconImageView.image = icon
        }
        iconImageViewWidthConstraint.constant = (icon != nil) ? CallMessageCell.iconSize : 0
        iconImageViewHeightConstraint.constant = (icon != nil) ? CallMessageCell.iconSize : 0
        self.label.text = message.customMessage
        
        let date = message.dateForUI()
        let description = DateUtil.formatDate(forDisplay: date)
        timestampLabel.text = description
    }
}
