
final class QuoteView : UIView {
    private let mode: Mode
    private let direction: Direction
    private let hInset: CGFloat
    private let maxWidth: CGFloat
    private let delegate: QuoteViewDelegate?

    private var maxBodyLabelHeight: CGFloat {
        switch mode {
        case .regular: return 60
        case .draft: return 40
        }
    }

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
        case (.regular, .light), (.draft, .light): return .black
        case (.regular, .dark): return (direction == .outgoing) ? .black : Colors.accent
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
    static let labelStackViewVMargin: CGFloat = 4
    static let cancelButtonSize: CGFloat = 33

    // MARK: Lifecycle
    init(for viewItem: ConversationViewItem, direction: Direction, hInset: CGFloat, maxWidth: CGFloat) {
        self.mode = .regular(viewItem)
        self.maxWidth = maxWidth
        self.direction = direction
        self.hInset = hInset
        self.delegate = nil
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }

    init(for model: OWSQuotedReplyModel, direction: Direction, hInset: CGFloat, maxWidth: CGFloat, delegate: QuoteViewDelegate) {
        self.mode = .draft(model)
        self.maxWidth = maxWidth
        self.direction = direction
        self.hInset = hInset
        self.delegate = delegate
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
        // There's quite a bit of calculation going on here. It's a bit complex so don't make changes
        // if you don't need to. If you do then test:
        // • Quoted text in both private chats and group chats
        // • Quoted images and videos in both private chats and group chats
        // • Quoted voice messages and documents in both private chats and group chats
        // • All of the above in both dark mode and light mode
        let hasAttachments = !attachments.isEmpty
        let thumbnailSize = QuoteView.thumbnailSize
        let iconSize = QuoteView.iconSize
        let labelStackViewSpacing = QuoteView.labelStackViewSpacing
        let labelStackViewVMargin = QuoteView.labelStackViewVMargin
        let smallSpacing = Values.smallSpacing
        let cancelButtonSize = QuoteView.cancelButtonSize
        var availableWidth: CGFloat
        // Subtract smallSpacing twice; once for the spacing in between the stack view elements and
        // once for the trailing margin.
        if !hasAttachments {
            availableWidth = maxWidth - 2 * hInset - Values.accentLineThickness - 2 * smallSpacing
        } else {
            availableWidth = maxWidth - 2 * hInset - thumbnailSize - 2 * smallSpacing
        }
        if case .draft = mode {
            availableWidth -= cancelButtonSize
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
            let isAudio = MIMETypeUtil.isAudio(attachments.first!.contentType ?? "")
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
            if (body ?? "").isEmpty {
                body = (thumbnail != nil) ? "Image" : (isAudio ? "Audio" : "Document")
            }
        }
        // Body label
        let bodyLabel = UILabel()
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byTruncatingTail
        let isOutgoing = (direction == .outgoing)
        bodyLabel.font = .systemFont(ofSize: Values.smallFontSize)
        bodyLabel.attributedText = given(body) { MentionUtilities.highlightMentions(in: $0, isOutgoingMessage: isOutgoing, threadID: threadID, attributes: [:]) }
            ?? given(attachments.first?.contentType) { NSAttributedString(string: MIMETypeUtil.isAudio($0) ? "Audio" : "Document") } ?? NSAttributedString(string: "Document")
        bodyLabel.textColor = textColor
        let bodyLabelSize = bodyLabel.systemLayoutSizeFitting(availableSpace)
        // Label stack view
        var authorLabelHeight: CGFloat?
        if isGroupThread {
            let authorLabel = UILabel()
            authorLabel.lineBreakMode = .byTruncatingTail
            let context: Contact.Context = (TSGroupThread.fetch(uniqueId: threadID)?.isOpenGroup == true) ? .openGroup : .regular
            authorLabel.text = Storage.shared.getContact(with: authorID)?.displayName(for: context) ?? authorID
            authorLabel.textColor = textColor
            authorLabel.font = .boldSystemFont(ofSize: Values.smallFontSize)
            let authorLabelSize = authorLabel.systemLayoutSizeFitting(availableSpace)
            authorLabel.set(.height, to: authorLabelSize.height)
            authorLabelHeight = authorLabelSize.height
            let labelStackView = UIStackView(arrangedSubviews: [ authorLabel, bodyLabel ])
            labelStackView.axis = .vertical
            labelStackView.spacing = labelStackViewSpacing
            labelStackView.distribution = .equalCentering
            labelStackView.set(.width, to: max(bodyLabelSize.width, authorLabelSize.width))
            labelStackView.isLayoutMarginsRelativeArrangement = true
            labelStackView.layoutMargins = UIEdgeInsets(top: labelStackViewVMargin, left: 0, bottom: labelStackViewVMargin, right: 0)
            mainStackView.addArrangedSubview(labelStackView)
        } else {
            mainStackView.addArrangedSubview(bodyLabel)
        }
        // Cancel button
        let cancelButton = UIButton(type: .custom)
        let tint: UIColor = isLightMode ? .black : .white
        cancelButton.setImage(UIImage(named: "X")?.withTint(tint), for: UIControl.State.normal)
        cancelButton.set(.width, to: cancelButtonSize)
        cancelButton.set(.height, to: cancelButtonSize)
        cancelButton.addTarget(self, action: #selector(cancel), for: UIControl.Event.touchUpInside)
        // Constraints
        contentView.addSubview(mainStackView)
        mainStackView.pin(to: contentView)
        if !isGroupThread {
            bodyLabel.set(.width, to: bodyLabelSize.width)
        }
        let bodyLabelHeight = bodyLabelSize.height.clamp(0, maxBodyLabelHeight)
        let contentViewHeight: CGFloat
        if hasAttachments {
            contentViewHeight = thumbnailSize + 8 // Add a small amount of spacing above and below the thumbnail
            bodyLabel.set(.height, to: 18) // Experimentally determined
        } else {
            if let authorLabelHeight = authorLabelHeight { // Group thread
                contentViewHeight = bodyLabelHeight + (authorLabelHeight + labelStackViewSpacing) + 2 * labelStackViewVMargin
            } else {
                contentViewHeight = bodyLabelHeight + 2 * smallSpacing
            }
        }
        contentView.set(.height, to: contentViewHeight)
        lineView.set(.height, to: contentViewHeight - 8) // Add a small amount of spacing above and below the line
        if case .draft = mode {
            addSubview(cancelButton)
            cancelButton.center(.vertical, in: self)
            cancelButton.pin(.right, to: .right, of: self)
        }
    }

    // MARK: Interaction
    @objc private func cancel() {
        delegate?.handleQuoteViewCancelButtonTapped()
    }
}

// MARK: Delegate
protocol QuoteViewDelegate {

    func handleQuoteViewCancelButtonTapped()
}
