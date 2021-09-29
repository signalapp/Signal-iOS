
final class CallMessageView : UIView {
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
        guard let message = viewItem.interaction as? TSMessage else { preconditionFailure() }
        // Image view
        let iconSize = CallMessageView.iconSize
        let icon = UIImage(named: "Phone")?.withTint(textColor)?.resizedImage(to: CGSize(width: iconSize, height: iconSize))
        let imageView = UIImageView(image: icon)
        imageView.contentMode = .center
        let iconImageViewSize = CallMessageView.iconImageViewSize
        imageView.set(.width, to: iconImageViewSize)
        imageView.set(.height, to: iconImageViewSize)
        // Body label
        let titleLabel = UILabel()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = message.body
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
