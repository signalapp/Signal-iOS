//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

protocol QuotedReplyPreviewDelegate: AnyObject {
    func quotedReplyPreviewDidPressCancel(_ preview: QuotedReplyPreview)
}

class QuotedReplyPreview: UIView, QuotedMessageSnippetViewDelegate {

    public weak var delegate: QuotedReplyPreviewDelegate?

    private let quotedReply: QuotedReplyModel
    private let conversationStyle: ConversationStyle
    private let spoilerState: SpoilerRenderState
    private var quotedMessageView: QuotedMessageSnippetView?
    private var heightConstraint: NSLayoutConstraint!

    @available(*, unavailable, message: "use other constructor instead.")
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable, message: "use other constructor instead.")
    override init(frame: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }

    init(
        quotedReply: QuotedReplyModel,
        conversationStyle: ConversationStyle,
        spoilerState: SpoilerRenderState
    ) {
        self.quotedReply = quotedReply
        self.conversationStyle = conversationStyle
        self.spoilerState = spoilerState

        super.init(frame: .zero)

        self.heightConstraint = self.autoSetDimension(.height, toSize: 0)

        updateContents()

        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange), name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    private let draftMarginTop: CGFloat = 6

    func updateContents() {
        subviews.forEach { $0.removeFromSuperview() }

        let hMargin: CGFloat = 6
        self.layoutMargins = UIEdgeInsets(top: draftMarginTop,
                                          left: hMargin,
                                          bottom: 0,
                                          right: hMargin)

        // We instantiate quotedMessageView late to ensure that it is updated
        // every time contentSizeCategoryDidChange (i.e. when dynamic type
        // sizes changes).
        let quotedMessageView = QuotedMessageSnippetView(
            quotedMessage: quotedReply,
            conversationStyle: conversationStyle,
            spoilerState: spoilerState
        )
        quotedMessageView.delegate = self
        self.quotedMessageView = quotedMessageView
        quotedMessageView.setContentHuggingHorizontalLow()
        quotedMessageView.setCompressionResistanceHorizontalLow()
        quotedMessageView.backgroundColor = .clear
        self.addSubview(quotedMessageView)
        quotedMessageView.autoPinEdgesToSuperviewMargins()

        updateHeight()
    }

    // MARK: Sizing

    func updateHeight() {
        guard let quotedMessageView else {
            owsFailDebug("missing quotedMessageView")
            return
        }
        let size = quotedMessageView.systemLayoutSizeFitting(.square(CGFloat.greatestFiniteMagnitude))
        heightConstraint.constant = size.height + draftMarginTop
    }

    @objc
    private func contentSizeCategoryDidChange(_ notification: Notification) {
        Logger.debug("")

        updateContents()
    }

    // MARK: QuotedMessageSnippetViewDelegate

    fileprivate func didTapCancelInQuotedMessageSnippet(view: QuotedMessageSnippetView) {
        delegate?.quotedReplyPreviewDidPressCancel(self)
    }
}

private protocol QuotedMessageSnippetViewDelegate: AnyObject {
    func didTapCancelInQuotedMessageSnippet(view: QuotedMessageSnippetView)
}

private class QuotedMessageSnippetView: UIView {

    weak var delegate: QuotedMessageSnippetViewDelegate?

    private let quotedMessage: QuotedReplyModel
    private let conversationStyle: ConversationStyle
    private let spoilerState: SpoilerRenderState
    private lazy var displayableQuotedText: DisplayableText? = {
        QuotedMessageSnippetView.displayableTextWithSneakyTransaction(
            forPreview: quotedMessage,
            spoilerState: spoilerState
        )
    }()

    init(
        quotedMessage: QuotedReplyModel,
        conversationStyle: ConversationStyle,
        spoilerState: SpoilerRenderState
    ) {
        self.quotedMessage = quotedMessage
        self.conversationStyle = conversationStyle
        self.spoilerState = spoilerState

        super.init(frame: .zero)

        isUserInteractionEnabled = true
        layoutMargins = .zero
        clipsToBounds = true

        createViewContents()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let quotedTextLabelSpoilerAnimator {
            spoilerState.animationManager.removeViewAnimator(quotedTextLabelSpoilerAnimator)
        }
    }

    // MARK: Layout

    private lazy var quotedAuthorLabel: UILabel = {
        let quotedAuthor: String
        if quotedMessage.authorAddress.isLocalAddress {
            quotedAuthor = CommonStrings.you
        } else {
            let authorName = contactsManager.displayName(for: quotedMessage.authorAddress)
            quotedAuthor = String(
                format: NSLocalizedString(
                    "QUOTED_REPLY_AUTHOR_INDICATOR_FORMAT",
                    comment: "Indicates the author of a quoted message. Embeds {{the author's name or phone number}}."
                ),
                authorName
            )
        }

        let label = UILabel()
        label.text = quotedAuthor
        label.font = Layout.quotedAuthorFont
        label.textColor = conversationStyle.quotedReplyAuthorColor()
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.setContentHuggingVerticalHigh()
        label.setContentHuggingHorizontalLow()
        label.setCompressionResistanceHorizontalLow()
        return label
    }()

    private var quotedTextLabelSpoilerAnimator: SpoilerableLabelAnimator?

    private lazy var quotedTextLabel: UILabel = {
        let label = UILabel()

        let attributedText: NSAttributedString
        if let displayableQuotedText, !displayableQuotedText.displayTextValue.isEmpty {
            let config = HydratedMessageBody.DisplayConfiguration.quotedReply(
                font: Layout.quotedTextFont,
                textColor: .fixed(conversationStyle.quotedReplyTextColor())
            )
            attributedText = styleDisplayableQuotedText(
                displayableQuotedText,
                config: config,
                quotedReplyModel: quotedMessage,
                spoilerState: spoilerState
            )
            let animator = SpoilerableLabelAnimator(label: label)
            self.quotedTextLabelSpoilerAnimator = animator
            var spoilerConfig = SpoilerableTextConfig.Builder(isViewVisible: true)
            spoilerConfig.text = displayableQuotedText.displayTextValue
            spoilerConfig.displayConfig = config
            spoilerConfig.animationManager = self.spoilerState.animationManager
            if let config = spoilerConfig.build() {
                animator.updateAnimationState(config)
            } else {
                owsFailDebug("Unable to build spoiler animator")
            }
        } else if let fileTypeForSnippet {
            attributedText = NSAttributedString(
                string: fileTypeForSnippet,
                attributes: [
                    .font: Layout.fileTypeFont,
                    .foregroundColor: conversationStyle.quotedReplyAttachmentColor()
                ]
            )
        } else if let sourceFilename = quotedMessage.sourceFilename?.filterForDisplay {
            attributedText = NSAttributedString(
                string: sourceFilename,
                attributes: [
                    .font: Layout.filenameFont,
                    .foregroundColor: conversationStyle.quotedReplyAttachmentColor()
                ]
            )
        } else if quotedMessage.isGiftBadge {
            attributedText = NSAttributedString(
                string: NSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_REPLY",
                    comment: "Shown when you're replying to a donation message."
                ),
                attributes: [
                    .font: Layout.fileTypeFont,
                    .foregroundColor: conversationStyle.quotedReplyAttachmentColor()
                ]
            )
        } else {
            attributedText = NSAttributedString(
                string: NSLocalizedString(
                    "QUOTED_REPLY_TYPE_ATTACHMENT",
                    comment: "Indicates this message is a quoted reply to an attachment of unknown type."
                ),
                attributes: [
                    .font: Layout.fileTypeFont,
                    .foregroundColor: conversationStyle.quotedReplyAttachmentColor()
                ]
            )
        }
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = displayableQuotedText?.displayTextNaturalAlignment ?? .natural
        label.attributedText = attributedText
        label.setContentHuggingHorizontalLow()
        label.setCompressionResistanceHorizontalLow()
        label.setCompressionResistanceVerticalHigh()
        return label
    }()

    private lazy var quoteContentSourceLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeFootnote
        label.textColor = Theme.lightThemePrimaryColor
        label.text = NSLocalizedString("QUOTED_REPLY_CONTENT_FROM_REMOTE_SOURCE", comment: "")
        return label
    }()

    private func buildRemoteContentSourceView() -> UIView {
        let glyphImageView = UIImageView(image: UIImage(imageLiteralResourceName: "link-slash-compact"))
        glyphImageView.tintColor = Theme.lightThemePrimaryColor
        glyphImageView.autoSetDimensions(to: .square(Layout.remotelySourcedContentGlyphLength))

        let sourceRow = UIStackView(arrangedSubviews: [ glyphImageView, quoteContentSourceLabel ])
        sourceRow.axis = .horizontal
        sourceRow.alignment = .center
        // TODO verify spacing w/ design
        sourceRow.spacing = 3
        sourceRow.isLayoutMarginsRelativeArrangement = true

        let leftMargin: CGFloat = 8
        let rowMargin: CGFloat = 4
        sourceRow.layoutMargins = UIEdgeInsets(top: rowMargin, leading: leftMargin, bottom: rowMargin, trailing: rowMargin)

        sourceRow.addBackgroundView(withBackgroundColor: .ows_whiteAlpha40)

        return sourceRow
    }

    private func buildImageView(image: UIImage) -> UIImageView {
        let imageView = UIImageView(image: image)
        // We need to specify a contentMode since the size of the image
        // might not match the aspect ratio of the view.
        imageView.contentMode = .scaleAspectFill
        // Use trilinear filters for better scaling quality at
        // some performance cost.
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        return imageView
    }

    private enum Layout {
        static let hSpacing: CGFloat = 8

        static var quotedAuthorFont: UIFont {
            UIFont.dynamicTypeSubheadline.semibold()
        }
        static var quotedAuthorHeight: CGFloat {
            ceil(quotedAuthorFont.lineHeight)
        }

        static var quotedTextFont: UIFont {
            .dynamicTypeBody
        }

        static var filenameFont: UIFont {
            quotedTextFont
        }

        static var fileTypeFont: UIFont {
            quotedTextFont.italic()
        }

        static let quotedAttachmentSize: CGFloat = 54

        static let remotelySourcedContentGlyphLength: CGFloat = 16
    }

    private func createViewContents() {
        let maskLayer = CAShapeLayer()
        let innerBubbleView = OWSLayerView(
            frame: .zero,
            layoutCallback: { layerView in
                let bezierPath = UIBezierPath.roundedRect(
                    layerView.bounds,
                    sharpCorners: [ .bottomLeft, .bottomRight ],
                    sharpCornerRadius: 4,
                    wideCornerRadius: 12
                )
                maskLayer.path = bezierPath.cgPath
            }
        )
        innerBubbleView.layer.mask = maskLayer

        // Background
        let chatColorView = CVColorOrGradientView.build(conversationStyle: conversationStyle, referenceView: self)
        chatColorView.shouldDeactivateConstraints = false
        innerBubbleView.addSubview(chatColorView)
        chatColorView.autoPinEdgesToSuperviewEdges()
        let tintView = UIView()
        tintView.backgroundColor = conversationStyle.isDarkThemeEnabled ? .ows_blackAlpha40 : .ows_whiteAlpha60
        innerBubbleView.addSubview(tintView)
        tintView.autoPinEdgesToSuperviewEdges()

        addSubview(innerBubbleView)
        innerBubbleView.autoPinEdgesToSuperviewMargins()

        let hStackView = UIStackView()
        hStackView.axis = .horizontal
        hStackView.spacing = Layout.hSpacing

        let stripeView = UIView()
        stripeView.backgroundColor = .white
        stripeView.autoSetDimension(.width, toSize: 4)
        hStackView.addArrangedSubview(stripeView)

        let vStackView = UIStackView()
        vStackView.axis = .vertical
        vStackView.layoutMargins = UIEdgeInsets(hMargin: 0, vMargin: 7)
        vStackView.isLayoutMarginsRelativeArrangement = true
        vStackView.spacing = 2
        hStackView.addArrangedSubview(vStackView)

        vStackView.addArrangedSubview(quotedAuthorLabel)
        quotedAuthorLabel.autoSetDimension(.height, toSize: Layout.quotedAuthorHeight)

        vStackView.addArrangedSubview(quotedTextLabel)

        let hasQuotedAttachment: Bool = {
            if let contentType = quotedMessage.contentType, contentType != OWSMimeTypeOversizeTextMessage {
                return true
            }
            if quotedMessage.isGiftBadge {
                return true
            }
            return false
        }()
        if hasQuotedAttachment {
            let quotedAttachmentView: UIView

            let tryToLoadThumbnailImage: (() -> UIImage?) = {
                guard let contentType = self.quotedMessage.contentType, TSAttachmentStream.hasThumbnail(forMimeType: contentType) else {
                    return nil
                }
                // TODO: Possibly ignore data that is too large.
                return self.quotedMessage.thumbnailImage
                // TODO: Possibly ignore images that are too large.
           }

            if let thumbnailImage = tryToLoadThumbnailImage() {
                let contentImageView = buildImageView(image: thumbnailImage)
                contentImageView.clipsToBounds = true

                if let contentType = quotedMessage.contentType, MIMETypeUtil.isVideo(contentType) {
                    let playIconImageView = buildImageView(image: UIImage(imageLiteralResourceName: "play-fill"))
                    playIconImageView.tintColor = .white
                    contentImageView.addSubview(playIconImageView)
                    playIconImageView.autoCenterInSuperview()
                }

                quotedAttachmentView = contentImageView
            } else if quotedMessage.failedThumbnailAttachmentPointer != nil {
                let contentImageView = buildImageView(image: UIImage(imageLiteralResourceName: "refresh"))
                contentImageView.contentMode = .scaleAspectFit
                contentImageView.tintColor = .white
                contentImageView.autoSetDimensions(to: .square(Layout.quotedAttachmentSize * 0.5))

                let containerView = UIView.container()
                containerView.backgroundColor = conversationStyle.quotedReplyHighlightColor()
                containerView.addSubview(contentImageView)
                contentImageView.autoCenterInSuperview()

                quotedAttachmentView = containerView
            } else if quotedMessage.isGiftBadge {
                let contentImageView = buildImageView(image: UIImage(imageLiteralResourceName: "gift-thumbnail"))
                contentImageView.contentMode = .scaleAspectFit

                let wrapper = UIView.transparentContainer()
                wrapper.addSubview(contentImageView)
                contentImageView.autoCenterInSuperview()
                contentImageView.autoSetDimension(.width, toSize: Layout.quotedAttachmentSize)

                quotedAttachmentView = wrapper
            } else {
                // TODO: Should we overlay the file extension like we do with CVComponentGenericAttachment?
                let contentImageView = buildImageView(image: UIImage(imageLiteralResourceName: "generic-attachment"))
                contentImageView.autoSetDimension(.width, toSize: Layout.quotedAttachmentSize * 0.5)
                contentImageView.contentMode = .scaleAspectFit

                let wrapper = UIView.transparentContainer()
                wrapper.addSubview(contentImageView)
                contentImageView.autoCenterInSuperview()

                quotedAttachmentView = wrapper
            }

            quotedAttachmentView.autoSetDimensions(to: .square(Layout.quotedAttachmentSize))
            hStackView.addArrangedSubview(quotedAttachmentView)
        } else {
            // If there's no attachment, add an empty view so that
            // the stack view's spacing serves as a margin between
            // the text views and the trailing edge.
            let emptyView = UIView.transparentContainer()
            emptyView.autoSetDimension(.width, toSize: 0)
            hStackView.addArrangedSubview(emptyView)
        }

        let contentView: UIView
        if quotedMessage.isRemotelySourced {
            let quoteSourceWrapper = UIStackView(arrangedSubviews: [ hStackView, buildRemoteContentSourceView() ])
            quoteSourceWrapper.axis = .vertical
            contentView = quoteSourceWrapper
        } else {
            contentView = hStackView
        }

        let cancelButton = UIButton(type: .custom)
        cancelButton.setImage(UIImage(imageLiteralResourceName: "x-20"), for: .normal)
        cancelButton.tintColor = Theme.secondaryTextAndIconColor
        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
        cancelButton.setContentHuggingHorizontalHigh()
        cancelButton.setCompressionResistanceHorizontalHigh()

        let cancelStack = UIStackView(arrangedSubviews: [cancelButton])
        cancelStack.axis = .horizontal
        cancelStack.alignment = .top
        cancelStack.isLayoutMarginsRelativeArrangement = true
        cancelStack.layoutMargins = UIEdgeInsets(top: 6, leading: 2, bottom: 0, trailing: 6)

        let cancelWrapper = UIStackView(arrangedSubviews: [ contentView, cancelStack ])
        cancelWrapper.axis = .horizontal

        innerBubbleView.addSubview(cancelWrapper)
        cancelWrapper.autoPinEdgesToSuperviewEdges()
    }

    @objc
    private func didTapCancel() {
        delegate?.didTapCancelInQuotedMessageSnippet(view: self)
    }

    // MARK: -

    private var fileTypeForSnippet: String? {
        // TODO: Are we going to use the filename?  For all mimetypes?
        guard let contentType = quotedMessage.contentType, !contentType.isEmpty else {
            return nil
        }

        if MIMETypeUtil.isAudio(contentType) {
            return NSLocalizedString(
                "QUOTED_REPLY_TYPE_AUDIO",
                comment: "Indicates this message is a quoted reply to an audio file."
            )
        } else if MIMETypeUtil.isAnimated(contentType) {
            if contentType.caseInsensitiveCompare(OWSMimeTypeImageGif) == .orderedSame {
                return NSLocalizedString(
                    "QUOTED_REPLY_TYPE_GIF",
                    comment: "Indicates this message is a quoted reply to animated GIF file."
                )
            } else {
                return NSLocalizedString(
                    "QUOTED_REPLY_TYPE_IMAGE",
                    comment: "Indicates this message is a quoted reply to an image file."
                )
            }
        } else if let attachmentStream = quotedMessage.attachmentStream, attachmentStream.isLoopingVideo {
            return NSLocalizedString(
                "QUOTED_REPLY_TYPE_GIF",
                comment: "Indicates this message is a quoted reply to animated GIF file."
            )
        } else if MIMETypeUtil.isVideo(contentType) {
            return NSLocalizedString(
                "QUOTED_REPLY_TYPE_VIDEO",
                comment: "Indicates this message is a quoted reply to a video file."
            )
        } else if MIMETypeUtil.isImage(contentType) {
            return NSLocalizedString(
                "QUOTED_REPLY_TYPE_PHOTO",
                comment: "Indicates this message is a quoted reply to a photo file."
            )
        }
        return nil
    }

    private static func displayableTextWithSneakyTransaction(
        forPreview quotedMessage: QuotedReplyModel,
        spoilerState: SpoilerRenderState
    ) -> DisplayableText? {
        guard let text = quotedMessage.body, !text.isEmpty else {
            return nil
        }
        return Self.databaseStorage.read { tx in
            let messageBody = MessageBody(text: text, ranges: quotedMessage.bodyRanges ?? .empty)
            return DisplayableText.displayableText(
                withMessageBody: messageBody,
                transaction: tx
            )
        }
    }

    private func styleDisplayableQuotedText(
        _ displayableQuotedText: DisplayableText,
        config: HydratedMessageBody.DisplayConfiguration,
        quotedReplyModel: QuotedReplyModel,
        spoilerState: SpoilerRenderState
    ) -> NSAttributedString {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: config.baseFont,
            .foregroundColor: config.baseTextColor.forCurrentTheme
        ]
        switch displayableQuotedText.displayTextValue {
        case .text(let text):
            return NSAttributedString(string: text, attributes: baseAttributes)
        case .attributedText(let text):
            let mutable = NSMutableAttributedString(attributedString: text)
            mutable.addAttributesToEntireString(baseAttributes)
            return mutable
        case .messageBody(let messageBody):
            return messageBody.asAttributedStringForDisplay(
                config: config,
                isDarkThemeEnabled: Theme.isDarkThemeEnabled
            )
        }
    }
}
