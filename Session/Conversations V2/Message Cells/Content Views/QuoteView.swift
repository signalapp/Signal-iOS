
final class QuoteView : UIView {
    private let viewItem: ConversationViewItem
    private let maxMessageWidth: CGFloat

    private var direction: Direction {
        guard let message = viewItem.interaction as? TSMessage else { preconditionFailure() }
        switch message {
        case is TSIncomingMessage: return .incoming
        case is TSOutgoingMessage: return .outgoing
        default: preconditionFailure()
        }
    }

    private var lineColor: UIColor {
        return .black
    }

    private var textColor: UIColor {
        switch (direction, AppModeManager.shared.currentAppMode) {
        case (.outgoing, .dark), (.incoming, .light): return .white
        default: return .black
        }
    }

    private var snBackgroundColor: UIColor {
        switch direction {
        case .outgoing: return Colors.receivedMessageBackground
        case .incoming: return Colors.sentMessageBackground
        }
    }

    // MARK: Direction
    enum Direction { case incoming, outgoing }

    // MARK: Settings
    static let inset = Values.smallSpacing
    static let thumbnailSize: CGFloat = 48
    static let iconSize: CGFloat = 24
    static let labelStackViewSpacing: CGFloat = 2

    // MARK: Lifecycle
    init(for viewItem: ConversationViewItem, maxMessageWidth: CGFloat) {
        self.viewItem = viewItem
        self.maxMessageWidth = maxMessageWidth
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(for:maxMessageWidth:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(for:maxMessageWidth:) instead.")
    }

    private func setUpViewHierarchy() {
        guard let quote = (viewItem.interaction as? TSMessage)?.quotedMessage else { return }
        let hasAttachments = !quote.quotedAttachments.isEmpty
        let thumbnailSize = QuoteView.thumbnailSize
        let iconSize = QuoteView.iconSize
        let labelStackViewSpacing = QuoteView.labelStackViewSpacing
        let smallSpacing = Values.smallSpacing
        let inset = QuoteView.inset
        let availableWidth: CGFloat
        if !hasAttachments {
            availableWidth = maxMessageWidth - 2 * inset - Values.accentLineThickness - 2 * smallSpacing
        } else {
            availableWidth = maxMessageWidth - 2 * inset - thumbnailSize - 2 * smallSpacing
        }
        let availableSpace = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        var body = quote.body
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [])
        mainStackView.axis = .horizontal
        mainStackView.spacing = smallSpacing
        mainStackView.isLayoutMarginsRelativeArrangement = true
        mainStackView.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: smallSpacing)
        mainStackView.alignment = .center
        // Content view
        let contentView = UIView()
        contentView.backgroundColor = snBackgroundColor
        contentView.layer.cornerRadius = VisibleMessageCell.smallCornerRadius
        contentView.layer.masksToBounds = true
        addSubview(contentView)
        contentView.pin(to: self, withInset: inset)
        // Line view
        let lineView = UIView()
        lineView.backgroundColor = lineColor
        lineView.set(.width, to: Values.accentLineThickness)
        if !hasAttachments {
            mainStackView.addArrangedSubview(lineView)
        } else {
            let image = viewItem.quotedReply?.thumbnailImage
            let fallbackImage = UIImage(named: "actionsheet_document_black")?.withTint(.white)?.resizedImage(to: CGSize(width: iconSize, height: iconSize))
            let imageView = UIImageView(image: image ?? fallbackImage)
            imageView.contentMode = (image != nil) ? .scaleAspectFill : .center
            imageView.backgroundColor = lineColor
            imageView.set(.width, to: thumbnailSize)
            imageView.set(.height, to: thumbnailSize)
            mainStackView.addArrangedSubview(imageView)
            body = (image != nil) ? "Image" : "Document"
        }
        // Body label
        let bodyLabel = UILabel()
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.text = given(body) { MentionUtilities.highlightMentions(in: $0, threadID: viewItem.interaction.uniqueThreadId) } ?? "Document"
        bodyLabel.textColor = textColor
        bodyLabel.font = .systemFont(ofSize: Values.smallFontSize)
        if hasAttachments {
            bodyLabel.numberOfLines = 1
        }
        let bodyLabelSize = bodyLabel.systemLayoutSizeFitting(availableSpace)
        // Label stack view
        if viewItem.isGroupThread {
            let authorLabel = UILabel()
            authorLabel.lineBreakMode = .byTruncatingTail
            authorLabel.text = SSKEnvironment.shared.profileManager.profileNameForRecipient(withID: quote.authorId, avoidingWriteTransaction: true)
            authorLabel.textColor = textColor
            authorLabel.font = .boldSystemFont(ofSize: Values.smallFontSize)
            let authorLabelSize = authorLabel.systemLayoutSizeFitting(availableSpace)
            let labelStackView = UIStackView(arrangedSubviews: [ authorLabel, bodyLabel ])
            labelStackView.axis = .vertical
            labelStackView.spacing = labelStackViewSpacing
            labelStackView.set(.width, to: max(bodyLabelSize.width, authorLabelSize.width))
            mainStackView.addArrangedSubview(labelStackView)
        } else {
            mainStackView.addArrangedSubview(bodyLabel)
        }
        // Constraints
        contentView.addSubview(mainStackView)
        mainStackView.pin(to: contentView)
        if !viewItem.isGroupThread {
            bodyLabel.set(.width, to: bodyLabelSize.width)
        }
        let bodyLabelHeight = bodyLabelSize.height
        let authorLabelHeight: CGFloat = 14.33
        let isAuthorShown = viewItem.isGroupThread
        let contentViewHeight: CGFloat
        if hasAttachments {
            contentViewHeight = thumbnailSize
        } else {
            contentViewHeight = bodyLabelHeight + 2 * smallSpacing + (isAuthorShown ? (authorLabelHeight + labelStackViewSpacing) : 0)
        }
        contentView.set(.height, to: contentViewHeight)
        lineView.set(.height, to: contentViewHeight)
    }
}
