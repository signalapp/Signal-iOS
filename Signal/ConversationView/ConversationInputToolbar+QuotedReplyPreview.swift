//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol QuotedReplyPreviewDelegate: AnyObject {
    func quotedReplyPreviewDidPressCancel(_ preview: QuotedReplyPreview)
}

final class QuotedReplyPreview: UIView, QuotedMessageSnippetViewDelegate {

    public weak var delegate: QuotedReplyPreviewDelegate?

    private let quotedReplyDraft: DraftQuotedReplyModel
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
        quotedReplyDraft: DraftQuotedReplyModel,
        conversationStyle: ConversationStyle,
        spoilerState: SpoilerRenderState
    ) {
        self.quotedReplyDraft = quotedReplyDraft
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
            quotedMessage: quotedReplyDraft,
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

final private class QuotedMessageSnippetView: UIView {

    weak var delegate: QuotedMessageSnippetViewDelegate?

    private let quotedMessage: DraftQuotedReplyModel
    private let conversationStyle: ConversationStyle
    private let spoilerState: SpoilerRenderState
    private lazy var displayableQuotedText: DisplayableText? = {
        QuotedMessageSnippetView.displayableTextWithSneakyTransaction(
            forPreview: quotedMessage,
            spoilerState: spoilerState
        )
    }()

    init(
        quotedMessage: DraftQuotedReplyModel,
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
        if quotedMessage.isOriginalMessageAuthorLocalUser {
            quotedAuthor = CommonStrings.you
        } else {
            let authorName = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return SSKEnvironment.shared.contactManagerRef.displayName(
                    for: quotedMessage.originalMessageAuthorAddress,
                    tx: tx
                ).resolvedValue()
            }
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
        } else if let sourceFilename = sourceFilenameForSnippet(quotedMessage.content)?.filterForDisplay {
            attributedText = NSAttributedString(
                string: sourceFilename,
                attributes: [
                    .font: Layout.filenameFont,
                    .foregroundColor: conversationStyle.quotedReplyAttachmentColor()
                ]
            )
        } else if quotedMessage.content.isGiftBadge {
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

        self.createContentView(for: quotedMessage.content, in: hStackView)

        let contentView: UIView
        if quotedMessage.content.isRemotelySourced {
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

    private func createContentView(for content: DraftQuotedReplyModel.Content, in hStackView: UIStackView) {
        switch content {
        case let .attachment(_, _, attachment, thumbnailImage):
            let quotedAttachmentView = self.createAttachmentView(attachment, thumbnailImage: thumbnailImage)
            quotedAttachmentView.autoSetDimensions(to: .square(Layout.quotedAttachmentSize))
            hStackView.addArrangedSubview(quotedAttachmentView)

        case .attachmentStub:
            let view = createStubAttachmentView()
            view.autoSetDimensions(to: .square(Layout.quotedAttachmentSize))
            hStackView.addArrangedSubview(view)

        case let .edit(_, _, content):
            return createContentView(for: content, in: hStackView)

        case .giftBadge:
            let contentImageView = buildImageView(image: UIImage(imageLiteralResourceName: "gift-thumbnail"))
            contentImageView.contentMode = .scaleAspectFit

            let wrapper = UIView.transparentContainer()
            wrapper.addSubview(contentImageView)
            contentImageView.autoCenterInSuperview()
            contentImageView.autoSetDimension(.width, toSize: Layout.quotedAttachmentSize)

            wrapper.autoSetDimensions(to: .square(Layout.quotedAttachmentSize))
            hStackView.addArrangedSubview(wrapper)

        case .payment, .text, .viewOnce, .contactShare, .storyReactionEmoji:
            // If there's no attachment, add an empty view so that
            // the stack view's spacing serves as a margin between
            // the text views and the trailing edge.
            let emptyView = UIView.transparentContainer()
            emptyView.autoSetDimension(.width, toSize: 0)
            hStackView.addArrangedSubview(emptyView)
        }
    }

    private func createAttachmentView(_ attachment: Attachment, thumbnailImage: UIImage?) -> UIView {
        let quotedAttachmentView: UIView
        if let thumbnailImage {
            let contentImageView = buildImageView(image: thumbnailImage)
            contentImageView.clipsToBounds = true

            // Mime type is spoofable by the sender but this view doesn't support playback anyway.
            if MimeTypeUtil.isSupportedVideoMimeType(attachment.mimeType) {
                let playIconImageView = buildImageView(image: UIImage(imageLiteralResourceName: "play-fill"))
                playIconImageView.tintColor = .white
                contentImageView.addSubview(playIconImageView)
                playIconImageView.autoCenterInSuperview()
            }

            quotedAttachmentView = contentImageView
        } else if attachment.asAnyPointer() != nil {
            let contentImageView = buildImageView(image: UIImage(imageLiteralResourceName: "refresh"))
            contentImageView.contentMode = .scaleAspectFit
            contentImageView.tintColor = .white
            contentImageView.autoSetDimensions(to: .square(Layout.quotedAttachmentSize * 0.5))

            let containerView = UIView.container()
            containerView.backgroundColor = conversationStyle.quotedReplyHighlightColor()
            containerView.addSubview(contentImageView)
            contentImageView.autoCenterInSuperview()

            quotedAttachmentView = containerView
        } else {
            quotedAttachmentView = createStubAttachmentView()
        }
        return quotedAttachmentView
    }

    private func createStubAttachmentView() -> UIView {
        // TODO: Should we overlay the file extension like we do with CVComponentGenericAttachment?
        let contentImageView = buildImageView(image: UIImage(imageLiteralResourceName: "generic-attachment"))
        contentImageView.autoSetDimension(.width, toSize: Layout.quotedAttachmentSize * 0.5)
        contentImageView.contentMode = .scaleAspectFit

        let wrapper = UIView.transparentContainer()
        wrapper.addSubview(contentImageView)
        contentImageView.autoCenterInSuperview()
        return wrapper
    }

    @objc
    private func didTapCancel() {
        delegate?.didTapCancelInQuotedMessageSnippet(view: self)
    }

    // MARK: -

    private func mimeTypeAndIsLooping(_ content: DraftQuotedReplyModel.Content) -> (String, Bool)? {
        switch content {
        case .attachmentStub(_, let stub) where stub.mimeType != nil:
            return (stub.mimeType!, false)
        case .attachment(_, let reference, let attachment, _):
            return (attachment.mimeType, reference.renderingFlag == .shouldLoop)
        case .edit(_, _, let innerContent):
            return mimeTypeAndIsLooping(innerContent)
        case .giftBadge, .text, .payment, .attachmentStub, .viewOnce, .contactShare, .storyReactionEmoji:
            return nil
        }
    }

    private var fileTypeForSnippet: String? {
        guard let (mimeType, isLoopingVideo) = mimeTypeAndIsLooping(quotedMessage.content) else {
            return nil
        }

        if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
            return NSLocalizedString(
                "QUOTED_REPLY_TYPE_AUDIO",
                comment: "Indicates this message is a quoted reply to an audio file."
            )
        } else if MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(mimeType) {
            if mimeType.caseInsensitiveCompare(MimeType.imageGif.rawValue) == .orderedSame {
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
        } else if isLoopingVideo && MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            return NSLocalizedString(
                "QUOTED_REPLY_TYPE_GIF",
                comment: "Indicates this message is a quoted reply to animated GIF file."
            )
        } else if MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            return NSLocalizedString(
                "QUOTED_REPLY_TYPE_VIDEO",
                comment: "Indicates this message is a quoted reply to a video file."
            )
        } else if MimeTypeUtil.isSupportedImageMimeType(mimeType) {
            return NSLocalizedString(
                "QUOTED_REPLY_TYPE_PHOTO",
                comment: "Indicates this message is a quoted reply to a photo file."
            )
        }
        return nil
    }

    private func sourceFilenameForSnippet(_ content: DraftQuotedReplyModel.Content) -> String? {
        switch content {
        case .attachmentStub(_, let stub):
            return stub.sourceFilename
        case .attachment(_, let reference, _, _):
            return reference.sourceFilename
        case .edit(_, _, let innerContent):
            return sourceFilenameForSnippet(innerContent)
        case .giftBadge, .text, .payment, .contactShare, .viewOnce, .storyReactionEmoji:
            return nil
        }
    }

    private static func displayableTextWithSneakyTransaction(
        forPreview quotedMessage: DraftQuotedReplyModel,
        spoilerState: SpoilerRenderState
    ) -> DisplayableText? {
        guard
            let body = quotedMessage.bodyForSending,
            !body.text.isEmpty
        else {
            return nil
        }
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            return DisplayableText.displayableText(
                withMessageBody: body,
                transaction: tx
            )
        }
    }

    private func styleDisplayableQuotedText(
        _ displayableQuotedText: DisplayableText,
        config: HydratedMessageBody.DisplayConfiguration,
        quotedReplyModel: DraftQuotedReplyModel,
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
