
final class LinkView : UIView {
    private let viewItem: ConversationViewItem
    
    private var textColor: UIColor {
        let isOutgoing = (viewItem.interaction.interactionType() == .outgoingMessage)
        switch (isOutgoing, AppModeManager.shared.currentAppMode) {
        case (true, .dark), (false, .light): return .black
        default: return .white
        }
    }
    
    private static let imageSize: CGFloat = 100
    
    init(for viewItem: ConversationViewItem) {
        self.viewItem = viewItem
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(for:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(for:) instead.")
    }
    
    private func setUpViewHierarchy() {
        guard let preview = viewItem.linkPreview else { return }
        
        let hStackViewContainer = UIView()
        hStackViewContainer.backgroundColor = .black
        
        let hStackView = UIStackView()
        hStackView.axis = .horizontal
        hStackView.alignment = .center
        
        hStackViewContainer.addSubview(hStackView)
        hStackView.pin(to: hStackViewContainer)
        
        let imageViewContainer = UIView()
        imageViewContainer.set(.width, to: LinkView.imageSize)
        imageViewContainer.set(.height, to: LinkView.imageSize)
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
        
        let bodyLabelContainer = UIView()
        
        let bodyLabel = VisibleMessageCell.getBodyLabel(for: viewItem, with: textColor)
        bodyLabelContainer.addSubview(bodyLabel)
        bodyLabel.pin(to: bodyLabelContainer, withInset: 12)
        vStackView.addArrangedSubview(bodyLabelContainer)
        
        addSubview(vStackView)
        vStackView.pin(to: self)
    }
}
