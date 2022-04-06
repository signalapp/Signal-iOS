import UIKit

@objc
final class CallMissedTipsModal : Modal {
    private let caller: String
    
    // MARK: Lifecycle
    @objc
    init(caller: String) {
        self.caller = caller
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(onCallEnabled:) instead.")
    }

    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(onCallEnabled:) instead.")
    }

    override func populateContentView() {
        // Tips icon
        let tipsIconImageView = UIImageView(image: UIImage(named: "Tips")?.withTint(Colors.text))
        tipsIconImageView.set(.width, to: 19)
        tipsIconImageView.set(.height, to: 28)
        // Title
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = NSLocalizedString("modal_call_missed_tips_title", comment: "")
        titleLabel.textAlignment = .center
        // Message
        let messageLabel = UILabel()
        messageLabel.textColor = Colors.text
        messageLabel.font = .systemFont(ofSize: Values.smallFontSize)
        let message = String(format: NSLocalizedString("modal_call_missed_tips_explanation", comment: ""), caller)
        messageLabel.text = message
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .natural
        // Cancel Button
        cancelButton.setTitle(NSLocalizedString("OK", comment: ""), for: .normal)
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ tipsIconImageView, titleLabel, messageLabel, cancelButton ])
        mainStackView.axis = .vertical
        mainStackView.alignment = .center
        mainStackView.spacing = Values.largeSpacing
        contentView.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: Values.largeSpacing)
    }
}
