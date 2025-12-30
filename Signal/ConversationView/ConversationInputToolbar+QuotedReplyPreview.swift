//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol QuotedReplyPreviewDelegate: AnyObject {
    func quotedReplyPreviewDidPressCancel(_ preview: QuotedReplyPreview)
}

class QuotedReplyPreview: UIView, QuotedMessageSnippetViewDelegate {

    weak var delegate: QuotedReplyPreviewDelegate?

    private let quotedReplyDraft: DraftQuotedReplyModel
    private let spoilerState: SpoilerRenderState
    private var quotedMessageView: QuotedMessageSnippetView?
    private var heightConstraint: NSLayoutConstraint!

    private weak var contentView: UIView?

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
        spoilerState: SpoilerRenderState,
    ) {
        self.quotedReplyDraft = quotedReplyDraft
        self.spoilerState = spoilerState

        super.init(frame: .zero)

        directionalLayoutMargins = .init(hMargin: 8, vMargin: 0)

        contentView = self

        // Background with rounded corners.
        let backgroundView: UIView
        if #available(iOS 26, *) {
            clipsToBounds = true
            cornerConfiguration = .uniformCorners(radius: .containerConcentric(minimum: 12))

            let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))

            // Colored overlay on top of blur.
            let dimmingView = UIView()
            dimmingView.backgroundColor = .Signal.secondaryFill
            dimmingView.translatesAutoresizingMaskIntoConstraints = false
            blurEffectView.contentView.addSubview(dimmingView)
            NSLayoutConstraint.activate([
                dimmingView.topAnchor.constraint(equalTo: blurEffectView.topAnchor),
                dimmingView.leadingAnchor.constraint(equalTo: blurEffectView.leadingAnchor),
                dimmingView.trailingAnchor.constraint(equalTo: blurEffectView.trailingAnchor),
                dimmingView.bottomAnchor.constraint(equalTo: blurEffectView.bottomAnchor),
            ])

            contentView = blurEffectView.contentView
            backgroundView = blurEffectView
        } else {
            let maskLayer = CAShapeLayer()
            backgroundView = OWSLayerView(
                frame: .zero,
                layoutCallback: { layerView in
                    maskLayer.path = UIBezierPath(roundedRect: layerView.bounds, cornerRadius: 12).cgPath
                },
            )
            backgroundView.layer.mask = maskLayer
            backgroundView.backgroundColor = .Signal.secondaryFill
        }
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        addConstraints([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        reloadMessageSnippet()

        // Quoted message text is complicated and is constructed via AttributedString.
        // Simply reload message preview view when font size changes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil,
        )
    }

    private func reloadMessageSnippet() {
        if let quotedMessageView {
            quotedMessageView.removeFromSuperview()
        }

        // We instantiate quotedMessageView late to ensure that it is updated
        // every time contentSizeCategoryDidChange (i.e. when dynamic type
        // sizes changes).
        let quotedMessageView = QuotedMessageSnippetView(
            quotedMessage: quotedReplyDraft,
            spoilerState: spoilerState,
        )
        quotedMessageView.delegate = self
        quotedMessageView.translatesAutoresizingMaskIntoConstraints = false
        let contentView = contentView ?? self
        contentView.addSubview(quotedMessageView)
        addConstraints([
            quotedMessageView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            quotedMessageView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            quotedMessageView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            quotedMessageView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])

        self.quotedMessageView = quotedMessageView
    }

    @objc
    private func contentSizeCategoryDidChange(_ notification: Notification) {
        reloadMessageSnippet()
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

    private let quotedMessage: DraftQuotedReplyModel
    private let spoilerState: SpoilerRenderState
    private lazy var displayableQuotedText: DisplayableText? = {
        QuotedMessageSnippetView.displayableTextWithSneakyTransaction(
            forPreview: quotedMessage,
            spoilerState: spoilerState,
        )
    }()

    init(
        quotedMessage: DraftQuotedReplyModel,
        spoilerState: SpoilerRenderState,
    ) {
        self.quotedMessage = quotedMessage
        self.spoilerState = spoilerState

        super.init(frame: .zero)

        isUserInteractionEnabled = true
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
                    tx: tx,
                ).resolvedValue()
            }
            quotedAuthor = String(
                format: NSLocalizedString(
                    "QUOTED_REPLY_AUTHOR_INDICATOR_FORMAT",
                    comment: "Indicates the author of a quoted message. Embeds {{the author's name or phone number}}.",
                ),
                authorName,
            )
        }

        let label = UILabel()
        label.text = quotedAuthor
        label.font = Layout.quotedAuthorFont
        label.textColor = ConversationInputToolbar.Style.primaryTextColor
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.setContentHuggingVerticalHigh()
        label.setContentHuggingHorizontalLow()
        label.setCompressionResistanceVerticalHigh()
        label.setCompressionResistanceHorizontalLow()
        return label
    }()

    private var quotedTextLabelSpoilerAnimator: SpoilerableLabelAnimator?

    private lazy var quotedTextLabel: UILabel = {
        let label = UILabel()

        let attributedText: NSAttributedString
        if
            let displayableQuotedText,
            !displayableQuotedText.displayTextValue.isEmpty,
            !quotedMessage.content.isPoll
        {
            let config = HydratedMessageBody.DisplayConfiguration.quotedReply(
                font: Layout.quotedTextFont,
                textColor: .fixed(ConversationInputToolbar.Style.primaryTextColor),
            )
            attributedText = styleDisplayableQuotedText(
                displayableQuotedText,
                config: config,
                quotedReplyModel: quotedMessage,
                spoilerState: spoilerState,
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
                    .foregroundColor: ConversationInputToolbar.Style.secondaryTextColor,
                ],
            )
        } else if let sourceFilename = sourceFilenameForSnippet(quotedMessage.content)?.filterForDisplay {
            attributedText = NSAttributedString(
                string: sourceFilename,
                attributes: [
                    .font: Layout.filenameFont,
                    .foregroundColor: ConversationInputToolbar.Style.secondaryTextColor,
                ],
            )
        } else if quotedMessage.content.isGiftBadge {
            attributedText = NSAttributedString(
                string: NSLocalizedString(
                    "DONATION_ON_BEHALF_OF_A_FRIEND_REPLY",
                    comment: "Shown when you're replying to a donation message.",
                ),
                attributes: [
                    .font: Layout.fileTypeFont,
                    .foregroundColor: ConversationInputToolbar.Style.secondaryTextColor,
                ],
            )
        } else if quotedMessage.content.isPoll {
            switch quotedMessage.content {
            case .poll(let pollQuestion):
                let pollIcon = SignalSymbol.poll.attributedString(dynamicTypeBaseSize: Layout.fileTypeFont.pointSize) + " "
                let pollPrefix = OWSLocalizedString(
                    "POLL_LABEL",
                    comment: "Label specifying the message type as a poll",
                ) + ": "

                attributedText = pollIcon + NSAttributedString(
                    string: pollPrefix + pollQuestion,
                    attributes: [
                        .font: Layout.fileTypeFont,
                        .foregroundColor: ConversationInputToolbar.Style.secondaryTextColor,
                    ],
                )
            default:
                owsFailDebug("Quoted message is poll but there's no poll")
                attributedText = NSAttributedString(
                    string: NSLocalizedString(
                        "QUOTED_REPLY_TYPE_ATTACHMENT",
                        comment: "Indicates this message is a quoted reply to an attachment of unknown type.",
                    ),
                    attributes: [
                        .font: Layout.fileTypeFont,
                        .foregroundColor: ConversationInputToolbar.Style.secondaryTextColor,
                    ],
                )
            }
        } else {
            attributedText = NSAttributedString(
                string: NSLocalizedString(
                    "QUOTED_REPLY_TYPE_ATTACHMENT",
                    comment: "Indicates this message is a quoted reply to an attachment of unknown type.",
                ),
                attributes: [
                    .font: Layout.fileTypeFont,
                    .foregroundColor: ConversationInputToolbar.Style.secondaryTextColor,
                ],
            )
        }
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = displayableQuotedText?.displayTextNaturalAlignment ?? .natural
        label.attributedText = attributedText
        label.setContentHuggingVerticalHigh()
        label.setContentHuggingHorizontalLow()
        label.setCompressionResistanceVerticalHigh()
        label.setCompressionResistanceHorizontalLow()
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

        let sourceRow = UIStackView(arrangedSubviews: [glyphImageView, quoteContentSourceLabel])
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
        static var quotedAuthorFont: UIFont {
            UIFont.dynamicTypeFootnoteClamped.semibold()
        }

        static var quotedTextFont: UIFont {
            .dynamicTypeSubheadlineClamped
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
        // Quoted text and message author, media thumbnail if any.
        let horizonalStack = UIStackView(arrangedSubviews: [])
        horizonalStack.axis = .horizontal
        horizonalStack.spacing = 8

        let stripeView = UIView()
        stripeView.backgroundColor = .Signal.quaternaryLabel
        horizonalStack.addArrangedSubview(stripeView)
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            stripeView.cornerConfiguration = .capsule()
        }
#endif

        let textStack = UIStackView(arrangedSubviews: [quotedAuthorLabel, quotedTextLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        // Putting vertical stack in a container allows to center that text stack vertically
        // when the image is taller than text, as well as add top and bottom margins.
        let textStackContainer = UIView.container()
        textStackContainer.addSubview(textStack)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStackContainer.addSubview(stripeView)
        stripeView.translatesAutoresizingMaskIntoConstraints = false
        textStackContainer.addConstraints([
            stripeView.leadingAnchor.constraint(equalTo: textStackContainer.leadingAnchor),
            stripeView.widthAnchor.constraint(equalToConstant: 4),
            stripeView.topAnchor.constraint(equalTo: textStack.topAnchor),
            stripeView.bottomAnchor.constraint(equalTo: textStack.bottomAnchor),

            textStack.leadingAnchor.constraint(equalTo: stripeView.trailingAnchor, constant: 8),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: textStackContainer.topAnchor, constant: 8),
            {
                let c = textStack.topAnchor.constraint(equalTo: textStackContainer.topAnchor, constant: 8)
                c.priority = .defaultLow
                return c
            }(),
            textStack.centerYAnchor.constraint(equalTo: textStackContainer.centerYAnchor),
            textStack.trailingAnchor.constraint(equalTo: textStackContainer.trailingAnchor),
        ])
        horizonalStack.addArrangedSubview(textStackContainer)

        createContentView(for: quotedMessage.content, in: horizonalStack)

        // If there's no local copy of the quoted message we display some extra text below
        // by wrapping what we have so far in a vertical stack view.
        let contentView: UIView
        if quotedMessage.content.isRemotelySourced {
            let quoteSourceWrapper = UIStackView(arrangedSubviews: [horizonalStack, buildRemoteContentSourceView()])
            quoteSourceWrapper.axis = .vertical
            contentView = quoteSourceWrapper
        } else {
            contentView = horizonalStack
        }

        // (X) button.
        let cancelButton = UIButton(
            configuration: .bordered(),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapCancel()
            },
        )
        cancelButton.configuration?.image = UIImage(imageLiteralResourceName: "x-compact-bold")
        cancelButton.configuration?.baseBackgroundColor = .init(dynamicProvider: { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(rgbHex: 0x787880, alpha: 0.4)
                : UIColor(rgbHex: 0xF5F5F5, alpha: 0.9)
        })
        cancelButton.configuration?.background.visualEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        cancelButton.tintColor = ConversationInputToolbar.Style.primaryTextColor
        cancelButton.configuration?.cornerStyle = .capsule
        cancelButton.setContentHuggingHorizontalHigh()
        cancelButton.setCompressionResistanceHorizontalHigh()

        // Put the button in a container and align it to the top.
        let cancelButtonContainer = UIView.container()
        cancelButtonContainer.addSubview(cancelButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButtonContainer.addConstraints([
            cancelButton.widthAnchor.constraint(equalToConstant: 24),
            cancelButton.heightAnchor.constraint(equalToConstant: 24),

            cancelButton.topAnchor.constraint(equalTo: cancelButtonContainer.topAnchor, constant: 8),
            cancelButton.leadingAnchor.constraint(equalTo: cancelButtonContainer.leadingAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: cancelButtonContainer.trailingAnchor),
            cancelButton.bottomAnchor.constraint(lessThanOrEqualTo: cancelButtonContainer.bottomAnchor),
        ])

        // One more horizontal stack to hold everything.
        let outermostHStack = UIStackView(arrangedSubviews: [contentView, cancelButtonContainer])
        outermostHStack.axis = .horizontal
        outermostHStack.spacing = 8
        outermostHStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outermostHStack)
        addConstraints([
            outermostHStack.topAnchor.constraint(equalTo: topAnchor),
            outermostHStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            outermostHStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            outermostHStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func createContentView(for content: DraftQuotedReplyModel.Content, in stackView: UIStackView) {
        var thumbnailView: UIView?

        switch content {
        case let .attachment(_, _, attachment, thumbnailImage):
            thumbnailView = createAttachmentView(attachment, thumbnailImage: thumbnailImage)

        case .attachmentStub:
            thumbnailView = createStubAttachmentView()

        case let .edit(_, _, content):
            createContentView(for: content, in: stackView)
            return

        case .giftBadge:
            let imageView = buildImageView(image: UIImage(imageLiteralResourceName: "gift-thumbnail"))
            imageView.contentMode = .scaleAspectFit
            thumbnailView = imageView

        case .payment, .text, .viewOnce, .contactShare, .storyReactionEmoji, .poll:
            break
        }

        guard let thumbnailView else { return }

        let containerView = UIView.container()
        containerView.addSubview(thumbnailView)
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addConstraints([
            thumbnailView.topAnchor.constraint(equalTo: containerView.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            // Always fixed width.
            thumbnailView.widthAnchor.constraint(equalToConstant: Layout.quotedAttachmentSize),

            // Stretch thumbnail to fill height if text requires more vertical space than
            // default height of the thumbnail provides.
            {
                let c = thumbnailView.heightAnchor.constraint(equalToConstant: Layout.quotedAttachmentSize)
                // Lower than vertical compression resistance on the text labels.
                c.priority = .defaultHigh
                return c
            }(),
        ])
        stackView.addArrangedSubview(containerView)
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
                playIconImageView.translatesAutoresizingMaskIntoConstraints = false
                contentImageView.addConstraints([
                    playIconImageView.centerYAnchor.constraint(equalTo: contentImageView.centerYAnchor),
                    playIconImageView.centerXAnchor.constraint(equalTo: contentImageView.centerXAnchor),
                ])
            }

            quotedAttachmentView = contentImageView
        } else if attachment.asAnyPointer() != nil {
            let refreshIcon = buildImageView(image: UIImage(imageLiteralResourceName: "refresh"))
            refreshIcon.contentMode = .scaleAspectFit
            refreshIcon.tintColor = .Signal.tertiaryLabel

            let containerView = UIView.container()
            containerView.backgroundColor = .Signal.tertiaryBackground
            containerView.addSubview(refreshIcon)
            refreshIcon.translatesAutoresizingMaskIntoConstraints = false
            containerView.addConstraints([
                refreshIcon.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                refreshIcon.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            ])

            quotedAttachmentView = containerView
        } else {
            quotedAttachmentView = createStubAttachmentView()
        }
        return quotedAttachmentView
    }

    // Return generic attachment image centered in a container view.
    private func createStubAttachmentView() -> UIView {
        // TODO: Should we overlay the file extension like we do with CVComponentGenericAttachment?
        let imageView = buildImageView(image: UIImage(imageLiteralResourceName: "generic-attachment"))
        imageView.contentMode = .scaleAspectFit

        let containerView = UIView.container()
        containerView.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addConstraints([
            imageView.topAnchor.constraint(greaterThanOrEqualTo: containerView.topAnchor),
            imageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            imageView.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor),
            imageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
        ])
        return containerView
    }

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
        case .giftBadge, .text, .payment, .attachmentStub, .viewOnce, .contactShare, .storyReactionEmoji, .poll:
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
                comment: "Indicates this message is a quoted reply to an audio file.",
            )
        } else if MimeTypeUtil.isSupportedDefinitelyAnimatedMimeType(mimeType) {
            if mimeType.caseInsensitiveCompare(MimeType.imageGif.rawValue) == .orderedSame {
                return NSLocalizedString(
                    "QUOTED_REPLY_TYPE_GIF",
                    comment: "Indicates this message is a quoted reply to animated GIF file.",
                )
            } else {
                return NSLocalizedString(
                    "QUOTED_REPLY_TYPE_IMAGE",
                    comment: "Indicates this message is a quoted reply to an image file.",
                )
            }
        } else if isLoopingVideo, MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            return NSLocalizedString(
                "QUOTED_REPLY_TYPE_GIF",
                comment: "Indicates this message is a quoted reply to animated GIF file.",
            )
        } else if MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            return NSLocalizedString(
                "QUOTED_REPLY_TYPE_VIDEO",
                comment: "Indicates this message is a quoted reply to a video file.",
            )
        } else if MimeTypeUtil.isSupportedImageMimeType(mimeType) {
            return NSLocalizedString(
                "QUOTED_REPLY_TYPE_PHOTO",
                comment: "Indicates this message is a quoted reply to a photo file.",
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
        case .giftBadge, .text, .payment, .contactShare, .viewOnce, .storyReactionEmoji, .poll:
            return nil
        }
    }

    private static func displayableTextWithSneakyTransaction(
        forPreview quotedMessage: DraftQuotedReplyModel,
        spoilerState: SpoilerRenderState,
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
                transaction: tx,
            )
        }
    }

    private func styleDisplayableQuotedText(
        _ displayableQuotedText: DisplayableText,
        config: HydratedMessageBody.DisplayConfiguration,
        quotedReplyModel: DraftQuotedReplyModel,
        spoilerState: SpoilerRenderState,
    ) -> NSAttributedString {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: config.baseFont,
            .foregroundColor: config.baseTextColor.forCurrentTheme,
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
                isDarkThemeEnabled: Theme.isDarkThemeEnabled,
            )
        }
    }
}
