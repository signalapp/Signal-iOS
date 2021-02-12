
final class LinkPreviewViewV2 : UIView {
    private let viewItem: ConversationViewItem
    private let maxWidth: CGFloat
    private let delegate: UITextViewDelegate & BodyTextViewDelegate
    
    private var textColor: UIColor {
        let isOutgoing = (viewItem.interaction.interactionType() == .outgoingMessage)
        switch (isOutgoing, AppModeManager.shared.currentAppMode) {
        case (true, .dark), (false, .light): return .black
        default: return .white
        }
    }
    
    private static let imageSize: CGFloat = 100
    
    init(for viewItem: ConversationViewItem, maxWidth: CGFloat, delegate: UITextViewDelegate & BodyTextViewDelegate) {
        self.viewItem = viewItem
        self.maxWidth = maxWidth
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
        guard let preview = viewItem.linkPreview else { return }
        
        let hStackViewContainer = UIView()
        hStackViewContainer.backgroundColor = isDarkMode ? .black : UIColor.black.withAlphaComponent(0.06)
        
        let hStackView = UIStackView()
        hStackView.axis = .horizontal
        hStackView.alignment = .center
        
        hStackViewContainer.addSubview(hStackView)
        hStackView.pin(to: hStackViewContainer)
        
        let imageViewContainer = UIView()
        imageViewContainer.set(.width, to: LinkPreviewViewV2.imageSize)
        imageViewContainer.set(.height, to: LinkPreviewViewV2.imageSize)
        imageViewContainer.clipsToBounds = true
        
        let imageView = UIImageView()
        let filePath = given(preview.imageAttachmentId) { TSAttachmentStream.fetch(uniqueId: $0)!.originalFilePath! }
        imageView.image = given(filePath) { UIImage(contentsOfFile: $0)! }
        imageView.contentMode = .scaleAspectFill
        imageViewContainer.addSubview(imageView)
        imageView.pin(to: imageViewContainer)
        hStackView.addArrangedSubview(imageViewContainer)
        
        let titleLabelContainer = UIView()
        
        let titleLabel = UILabel()
        titleLabel.text = preview.title
        titleLabel.textColor = textColor
        titleLabel.font = .boldSystemFont(ofSize: Values.smallFontSize)
        titleLabel.numberOfLines = 0
        titleLabelContainer.addSubview(titleLabel)
        titleLabel.pin(to: titleLabelContainer, withInset: Values.smallSpacing)
        hStackView.addArrangedSubview(titleLabelContainer)
        
        let vStackView = UIStackView()
        vStackView.axis = .vertical
        vStackView.addArrangedSubview(hStackViewContainer)
        
        let separator = UIView()
        separator.backgroundColor = Colors.separator
        separator.set(.height, to: 1 / UIScreen.main.scale)
        vStackView.addArrangedSubview(separator)
        
        let bodyTextViewContainer = UIView()
        
        let bodyTextView = VisibleMessageCell.getBodyTextView(for: viewItem, with: maxWidth, textColor: textColor, delegate: delegate)
        bodyTextViewContainer.addSubview(bodyTextView)
        bodyTextView.pin(to: bodyTextViewContainer, withInset: 12)
        vStackView.addArrangedSubview(bodyTextViewContainer)
        
        addSubview(vStackView)
        vStackView.pin(to: self)
    }
}
