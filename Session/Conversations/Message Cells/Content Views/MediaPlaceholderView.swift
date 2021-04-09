
final class MediaPlaceholderView : UIView {
    private let viewItem: ConversationViewItem
    private let textColor: UIColor
    
    // MARK: Settings
    private static let iconSize: CGFloat = 24
    private static let iconImageViewSize: CGFloat = 40
    
    // MARK: Lifecycle
    init(viewItem: ConversationViewItem, textColor: UIColor) {
        self.viewItem = viewItem
        self.textColor = textColor
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(viewItem:textColor:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(viewItem:textColor:) instead.")
    }
    
    private func setUpViewHierarchy() {
        let (iconName, attachmentDescription): (String, String) = {
            guard let message = viewItem.interaction as? TSIncomingMessage else { return ("actionsheet_document_black", "file") } // Should never occur
            var attachments: [TSAttachment] = []
            Storage.read { transaction in
                attachments = message.attachments(with: transaction)
            }
            guard let contentType = attachments.first?.contentType else { return ("actionsheet_document_black", "file") } // Should never occur
            if MIMETypeUtil.isAudio(contentType) { return ("attachment_audio", "audio") }
            if MIMETypeUtil.isImage(contentType) || MIMETypeUtil.isVideo(contentType) { return ("actionsheet_camera_roll_black", "media") }
            return ("actionsheet_document_black", "file")
        }()
        // Image view
        let iconSize = MediaPlaceholderView.iconSize
        let icon = UIImage(named: iconName)?.withTint(textColor)?.resizedImage(to: CGSize(width: iconSize, height: iconSize))
        let imageView = UIImageView(image: icon)
        imageView.contentMode = .center
        let iconImageViewSize = MediaPlaceholderView.iconImageViewSize
        imageView.set(.width, to: iconImageViewSize)
        imageView.set(.height, to: iconImageViewSize)
        // Body label
        let titleLabel = UILabel()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = "Tap to download \(attachmentDescription)"
        titleLabel.textColor = textColor
        titleLabel.font = .systemFont(ofSize: Values.mediumFontSize)
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ imageView, titleLabel ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12)
        addSubview(stackView)
        stackView.pin(to: self, withInset: Values.smallSpacing)
    }
}
