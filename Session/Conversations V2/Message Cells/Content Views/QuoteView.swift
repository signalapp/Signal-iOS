
final class QuoteView : UIView {
    private let mode: Mode
    private let direction: Direction
    private let hInset: CGFloat
    private let maxMessageWidth: CGFloat

    private var attachments: [OWSAttachmentInfo] {
        switch mode {
        case .regular(let viewItem): return (viewItem.interaction as? TSMessage)?.quotedMessage!.quotedAttachments ?? []
        case .draft(let model): return given(model.attachmentStream) { [ OWSAttachmentInfo(attachmentStream: $0) ] } ?? []
        }
    }

    private var thumbnail: UIImage? {
        switch mode {
        case .regular(let viewItem): return viewItem.quotedReply!.thumbnailImage
        case .draft(let model): return model.thumbnailImage
        }
    }

    private var body: String? {
        switch mode {
        case .regular(let viewItem): return (viewItem.interaction as? TSMessage)?.quotedMessage!.body
        case .draft(let model): return model.body
        }
    }

    private var threadID: String {
        switch mode {
        case .regular(let viewItem): return viewItem.interaction.uniqueThreadId
        case .draft(let model): return model.threadId
        }
    }

    private var isGroupThread: Bool {
        switch mode {
        case .regular(let viewItem): return viewItem.isGroupThread
        case .draft(let model):
            var result = false
            Storage.read { transaction in
                result = TSThread.fetch(uniqueId: model.threadId, transaction: transaction)?.isGroupThread() ?? false
            }
            return result
        }
    }

    private var authorID: String {
        switch mode {
        case .regular(let viewItem): return viewItem.quotedReply!.authorId
        case .draft(let model): return model.authorId
        }
    }

    private var lineColor: UIColor {
        switch (mode, AppModeManager.shared.currentAppMode) {
        case (.regular, _), (.draft, .light): return .black
        case (.draft, .dark): return Colors.accent
        }
    }

    private var textColor: UIColor {
        if case .draft = mode { return Colors.text }
        switch (direction, AppModeManager.shared.currentAppMode) {
        case (.outgoing, .dark), (.incoming, .light): return .black
        default: return .white
        }
    }

    // MARK: Mode
    enum Mode {
        case regular(ConversationViewItem)
        case draft(OWSQuotedReplyModel)
    }

    // MARK: Direction
    enum Direction { case incoming, outgoing }

    // MARK: Settings
    static let thumbnailSize: CGFloat = 48
    static let iconSize: CGFloat = 24
    static let labelStackViewSpacing: CGFloat = 2

    // MARK: Lifecycle
    init(for viewItem: ConversationViewItem, direction: Direction, hInset: CGFloat, maxMessageWidth: CGFloat) {
        self.mode = .regular(viewItem)
        self.maxMessageWidth = maxMessageWidth
        self.direction = direction
        self.hInset = hInset
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }

    init(for model: OWSQuotedReplyModel, direction: Direction, hInset: CGFloat, maxMessageWidth: CGFloat) {
        self.mode = .draft(model)
        self.maxMessageWidth = maxMessageWidth
        self.direction = direction
        self.hInset = hInset
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
        let hasAttachments = !attachments.isEmpty
        let thumbnailSize = QuoteView.thumbnailSize
        let iconSize = QuoteView.iconSize
        let labelStackViewSpacing = QuoteView.labelStackViewSpacing
        let smallSpacing = Values.smallSpacing
        let availableWidth: CGFloat
        if !hasAttachments {
            availableWidth = maxMessageWidth - 2 * hInset - Values.accentLineThickness - 2 * smallSpacing
        } else {
            availableWidth = maxMessageWidth - 2 * hInset - thumbnailSize - 2 * smallSpacing
        }
        let availableSpace = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        var body = self.body
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [])
        mainStackView.axis = .horizontal
        mainStackView.spacing = smallSpacing
        mainStackView.isLayoutMarginsRelativeArrangement = true
        mainStackView.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: smallSpacing)
        mainStackView.alignment = .center
        // Content view
        let contentView = UIView()
        addSubview(contentView)
        contentView.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top, UIView.VerticalEdge.bottom ], to: self)
        contentView.rightAnchor.constraint(lessThanOrEqualTo: self.rightAnchor).isActive = true
        // Line view
        let lineView = UIView()
        lineView.backgroundColor = lineColor
        lineView.set(.width, to: Values.accentLineThickness)
        if !hasAttachments {
            mainStackView.addArrangedSubview(lineView)
        } else {
            let isAudio = MIMETypeUtil.isAudio(attachments.first!.contentType!)
            let fallbackImageName = isAudio ? "attachment_audio" : "actionsheet_document_black"
            let fallbackImage = UIImage(named: fallbackImageName)?.withTint(.white)?.resizedImage(to: CGSize(width: iconSize, height: iconSize))
            let imageView = UIImageView(image: thumbnail ?? fallbackImage)
            imageView.contentMode = (thumbnail != nil) ? .scaleAspectFill : .center
            imageView.backgroundColor = lineColor
            imageView.layer.cornerRadius = VisibleMessageCell.smallCornerRadius
            imageView.layer.masksToBounds = true
            imageView.set(.width, to: thumbnailSize)
            imageView.set(.height, to: thumbnailSize)
            mainStackView.addArrangedSubview(imageView)
            body = (thumbnail != nil) ? "Image" : (isAudio ? "Audio" : "Document")
        }
        // Body label
        let bodyLabel = UILabel()
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byTruncatingTail
        let isOutgoing = (direction == .outgoing)
        bodyLabel.attributedText = given(body) { MentionUtilities.highlightMentions(in: $0, isOutgoingMessage: isOutgoing, threadID: threadID, attributes: [:]) }
            ?? given(attachments.first?.contentType) { NSAttributedString(string: MIMETypeUtil.isAudio($0) ? "Audio" : "Document") } ?? NSAttributedString(string: "Document")
        bodyLabel.textColor = textColor
        bodyLabel.font = .systemFont(ofSize: Values.smallFontSize)
        if hasAttachments {
            bodyLabel.numberOfLines = 1
        }
        let bodyLabelSize = bodyLabel.systemLayoutSizeFitting(availableSpace)
        // Label stack view
        if isGroupThread {
            let authorLabel = UILabel()
            authorLabel.lineBreakMode = .byTruncatingTail
            authorLabel.text = SSKEnvironment.shared.profileManager.profileNameForRecipient(withID: authorID, avoidingWriteTransaction: true)
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
        if !isGroupThread {
            bodyLabel.set(.width, to: bodyLabelSize.width)
        }
        let maxBodyLabelHeight: CGFloat = 72
        let bodyLabelHeight = bodyLabelSize.height.clamp(0, maxBodyLabelHeight)
        let authorLabelHeight: CGFloat = 14.33
        let isAuthorShown = isGroupThread
        let contentViewHeight: CGFloat
        if hasAttachments {
            contentViewHeight = thumbnailSize + 8
        } else {
            contentViewHeight = bodyLabelHeight + 2 * smallSpacing + (isAuthorShown ? (authorLabelHeight + labelStackViewSpacing) : 0)
        }
        contentView.set(.height, to: contentViewHeight)
        lineView.set(.height, to: contentViewHeight - 8)
    }
}
