
final class DownloadAttachmentModal : Modal {
    private let viewItem: ConversationViewItem
    
    // MARK: Lifecycle
    init(viewItem: ConversationViewItem) {
        self.viewItem = viewItem
        super.init(nibName: nil, bundle: nil)
    }
    
    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(viewItem:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(viewItem:) instead.")
    }
    
    override func populateContentView() {
        guard let publicKey = (viewItem.interaction as? TSIncomingMessage)?.authorId else { return }
        // Name
        let name = Storage.shared.getContact(with: publicKey)?.displayName(for: .regular) ?? publicKey
        // Title
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.largeFontSize)
        titleLabel.text = String(format: NSLocalizedString("modal_download_attachment_title", comment: ""), name)
        titleLabel.textAlignment = .center
        // Message
        let messageLabel = UILabel()
        messageLabel.textColor = Colors.text
        messageLabel.font = .systemFont(ofSize: Values.smallFontSize)
        let message = String(format: NSLocalizedString("modal_download_attachment_explanation", comment: ""), name)
        let attributedMessage = NSMutableAttributedString(string: message)
        attributedMessage.addAttributes([ .font : UIFont.boldSystemFont(ofSize: Values.smallFontSize) ], range: (message as NSString).range(of: name))
        messageLabel.attributedText = attributedMessage
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .center
        // Download button
        let downloadButton = UIButton()
        downloadButton.set(.height, to: Values.mediumButtonHeight)
        downloadButton.layer.cornerRadius = Modal.buttonCornerRadius
        downloadButton.backgroundColor = Colors.buttonBackground
        downloadButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        downloadButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        downloadButton.setTitle(NSLocalizedString("modal_download_button_title", comment: ""), for: UIControl.State.normal)
        downloadButton.addTarget(self, action: #selector(trust), for: UIControl.Event.touchUpInside)
        // Button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ cancelButton, downloadButton ])
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
    @objc private func trust() {
        guard let message = viewItem.interaction as? TSIncomingMessage else { return }
        let publicKey = message.authorId
        let contact = Storage.shared.getContact(with: publicKey) ?? Contact(sessionID: publicKey)
        contact.isTrusted = true
        Storage.write(with: { transaction in
            Storage.shared.setContact(contact, using: transaction)
            MessageInvalidator.invalidate(message, with: transaction)
        }, completion: {
            Storage.shared.resumeAttachmentDownloadJobsIfNeeded(for: message.uniqueThreadId)
        })
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
}
