
final class LinkPreviewModal : Modal {
    private let onLinkPreviewsEnabled: () -> Void

    // MARK: Lifecycle
    init(onLinkPreviewsEnabled: @escaping () -> Void) {
        self.onLinkPreviewsEnabled = onLinkPreviewsEnabled
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(onLinkPreviewsEnabled:) instead.")
    }

    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(onLinkPreviewsEnabled:) instead.")
    }

    override func populateContentView() {
        // Title
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.largeFontSize)
        titleLabel.text = "Enable Link Previews?"
        titleLabel.textAlignment = .center
        // Message
        let messageLabel = UILabel()
        messageLabel.textColor = Colors.text
        messageLabel.font = .systemFont(ofSize: Values.smallFontSize)
        let message = "Enabling link previews will show previews for URLs you send and receive. This can be useful, but Session will need to contact linked websites to generate previews. You can always disable link previews in Session's settings."
        messageLabel.text = message
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .center
        // Enable button
        let enableButton = UIButton()
        enableButton.set(.height, to: Values.mediumButtonHeight)
        enableButton.layer.cornerRadius = Values.modalButtonCornerRadius
        enableButton.backgroundColor = Colors.buttonBackground
        enableButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        enableButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        enableButton.setTitle("Enable", for: UIControl.State.normal)
        enableButton.addTarget(self, action: #selector(enable), for: UIControl.Event.touchUpInside)
        // Button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ cancelButton, enableButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.distribution = .fillEqually
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ titleLabel, messageLabel, buttonStackView ])
        mainStackView.axis = .vertical
        mainStackView.spacing = Values.largeSpacing
        contentView.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: Values.largeSpacing)
    }

    // MARK: Interaction
    @objc private func enable() {
        SSKPreferences.areLinkPreviewsEnabled = true
        presentingViewController?.dismiss(animated: true, completion: nil)
        onLinkPreviewsEnabled()
    }
}
