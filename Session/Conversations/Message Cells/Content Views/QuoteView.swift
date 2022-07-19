// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

final class QuoteView: UIView {
    static let thumbnailSize: CGFloat = 48
    static let iconSize: CGFloat = 24
    static let labelStackViewSpacing: CGFloat = 2
    static let labelStackViewVMargin: CGFloat = 4
    static let cancelButtonSize: CGFloat = 33
    
    enum Mode {
        case regular
        case draft
    }
    enum Direction { case incoming, outgoing }
    
    // MARK: - Variables
    
    private let onCancel: (() -> ())?

    // MARK: - Lifecycle
    
    init(
        for mode: Mode,
        authorId: String,
        quotedText: String?,
        threadVariant: SessionThread.Variant,
        currentUserPublicKey: String?,
        currentUserBlindedPublicKey: String?,
        direction: Direction,
        attachment: Attachment?,
        hInset: CGFloat,
        maxWidth: CGFloat,
        onCancel: (() -> ())? = nil
    ) {
        self.onCancel = onCancel
        
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy(
            mode: mode,
            authorId: authorId,
            quotedText: quotedText,
            threadVariant: threadVariant,
            currentUserPublicKey: currentUserPublicKey,
            currentUserBlindedPublicKey: currentUserBlindedPublicKey,
            direction: direction,
            attachment: attachment,
            hInset: hInset,
            maxWidth: maxWidth
        )
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(for:maxMessageWidth:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(for:maxMessageWidth:) instead.")
    }

    private func setUpViewHierarchy(
        mode: Mode,
        authorId: String,
        quotedText: String?,
        threadVariant: SessionThread.Variant,
        currentUserPublicKey: String?,
        currentUserBlindedPublicKey: String?,
        direction: Direction,
        attachment: Attachment?,
        hInset: CGFloat,
        maxWidth: CGFloat
    ) {
        // There's quite a bit of calculation going on here. It's a bit complex so don't make changes
        // if you don't need to. If you do then test:
        // • Quoted text in both private chats and group chats
        // • Quoted images and videos in both private chats and group chats
        // • Quoted voice messages and documents in both private chats and group chats
        // • All of the above in both dark mode and light mode
        let thumbnailSize = QuoteView.thumbnailSize
        let iconSize = QuoteView.iconSize
        let labelStackViewSpacing = QuoteView.labelStackViewSpacing
        let labelStackViewVMargin = QuoteView.labelStackViewVMargin
        let smallSpacing = Values.smallSpacing
        let cancelButtonSize = QuoteView.cancelButtonSize
        var availableWidth: CGFloat
        
        // Subtract smallSpacing twice; once for the spacing in between the stack view elements and
        // once for the trailing margin.
        if attachment == nil {
            availableWidth = maxWidth - 2 * hInset - Values.accentLineThickness - 2 * smallSpacing
        }
        else {
            availableWidth = maxWidth - 2 * hInset - thumbnailSize - 2 * smallSpacing
        }
        
        if case .draft = mode {
            availableWidth -= cancelButtonSize
        }
        
        let availableSpace = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        var body: String? = quotedText
        
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
        let lineColor: UIColor = {
            switch (mode, AppModeManager.shared.currentAppMode) {
                case (.regular, .light), (.draft, .light): return .black
                case (.regular, .dark): return (direction == .outgoing) ? .black : Colors.accent
                case (.draft, .dark): return Colors.accent
            }
        }()
        let lineView = UIView()
        lineView.backgroundColor = lineColor
        lineView.set(.width, to: Values.accentLineThickness)
        
        if let attachment: Attachment = attachment {
            let isAudio: Bool = MIMETypeUtil.isAudio(attachment.contentType)
            let fallbackImageName: String = (isAudio ? "attachment_audio" : "actionsheet_document_black")
            let imageView: UIImageView = UIImageView(
                image: UIImage(named: fallbackImageName)?
                    .withRenderingMode(.alwaysTemplate)
                    .resizedImage(to: CGSize(width: iconSize, height: iconSize))
            )
            
            attachment.thumbnail(
                size: .small,
                success: { image, _ in
                    guard Thread.isMainThread else {
                        DispatchQueue.main.async {
                            imageView.image = image
                            imageView.contentMode = .scaleAspectFill
                        }
                        return
                    }
                    
                    imageView.image = image
                    imageView.contentMode = .scaleAspectFill
                },
                failure: {}
            )
            
            imageView.tintColor = .white
            imageView.contentMode = .center
            imageView.backgroundColor = lineColor
            imageView.layer.cornerRadius = VisibleMessageCell.smallCornerRadius
            imageView.layer.masksToBounds = true
            imageView.set(.width, to: thumbnailSize)
            imageView.set(.height, to: thumbnailSize)
            mainStackView.addArrangedSubview(imageView)
            
            if (body ?? "").isEmpty {
                body = (attachment.isImage ?
                    "Image" :
                    (isAudio ? "Audio" : "Document")
                )
            }
        }
        else {
            mainStackView.addArrangedSubview(lineView)
        }
        
        // Body label
        let textColor: UIColor = {
            guard mode != .draft else { return Colors.text }
            
            switch (direction, AppModeManager.shared.currentAppMode) {
                case (.outgoing, .dark), (.incoming, .light): return .black
                default: return .white
            }
        }()
        let bodyLabel = UILabel()
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byTruncatingTail
        
        let isOutgoing = (direction == .outgoing)
        bodyLabel.font = .systemFont(ofSize: Values.smallFontSize)
        bodyLabel.attributedText = body
            .map {
                MentionUtilities.highlightMentions(
                    in: $0,
                    threadVariant: threadVariant,
                    currentUserPublicKey: currentUserPublicKey,
                    currentUserBlindedPublicKey: currentUserBlindedPublicKey,
                    isOutgoingMessage: isOutgoing,
                    attributes: [:]
                )
            }
            .defaulting(
                to: attachment.map {
                    NSAttributedString(string: MIMETypeUtil.isAudio($0.contentType) ? "Audio" : "Document")
                }
            )
            .defaulting(to: NSAttributedString(string: "Document"))
        bodyLabel.textColor = textColor
        
        let bodyLabelSize = bodyLabel.systemLayoutSizeFitting(availableSpace)
        
        // Label stack view
        var authorLabelHeight: CGFloat?
        if threadVariant == .openGroup || threadVariant == .closedGroup {
            let isCurrentUser: Bool = [
                currentUserPublicKey,
                currentUserBlindedPublicKey,
            ]
            .compactMap { $0 }
            .asSet()
            .contains(authorId)
            let authorLabel = UILabel()
            authorLabel.lineBreakMode = .byTruncatingTail
            authorLabel.text = (isCurrentUser ?
                "MEDIA_GALLERY_SENDER_NAME_YOU".localized() :
                Profile.displayName(
                    id: authorId,
                    threadVariant: threadVariant
                )
            )
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
        }
        else {
            mainStackView.addArrangedSubview(bodyLabel)
        }
        
        // Cancel button
        let cancelButton = UIButton(type: .custom)
        cancelButton.setImage(UIImage(named: "X")?.withRenderingMode(.alwaysTemplate), for: UIControl.State.normal)
        cancelButton.tintColor = (isLightMode ? .black : .white)
        cancelButton.set(.width, to: cancelButtonSize)
        cancelButton.set(.height, to: cancelButtonSize)
        cancelButton.addTarget(self, action: #selector(cancel), for: UIControl.Event.touchUpInside)
        
        // Constraints
        contentView.addSubview(mainStackView)
        mainStackView.pin(to: contentView)
        
        if threadVariant != .openGroup && threadVariant != .closedGroup {
            bodyLabel.set(.width, to: bodyLabelSize.width)
        }
        
        let bodyLabelHeight = bodyLabelSize.height.clamp(0, (mode == .regular ? 60 : 40))
        let contentViewHeight: CGFloat
        
        if attachment != nil {
            contentViewHeight = thumbnailSize + 8 // Add a small amount of spacing above and below the thumbnail
            bodyLabel.set(.height, to: 18) // Experimentally determined
        }
        else {
            if let authorLabelHeight = authorLabelHeight { // Group thread
                contentViewHeight = bodyLabelHeight + (authorLabelHeight + labelStackViewSpacing) + 2 * labelStackViewVMargin
            }
            else {
                contentViewHeight = bodyLabelHeight + 2 * smallSpacing
            }
        }
        
        contentView.set(.height, to: contentViewHeight)
        lineView.set(.height, to: contentViewHeight - 8) // Add a small amount of spacing above and below the line
        
        if mode == .draft {
            addSubview(cancelButton)
            cancelButton.center(.vertical, in: self)
            cancelButton.pin(.right, to: .right, of: self)
        }
    }

    // MARK: - Interaction
    
    @objc private func cancel() {
        onCancel?()
    }
}
