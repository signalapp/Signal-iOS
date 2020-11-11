import SessionUIKit

@objc(LKSessionRestorationView)
final class SessionRestorationView : UIView {
    private let thread: TSThread
    @objc public var onRestore: (() -> Void)?
    @objc public var onDismiss: (() -> Void)?
    
    // MARK: Lifecycle
    @objc init(thread: TSThread) {
        self.thread = thread;
        super.init(frame: CGRect.zero)
        initialize()
    }
       
    required init?(coder: NSCoder) { fatalError("Using SessionRestorationView.init(coder:) isn't allowed. Use SessionRestorationView.init(thread:) instead.") }
    override init(frame: CGRect) { fatalError("Using SessionRestorationView.init(frame:) isn't allowed. Use SessionRestorationView.init(thread:) instead.") }
    
    private func initialize() {
        // Set up background
        backgroundColor = Colors.modalBackground
        layer.cornerRadius = Values.modalCornerRadius
        layer.masksToBounds = false
        layer.borderColor = Colors.modalBorder.cgColor
        layer.borderWidth = Values.borderThickness
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.64
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = "Session Out of Sync"
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = "Would you like to restore your session? This can help resolve issues. Your messages will be preserved."
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up restore button
        let restoreButton = UIButton()
        restoreButton.set(.height, to: Values.mediumButtonHeight)
        restoreButton.layer.cornerRadius = Values.modalButtonCornerRadius
        restoreButton.backgroundColor = Colors.accent
        restoreButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        restoreButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        restoreButton.setTitle(NSLocalizedString("session_reset_banner_restore_button_title", comment: ""), for: UIControl.State.normal)
        restoreButton.addTarget(self, action: #selector(restore), for: UIControl.Event.touchUpInside)
        // Set up dismiss button
        let dismissButton = UIButton()
        dismissButton.set(.height, to: Values.mediumButtonHeight)
        dismissButton.layer.cornerRadius = Values.modalButtonCornerRadius
        dismissButton.backgroundColor = Colors.buttonBackground
        dismissButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        dismissButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        dismissButton.setTitle(NSLocalizedString("session_reset_banner_dismiss_button_title", comment: ""), for: UIControl.State.normal)
        dismissButton.addTarget(self, action: #selector(dismiss), for: UIControl.Event.touchUpInside)
        // Set up button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ dismissButton, restoreButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.distribution = .fillEqually
        // Set up main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel, buttonStackView ])
        mainStackView.axis = .vertical
        mainStackView.spacing = Values.smallSpacing
        addSubview(mainStackView)
        mainStackView.pin(to: self, withInset: Values.mediumSpacing)
        // Update explanation label if possible
        if let contactID = thread.contactIdentifier() {
            let displayName = UserDisplayNameUtilities.getPrivateChatDisplayName(for: contactID) ?? contactID
            explanationLabel.text = String(format: "Would you like to restore your session with %@? This can help resolve issues. Your messages will be preserved.", displayName)
        }
    }
    
    // MARK: Interaction
    @objc private func restore() { onRestore?() }
    
    @objc private func dismiss() { onDismiss?() }
}
