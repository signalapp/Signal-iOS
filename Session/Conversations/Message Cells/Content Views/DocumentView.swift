
final class DocumentView : UIView {
    private let viewItem: ConversationViewItem
    private let textColor: UIColor
    
    // MARK: Settings
    private static let iconImageViewSize: CGSize = CGSize(width: 31, height: 40)
    
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
        guard let attachment = viewItem.attachmentStream ?? viewItem.attachmentPointer else { return }
        // Image view
        let icon = UIImage(named: "File")?.withTint(textColor)
        let imageView = UIImageView(image: icon)
        imageView.contentMode = .center
        let iconImageViewSize = DocumentView.iconImageViewSize
        imageView.set(.width, to: iconImageViewSize.width)
        imageView.set(.height, to: iconImageViewSize.height)
        // Body label
        let titleLabel = UILabel()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = attachment.sourceFilename ?? "File"
        titleLabel.textColor = textColor
        titleLabel.font = .systemFont(ofSize: Values.smallFontSize, weight: .light)
        // Size label
        let sizeLabel = UILabel()
        sizeLabel.lineBreakMode = .byTruncatingTail
        sizeLabel.text = OWSFormat.formatFileSize(UInt(attachment.byteCount))
        sizeLabel.textColor = textColor
        sizeLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        // Label stack view
        let labelStackView = UIStackView(arrangedSubviews: [ titleLabel, sizeLabel ])
        labelStackView.axis = .vertical
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ imageView, labelStackView ])
        stackView.axis = .horizontal
        stackView.spacing = Values.verySmallSpacing
        stackView.alignment = .center
        addSubview(stackView)
        stackView.pin(to: self)
    }
}
