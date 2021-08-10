
final class DeletedMessageView : UIView {
    private let viewItem: ConversationViewItem
    private let textColor: UIColor
    
    // MARK: Settings
    private static let iconSize: CGFloat = 18
    private static let iconImageViewSize: CGFloat = 30
    
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
        // Image view
        let iconSize = DeletedMessageView.iconSize
        let icon = UIImage(named: "ic_trash")?.withTint(textColor)?.resizedImage(to: CGSize(width: iconSize, height: iconSize))
        let imageView = UIImageView(image: icon)
        imageView.contentMode = .center
        let iconImageViewSize = DeletedMessageView.iconImageViewSize
        imageView.set(.width, to: iconImageViewSize)
        imageView.set(.height, to: iconImageViewSize)
        // Body label
        let titleLabel = UILabel()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = NSLocalizedString("message_deleted", comment: "")
        titleLabel.textColor = textColor
        titleLabel.font = .systemFont(ofSize: Values.smallFontSize)
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ imageView, titleLabel ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 6)
        addSubview(stackView)
        stackView.pin(to: self, withInset: Values.smallSpacing)
    }
}

