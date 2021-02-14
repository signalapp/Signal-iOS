
final class LinkPreviewViewV2 : UIView {
    private let viewItem: ConversationViewItem?
    private let maxWidth: CGFloat
    private let isOutgoing: Bool
    private let delegate: UITextViewDelegate & BodyTextViewDelegate
    var linkPreviewState: LinkPreviewState? { didSet { update() } }

    private var textColor: UIColor {
        switch (isOutgoing, AppModeManager.shared.currentAppMode) {
        case (true, .dark), (false, .light): return .black
        default: return .white
        }
    }

    // MARK: UI Components
    private lazy var imageView: UIImageView = {
        let result = UIImageView()
        result.contentMode = .scaleAspectFill
        return result
    }()

    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.textColor = textColor
        result.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.numberOfLines = 0
        return result
    }()

    private lazy var bodyTextViewContainer = UIView()

    // MARK: Settings
    private static let imageSize: CGFloat = 100

    // MARK: Lifecycle
    init(for viewItem: ConversationViewItem?, maxWidth: CGFloat, isOutgoing: Bool, delegate: UITextViewDelegate & BodyTextViewDelegate) {
        self.viewItem = viewItem
        self.maxWidth = maxWidth
        self.isOutgoing = isOutgoing
        self.delegate = delegate
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(for:maxWidth:delegate:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(for:maxWidth:delegate:) instead.")
    }
    
    private func setUpViewHierarchy() {
        // Image view
        let imageViewContainer = UIView()
        imageViewContainer.set(.width, to: LinkPreviewViewV2.imageSize)
        imageViewContainer.set(.height, to: LinkPreviewViewV2.imageSize)
        imageViewContainer.clipsToBounds = true
        imageViewContainer.addSubview(imageView)
        imageView.pin(to: imageViewContainer)
        // Title label
        let titleLabelContainer = UIView()
        titleLabelContainer.addSubview(titleLabel)
        titleLabel.pin(to: titleLabelContainer, withInset: Values.smallSpacing)
        // Horizontal stack view
        let hStackViewContainer = UIView()
        hStackViewContainer.backgroundColor = isDarkMode ? .black : UIColor.black.withAlphaComponent(0.06)
        let hStackView = UIStackView(arrangedSubviews: [ imageViewContainer, titleLabelContainer ])
        hStackView.axis = .horizontal
        hStackView.alignment = .center
        hStackViewContainer.addSubview(hStackView)
        hStackView.pin(to: hStackViewContainer)
        // Vertical stack view
        let vStackView = UIStackView(arrangedSubviews: [ hStackViewContainer, bodyTextViewContainer ])
        vStackView.axis = .vertical
        addSubview(vStackView)
        vStackView.pin(to: self)
    }

    // MARK: Updating
    private func update() {
        guard let linkPreviewState = linkPreviewState else { return }
        // Image view
        imageView.image = linkPreviewState.image()
        // Title
        titleLabel.text = linkPreviewState.title()
        // Body text view
        bodyTextViewContainer.subviews.forEach { $0.removeFromSuperview() }
        if let viewItem = viewItem {
            let bodyTextView = VisibleMessageCell.getBodyTextView(for: viewItem, with: maxWidth, textColor: textColor, delegate: delegate)
            bodyTextViewContainer.addSubview(bodyTextView)
            bodyTextView.pin(to: bodyTextViewContainer, withInset: 12)
        }
    }
}
