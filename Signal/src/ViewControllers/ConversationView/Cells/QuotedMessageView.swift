//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

public protocol QuotedMessageViewDelegate: AnyObject {

    func didTapQuotedReply(_ quotedReply: QuotedReplyModel,
                           failedThumbnailDownloadAttachmentPointer attachmentPointer: TSAttachmentPointer)

    func didCancelQuotedReply()
}

// MARK: -

public class QuotedMessageView: ManualStackViewWithLayer {

    public struct State: Equatable {
        let quotedReplyModel: QuotedReplyModel
        let displayableQuotedText: DisplayableText?
        let conversationStyle: ConversationStyle
        let isOutgoing: Bool
        let isForPreview: Bool
        let quotedAuthorName: String

        var quotedInteractionIdentifier: InteractionSnapshotIdentifier {
            return InteractionSnapshotIdentifier(
                timestamp: quotedReplyModel.timestamp,
                authorUuid: quotedReplyModel.authorAddress.uuidString
            )
        }
    }

    private var state: State?

    private weak var delegate: QuotedMessageViewDelegate?

    private let hStack = ManualStackView(name: "hStack")
    private let innerVStack = ManualStackView(name: "innerVStack")
    private let outerVStack = ManualStackView(name: "outerVStack")
    private let remotelySourcedContentStack = ManualStackViewWithLayer(name: "remotelySourcedContentStack")

    private let stripeView = UIView()
    private let quotedAuthorLabel = CVLabel()
    private let quotedTextLabel = CVLabel()
    private let quoteContentSourceLabel = CVLabel()
    private let quoteReactionHeaderLabel = CVLabel()
    private let quoteReactionLabel = CVLabel()
    private let quotedImageView = CVImageView()
    private let remotelySourcedContentIconView = CVImageView()

    // Background
    private let bubbleView = ManualLayoutViewWithLayer(name: "bubbleView")
    private let chatColorView = CVColorOrGradientView()
    private let tintView = ManualLayoutViewWithLayer(name: "tintView")

    static func stateForConversation(
        quotedReplyModel: QuotedReplyModel,
        displayableQuotedText: DisplayableText?,
        conversationStyle: ConversationStyle,
        isOutgoing: Bool,
        transaction: SDSAnyReadTransaction
    ) -> State {

        let quotedAuthorName = contactsManager.displayName(for: quotedReplyModel.authorAddress,
                                                           transaction: transaction)

        return State(quotedReplyModel: quotedReplyModel,
                     displayableQuotedText: displayableQuotedText,
                     conversationStyle: conversationStyle,
                     isOutgoing: isOutgoing,
                     isForPreview: false,
                     quotedAuthorName: quotedAuthorName)
    }

    static func stateForPreview(
        quotedReplyModel: QuotedReplyModel,
        conversationStyle: ConversationStyle,
        transaction: SDSAnyReadTransaction
    ) -> State {

        let quotedAuthorName = contactsManager.displayName(
            for: quotedReplyModel.authorAddress,
            transaction: transaction
        )

        var displayableQuotedText: DisplayableText?
        if let body = quotedReplyModel.body, !body.isEmpty {
            let messageBody = MessageBody(text: body, ranges: quotedReplyModel.bodyRanges ?? .empty)
            displayableQuotedText = DisplayableText.displayableText(
                withMessageBody: messageBody,
                transaction: transaction
            )
        }

        return State(
            quotedReplyModel: quotedReplyModel,
            displayableQuotedText: displayableQuotedText,
            conversationStyle: conversationStyle,
            isOutgoing: true,
            isForPreview: true,
            quotedAuthorName: quotedAuthorName
        )
    }

    // The Configurator can be used to:
    //
    // * Configure this view for rendering.
    // * Measure this view _without_ creating its views.
    private struct Configurator {
        let state: State

        var quotedReplyModel: QuotedReplyModel { state.quotedReplyModel }
        var displayableQuotedText: DisplayableText? { state.displayableQuotedText }
        var conversationStyle: ConversationStyle { state.conversationStyle }
        var isOutgoing: Bool { state.isOutgoing }
        var isIncoming: Bool { !isOutgoing }
        var isForPreview: Bool { state.isForPreview }
        var quotedAuthorName: String { state.quotedAuthorName }

        let stripeThickness: CGFloat = 4
        var quotedAuthorFont: UIFont { UIFont.dynamicTypeSubheadlineClamped.semibold() }
        var quotedAuthorColor: UIColor { conversationStyle.quotedReplyAuthorColor() }
        var quotedTextColor: UIColor { conversationStyle.quotedReplyTextColor() }
        var quotedTextFont: UIFont { UIFont.dynamicTypeBody2 }
        var fileTypeTextColor: UIColor { conversationStyle.quotedReplyAttachmentColor() }
        var fileTypeFont: UIFont { quotedTextFont.italic() }
        var filenameTextColor: UIColor { conversationStyle.quotedReplyAttachmentColor() }
        var filenameFont: UIFont { quotedTextFont }
        var quotedAuthorHeight: CGFloat { quotedAuthorFont.lineHeight }
        let quotedAttachmentSizeWithoutQuotedText: CGFloat = 64
        let quotedAttachmentSizeWithQuotedText: CGFloat = 72
        var quotedAttachmentSize: CGSize {
            let height = hasQuotedText ? quotedAttachmentSizeWithQuotedText : quotedAttachmentSizeWithoutQuotedText
            if quotedReplyModel.isStory {
                return CGSize(width: 0.625 * height, height: height)
            } else {
                return CGSize(square: height)
            }
        }
        var quotedReactionRect: CGRect {
            CGRect(x: 0, y: quotedAttachmentSize.height - 32, width: hasQuotedThumbnail ? 32 : 40, height: 32)
        }
        let remotelySourcedContentIconSize: CGFloat = 16
        let cancelIconSize: CGFloat = 20
        let cancelIconMargins = UIEdgeInsets(top: 6, leading: 6, bottom: 0, trailing: 6)

        var outerStackConfig: CVStackViewConfig {
            CVStackViewConfig(axis: .vertical,
                              alignment: .fill,
                              spacing: 8,
                              layoutMargins: UIEdgeInsets(hMargin: isForPreview ? 0 : 8,
                                                          vMargin: 0))
        }

        var hStackConfig: CVStackViewConfig {
            CVStackViewConfig(axis: .horizontal,
                              alignment: .fill,
                              spacing: 8,
                              layoutMargins: .zero)
        }

        var innerVStackConfig: CVStackViewConfig {
            CVStackViewConfig(axis: .vertical,
                              alignment: .leading,
                              spacing: 2,
                              layoutMargins: UIEdgeInsets(hMargin: 0, vMargin: 6))
        }

        var outerVStackConfig: CVStackViewConfig {
            CVStackViewConfig(axis: .vertical,
                              alignment: .fill,
                              spacing: 0,
                              layoutMargins: .zero)
        }

        var remotelySourcedContentStackConfig: CVStackViewConfig {
            CVStackViewConfig(axis: .horizontal,
                              alignment: .center,
                              spacing: 3,
                              layoutMargins: UIEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 4))
        }

        var hasQuotedThumbnail: Bool {
            contentTypeWithThumbnail != nil || quotedReplyModel.thumbnailViewFactory != nil || quotedReplyModel.isGiftBadge
        }

        var hasReaction: Bool {
            quotedReplyModel.reactionEmoji != nil
        }

        var contentType: String? {
            guard let contentType = quotedReplyModel.contentType,
                  !contentType.isEmpty else {
                return nil
            }
            return contentType
        }

        var contentTypeWithThumbnail: String? {
            guard let contentType = self.contentType else {
                return nil
            }
            guard contentType != OWSMimeTypeOversizeTextMessage else {
                return nil
            }
            return contentType
        }

        var isAudioAttachment: Bool {
            // TODO: Are we going to use the filename?  For all mimetypes?
            guard let contentType = self.contentType else {
                return false
            }
            return MIMETypeUtil.isAudio(contentType)
        }

        var isVideoAttachment: Bool {
            // TODO: Are we going to use the filename?  For all mimetypes?
            guard let contentType = self.contentType else {
                return false
            }
            return MIMETypeUtil.isVideo(contentType)
        }

        var highlightColor: UIColor {
            conversationStyle.quotedReplyHighlightColor()
        }

        var quotedAuthorLabelConfig: CVLabelConfig {
            let authorName: String
            if quotedReplyModel.authorAddress.isLocalAddress {
                authorName = CommonStrings.you
            } else {
                authorName = quotedAuthorName
            }

            let text: String
            if quotedReplyModel.isStory {
                let format = OWSLocalizedString("QUOTED_REPLY_STORY_AUTHOR_INDICATOR_FORMAT",
                                               comment: "Message header when you are quoting a story. Embeds {{ story author name }}")
                text = String(format: format, authorName)
            } else {
                text = authorName
            }

            return CVLabelConfig.unstyledText(
                text,
                font: quotedAuthorFont,
                textColor: quotedAuthorColor,
                numberOfLines: 1,
                lineBreakMode: .byTruncatingTail
            )
        }

        var hasQuotedText: Bool {
            if let displayableQuotedText = self.displayableQuotedText,
               !displayableQuotedText.displayTextValue.isEmpty {
                return true
            } else {
                return false
            }
        }
        var quotedTextLabelConfig: CVLabelConfig {
            let labelText: CVTextValue
            var textAlignment: NSTextAlignment?

            let displayTextValue = self.displayableQuotedText?.displayTextValue.nilIfEmpty

            switch displayTextValue {
            case .text(let text):
                labelText = .text(text)
                textAlignment = text.naturalTextAlignment
            case .attributedText(let attributedText):
                let mutableText = NSMutableAttributedString(attributedString: attributedText)
                mutableText.addAttributesToEntireString([
                    .font: quotedTextFont,
                    .foregroundColor: quotedTextColor
                ])
                labelText = .attributedText(mutableText)
                textAlignment = attributedText.string.naturalTextAlignment
            case .messageBody(let messageBody):
                labelText = .messageBody(messageBody)
                textAlignment = messageBody.naturalTextAlignment
            case .none:
                if let fileTypeForSnippet = self.fileTypeForSnippet {
                    labelText = .attributedText(NSAttributedString(
                        string: fileTypeForSnippet,
                        attributes: [
                            .font: fileTypeFont,
                            .foregroundColor: fileTypeTextColor
                        ]
                    ))
                } else if let sourceFilename = quotedReplyModel.sourceFilename?.filterStringForDisplay() {
                    labelText = .attributedText(NSAttributedString(
                        string: sourceFilename,
                        attributes: [
                            .font: filenameFont,
                            .foregroundColor: filenameTextColor
                        ]
                    ))
                } else if self.quotedReplyModel.isGiftBadge {
                    labelText = .attributedText(NSAttributedString(
                        string: OWSLocalizedString(
                            "DONATION_ON_BEHALF_OF_A_FRIEND_REPLY",
                            comment: "Shown when you're replying to a donation message."
                        ),
                        // This appears in the same context as fileType, so use the same font/color.
                        attributes: [.font: self.fileTypeFont, .foregroundColor: self.fileTypeTextColor]
                    ))
                } else {
                    let string = OWSLocalizedString("QUOTED_REPLY_TYPE_ATTACHMENT",
                                                    comment: "Indicates this message is a quoted reply to an attachment of unknown type.")
                    labelText = .attributedText(NSAttributedString(
                        string: string,
                        attributes: [
                            .font: fileTypeFont,
                            .foregroundColor: fileTypeTextColor
                        ]
                    ))
                }
            }

            let displayConfig = HydratedMessageBody.DisplayConfiguration.quotedReply(
                font: quotedTextFont,
                textColor: .fixed(quotedTextColor)
            )

            return CVLabelConfig(
                text: labelText,
                displayConfig: displayConfig,
                font: quotedTextFont,
                textColor: quotedTextColor,
                numberOfLines: isForPreview || hasQuotedThumbnail ? 1 : 2,
                lineBreakMode: .byTruncatingTail,
                textAlignment: textAlignment
            )
        }

        var quoteContentSourceLabelConfig: CVLabelConfig {
            let text = OWSLocalizedString("QUOTED_REPLY_CONTENT_FROM_REMOTE_SOURCE",
                                         comment: "Footer label that appears below quoted messages when the quoted content was not derived locally. When the local user doesn't have a copy of the message being quoted, e.g. if it had since been deleted, we instead show the content specified by the sender.")
            return CVLabelConfig.unstyledText(
                text,
                font: UIFont.dynamicTypeFootnote,
                textColor: Theme.lightThemePrimaryColor,
                numberOfLines: 0,
                lineBreakMode: .byWordWrapping
            )
        }

        var quoteReactionHeaderLabelConfig: CVLabelConfig {
            let text: String
            if quotedReplyModel.authorAddress.isLocalAddress {
                text = OWSLocalizedString("QUOTED_REPLY_REACTION_TO_OWN_STORY",
                                         comment: "Header label that appears above quoted messages when the quoted content was includes a reaction to your own story.")
            } else {
                let formatText = OWSLocalizedString("QUOTED_REPLY_REACTION_TO_STORY_FORMAT",
                                                   comment: "Header label that appears above quoted messages when the quoted content was includes a reaction to a story. Embeds {{ story author name }}")
                text = String(format: formatText, quotedAuthorName)
            }

            return CVLabelConfig.unstyledText(
                text,
                font: UIFont.dynamicTypeFootnote,
                textColor: conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming)
            )
        }

        var quoteReactionLabelConfig: CVLabelConfig {
            let font = UIFont.systemFont(ofSize: 28)
            return CVLabelConfig(
                text: .attributedText((quotedReplyModel.reactionEmoji ?? "").styled(with: .lineHeightMultiple(0.6))),
                displayConfig: .forUnstyledText(font: font, textColor: quotedTextColor),
                font: font,
                textColor: quotedTextColor
            )
        }

        var fileTypeForSnippet: String? {
            // TODO: Are we going to use the filename?  For all mimetypes?
            guard let contentType = self.contentType else {
                return nil
            }

            if MIMETypeUtil.isAudio(contentType) {
                return OWSLocalizedString("QUOTED_REPLY_TYPE_AUDIO",
                                         comment: "Indicates this message is a quoted reply to an audio file.")
            } else if MIMETypeUtil.isVideo(contentType) {
                return OWSLocalizedString("QUOTED_REPLY_TYPE_VIDEO",
                                         comment: "Indicates this message is a quoted reply to a video file.")
            } else if MIMETypeUtil.isAnimated(contentType) {
                if contentType.caseInsensitiveCompare(OWSMimeTypeImageGif) == .orderedSame {
                    return OWSLocalizedString("QUOTED_REPLY_TYPE_GIF",
                                             comment: "Indicates this message is a quoted reply to animated GIF file.")
                } else {
                    return OWSLocalizedString("QUOTED_REPLY_TYPE_IMAGE",
                                             comment: "Indicates this message is a quoted reply to an image file.")
                }
            } else if MIMETypeUtil.isImage(contentType) {
                return OWSLocalizedString("QUOTED_REPLY_TYPE_PHOTO",
                                         comment: "Indicates this message is a quoted reply to a photo file.")
            }
            return nil
        }
    }

    private static let sharpCornerRadius: CGFloat = 4
    private static let wideCornerRadius: CGFloat = 10

    private func createBubbleView(sharpCorners: OWSDirectionalRectCorner,
                                  conversationStyle: ConversationStyle,
                                  configurator: Configurator,
                                  componentDelegate: CVComponentDelegate) -> ManualLayoutView {

        // Background
        chatColorView.configure(value: conversationStyle.bubbleChatColorOutgoing,
                                referenceView: componentDelegate.view)
        bubbleView.addSubviewToFillSuperviewEdges(chatColorView)
        tintView.backgroundColor = (conversationStyle.isDarkThemeEnabled
                                        ? UIColor(white: 0, alpha: 0.4)
                                        : UIColor(white: 1, alpha: 0.6))
        bubbleView.addSubviewToFillSuperviewMargins(tintView)
        // For incoming messages, manipulate leading margin
        // to render stripe.
        bubbleView.layoutMargins = UIEdgeInsets(top: 0,
                                                leading: (configurator.isIncoming
                                                            ? configurator.stripeThickness
                                                            : 0),
                                                bottom: 0,
                                                trailing: 0)

        // Mask & Rounding
        if sharpCorners.isEmpty || sharpCorners.contains(.allCorners) {
            bubbleView.layer.maskedCorners = .all
            bubbleView.layer.cornerRadius = sharpCorners.isEmpty ? Self.wideCornerRadius : Self.sharpCornerRadius
        } else {
            // Slow path. CA isn't optimized to handle corners of multiple radii
            // Let's do it by hand with a CAShapeLayer
            let maskLayer = CAShapeLayer()
            bubbleView.addLayoutBlock { view in
                let sharpCorners = UIView.uiRectCorner(forOWSDirectionalRectCorner: sharpCorners)
                let bezierPath = UIBezierPath.roundedRect(view.bounds,
                                                          sharpCorners: sharpCorners,
                                                          sharpCornerRadius: Self.sharpCornerRadius,
                                                          wideCornerRadius: Self.wideCornerRadius)
                maskLayer.path = bezierPath.cgPath
            }
            bubbleView.layer.mask = maskLayer
        }

        return bubbleView
    }

    public func configureForRendering(
        state: State,
        delegate: QuotedMessageViewDelegate?,
        componentDelegate: CVComponentDelegate,
        sharpCorners: OWSDirectionalRectCorner,
        cellMeasurement: CVCellMeasurement
    ) {
        self.state = state
        self.delegate = delegate

        let configurator = Configurator(state: state)
        let conversationStyle = configurator.conversationStyle
        let quotedReplyModel = configurator.quotedReplyModel

        var hStackSubviews = [UIView]()

        if configurator.isForPreview || configurator.isOutgoing {
            stripeView.backgroundColor = .ows_white
        } else {
            // We render the stripe by manipulating the chat color overlay.
            stripeView.backgroundColor = .clear
        }
        hStackSubviews.append(stripeView)

        var innerVStackSubviews = [UIView]()

        let quotedAuthorLabelConfig = configurator.quotedAuthorLabelConfig
        quotedAuthorLabelConfig.applyForRendering(label: quotedAuthorLabel)
        innerVStackSubviews.append(quotedAuthorLabel)

        let quotedTextLabelConfig = configurator.quotedTextLabelConfig
        quotedTextLabelConfig.applyForRendering(label: quotedTextLabel)
        quotedTextSpoilerConfigBuilder.text = quotedTextLabelConfig.text
        quotedTextSpoilerConfigBuilder.spoilerConfig = quotedTextLabelConfig.displayConfig.style
        quotedTextSpoilerConfigBuilder.animator = componentDelegate.spoilerState.animator
        innerVStackSubviews.append(quotedTextLabel)

        innerVStack.configure(config: configurator.innerVStackConfig,
                              cellMeasurement: cellMeasurement,
                              measurementKey: Self.measurementKey_innerVStack,
                              subviews: innerVStackSubviews)
        hStackSubviews.append(innerVStack)

        let thumbnailView: UIView? = {
            guard configurator.hasQuotedThumbnail else { return nil }

            if let thumbnailView = configurator.quotedReplyModel.thumbnailViewFactory?() { return thumbnailView }

            let quotedImageView = self.quotedImageView
            // Use trilinear filters for better scaling quality at
            // some performance cost.
            quotedImageView.layer.minificationFilter = .trilinear
            quotedImageView.layer.magnificationFilter = .trilinear
            quotedImageView.layer.mask = nil

            func tryToLoadThumbnailImage() -> UIImage? {
                guard let contentType = configurator.contentTypeWithThumbnail,
                        TSAttachmentStream.hasThumbnail(forMimeType: contentType) else { return nil }

                // TODO: Possibly ignore data that is too large.
                let image = quotedReplyModel.thumbnailImage
                // TODO: Possibly ignore images that are too large.
                return image
            }

            if let thumbnailImage = tryToLoadThumbnailImage() {
                quotedImageView.image = thumbnailImage
                // We need to specify a contentMode since the size of the image
                // might not match the aspect ratio of the view.
                quotedImageView.contentMode = .scaleAspectFill
                quotedImageView.clipsToBounds = true

                let wrapper = ManualLayoutView(name: "thumbnailImageWrapper")
                wrapper.addSubviewToFillSuperviewEdges(quotedImageView)

                if configurator.isVideoAttachment {
                    let overlayView = ManualLayoutViewWithLayer(name: "video_overlay")
                    overlayView.backgroundColor = .ows_black.withAlphaComponent(0.20)
                    wrapper.addSubviewToFillSuperviewEdges(overlayView)

                    let contentImageView = CVImageView()
                    contentImageView.setTemplateImageName("play-fill", tintColor: .ows_white)
                    contentImageView.setShadow(radius: 6, opacity: 0.24, offset: .zero, color: .ows_black)
                    wrapper.addSubviewToCenterOnSuperviewWithDesiredSize(contentImageView)
                }
                return wrapper
            } else if quotedReplyModel.failedThumbnailAttachmentPointer != nil {
                let wrapper = ManualLayoutViewWithLayer(name: "thumbnailDownloadFailedWrapper")
                wrapper.backgroundColor = configurator.highlightColor

                // TODO: design review icon and color
                quotedImageView.setTemplateImageName("refresh", tintColor: .white)
                quotedImageView.contentMode = .scaleAspectFit
                quotedImageView.clipsToBounds = false
                let iconSize = CGSize.square(configurator.quotedAttachmentSize.width * 0.5)
                wrapper.addSubviewToCenterOnSuperview(quotedImageView, size: iconSize)

                wrapper.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                                    action: #selector(didTapFailedThumbnailDownload)))
                wrapper.isUserInteractionEnabled = true

                return wrapper
            } else if quotedReplyModel.isGiftBadge {
                quotedImageView.image = UIImage(named: "gift-thumbnail")
                quotedImageView.contentMode = .scaleAspectFit
                quotedImageView.clipsToBounds = false

                let wrapper = ManualLayoutViewWithLayer(name: "giftBadgeWrapper")
                wrapper.addSubviewToFillSuperviewEdges(quotedImageView)

                // For outgoing replies to gift messages, the wrapping image is blue, and
                // the bubble can be the same shade of blue. This looks odd, so add a 1pt
                // white border in that case.
                if configurator.isOutgoing && !configurator.isForPreview {
                    // The gift badge needs to know which corners to round, which depends on
                    // whether or not there's adjacent content in the parent container. We care
                    // about "edges that are against the rounded parent edges", and then we
                    // round the corners at the intersection of those edges. For example, in
                    // the common case, we'll be pressing against the top, trailing, and bottom
                    // edges, so we round the .topTrailing and .bottomTrailing corners.
                    var eligibleCorners: OWSDirectionalRectCorner = [.topTrailing, .bottomTrailing]
                    if quotedReplyModel.isRemotelySourced {
                        eligibleCorners.remove(.bottomTrailing)
                    }
                    let maskLayer = CAShapeLayer()
                    quotedImageView.addLayoutBlock { view in
                        let borderWidth: CGFloat = 1
                        assert(borderWidth <= Self.sharpCornerRadius)
                        assert(borderWidth <= Self.wideCornerRadius)
                        let maskRect = view.bounds.insetBy(dx: borderWidth, dy: borderWidth)
                        maskLayer.path = UIBezierPath.roundedRect(
                            maskRect,
                            sharpCorners: UIView.uiRectCorner(
                                forOWSDirectionalRectCorner: sharpCorners.intersection(eligibleCorners)
                            ),
                            sharpCornerRadius: Self.sharpCornerRadius - borderWidth,
                            wideCorners: UIView.uiRectCorner(
                                forOWSDirectionalRectCorner: eligibleCorners.subtracting(sharpCorners)
                            ),
                            wideCornerRadius: Self.wideCornerRadius - borderWidth
                        ).cgPath
                    }
                    quotedImageView.layer.mask = maskLayer
                    wrapper.backgroundColor = .ows_white
                }
                return wrapper
            } else {
                // TODO: Should we overlay the file extension like we do with CVComponentGenericAttachment
                quotedImageView.setTemplateImageName("generic-attachment", tintColor: .clear)
                quotedImageView.contentMode = .scaleAspectFit
                quotedImageView.clipsToBounds = false
                quotedImageView.tintColor = nil

                let wrapper = ManualLayoutView(name: "genericAttachmentWrapper")
                let iconSize = CGSize.square(configurator.quotedAttachmentSize.width * 0.5)
                wrapper.addSubviewToCenterOnSuperview(quotedImageView, size: iconSize)
                return wrapper
            }
        }()

        let trailingView: UIView
        if let thumbnailView = thumbnailView {
            if configurator.hasReaction {
                let wrapper = ManualLayoutView(name: "thumbnailWithReactionWrapper")

                wrapper.addSubview(thumbnailView) { _ in
                    thumbnailView.frame = CGRect(origin: CGPoint(x: 16, y: 0), size: configurator.quotedAttachmentSize)
                }

                let reactionLabelConfig = configurator.quoteReactionLabelConfig
                reactionLabelConfig.applyForRendering(label: quoteReactionLabel)

                quoteReactionLabel.frame = configurator.quotedReactionRect
                wrapper.addSubview(quoteReactionLabel)

                trailingView = wrapper
            } else {
                trailingView = thumbnailView
            }
        } else if configurator.hasReaction {
            let wrapper = ManualLayoutView(name: "reactionWrapper")

            let reactionLabelConfig = configurator.quoteReactionLabelConfig
            reactionLabelConfig.applyForRendering(label: quoteReactionLabel)

            quoteReactionLabel.frame = configurator.quotedReactionRect
            wrapper.addSubview(quoteReactionLabel)

            trailingView = wrapper
        } else {
            // If there's no attachment, add an empty view so that
            // the stack view's spacing serves as a margin between
            // the text views and the trailing edge.
            trailingView = UIView.transparentSpacer()
        }

        hStackSubviews.append(trailingView)

        if configurator.isForPreview {
            let cancelButton = UIButton(type: .custom)
            cancelButton.setImage(UIImage(imageLiteralResourceName: "x-20"), for: .normal)
            cancelButton.imageView?.tintColor = Theme.secondaryTextAndIconColor
            cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)

            let cancelWrapper = ManualLayoutView(name: "cancelWrapper")
            cancelWrapper.layoutMargins = configurator.cancelIconMargins
            cancelWrapper.addSubviewToFillSuperviewMargins(cancelButton)
            hStackSubviews.append(cancelWrapper)
        }

        hStack.configure(config: configurator.hStackConfig,
                         cellMeasurement: cellMeasurement,
                         measurementKey: Self.measurementKey_hStack,
                         subviews: hStackSubviews)

        var outerVStackSubviews = [UIView]()

        outerVStackSubviews.append(hStack)

        if quotedReplyModel.isRemotelySourced {
            remotelySourcedContentIconView.setTemplateImageName("link-slash-compact", tintColor: Theme.lightThemePrimaryColor)

            let quoteContentSourceLabelConfig = configurator.quoteContentSourceLabelConfig
            quoteContentSourceLabelConfig.applyForRendering(label: quoteContentSourceLabel)

            remotelySourcedContentStack.configure(config: configurator.remotelySourcedContentStackConfig,
                                                  cellMeasurement: cellMeasurement,
                                                  measurementKey: Self.measurementKey_remotelySourcedContentStack,
                                                  subviews: [
                                                    remotelySourcedContentIconView,
                                                    quoteContentSourceLabel
                                                  ])
            remotelySourcedContentStack.backgroundColor = UIColor.white.withAlphaComponent(0.4)
            outerVStackSubviews.append(remotelySourcedContentStack)
        }

        outerVStack.configure(config: configurator.outerVStackConfig,
                              cellMeasurement: cellMeasurement,
                              measurementKey: Self.measurementKey_outerVStack,
                              subviews: outerVStackSubviews)

        var outerStackViews = [UIView]()

        if configurator.hasReaction {
            let reactionLabelConfig = configurator.quoteReactionHeaderLabelConfig
            reactionLabelConfig.applyForRendering(label: quoteReactionHeaderLabel)
            outerStackViews.append(quoteReactionHeaderLabel)
        }

        let bubbleView = createBubbleView(sharpCorners: sharpCorners,
                                          conversationStyle: conversationStyle,
                                          configurator: configurator,
                                          componentDelegate: componentDelegate)
        bubbleView.addSubviewToFillSuperviewEdges(outerVStack)
        bubbleView.clipsToBounds = true
        outerStackViews.append(bubbleView)

        self.configure(config: configurator.outerStackConfig,
                       cellMeasurement: cellMeasurement,
                       measurementKey: Self.measurementKey_outerStack,
                       subviews: outerStackViews)
    }

    public func setIsCellVisible(_ isCellVisible: Bool) {
        quotedTextSpoilerConfigBuilder.isViewVisible = isCellVisible
    }

    // MARK: - Measurement

    private static let measurementKey_outerStack = "QuotedMessageView.measurementKey_outerStack"
    private static let measurementKey_hStack = "QuotedMessageView.measurementKey_hStack"
    private static let measurementKey_innerVStack = "QuotedMessageView.measurementKey_innerVStack"
    private static let measurementKey_outerVStack = "QuotedMessageView.measurementKey_outerVStack"
    private static let measurementKey_remotelySourcedContentStack = "QuotedMessageView.measurementKey_remotelySourcedContentStack"

    public static func measure(state: State,
                               maxWidth: CGFloat,
                               measurementBuilder: CVCellMeasurement.Builder) -> CGSize {

        let configurator = Configurator(state: state)

        let outerStackConfig = configurator.outerStackConfig
        let hStackConfig = configurator.hStackConfig
        let innerVStackConfig = configurator.innerVStackConfig
        let outerVStackConfig = configurator.outerVStackConfig
        let hasQuotedThumbnail = configurator.hasQuotedThumbnail
        let hasReaction = configurator.hasReaction
        let quotedAttachmentSize = configurator.quotedAttachmentSize
        let quotedReactionRect = configurator.quotedReactionRect
        let quotedReplyModel = configurator.quotedReplyModel

        var maxLabelWidth = (maxWidth - (configurator.stripeThickness +
                                            hStackConfig.spacing * 2 +
                                            hStackConfig.layoutMargins.totalWidth +
                                            innerVStackConfig.layoutMargins.totalWidth +
                                            outerVStackConfig.layoutMargins.totalWidth +
                                            outerStackConfig.layoutMargins.totalWidth))
        if hasQuotedThumbnail {
            maxLabelWidth -= quotedAttachmentSize.width
            if hasReaction { maxLabelWidth -= quotedReactionRect.width / 2 }
        } else if hasReaction {
            maxLabelWidth -= quotedReactionRect.width
        }
        maxLabelWidth = max(0, maxLabelWidth)

        var innerVStackSubviewInfos = [ManualStackSubviewInfo]()

        let quotedAuthorLabelConfig = configurator.quotedAuthorLabelConfig
        let quotedAuthorSize = CVText.measureLabel(config: quotedAuthorLabelConfig,
                                                   maxWidth: maxLabelWidth)
        innerVStackSubviewInfos.append(quotedAuthorSize.asManualSubviewInfo)

        let quotedTextLabelConfig = configurator.quotedTextLabelConfig
        let quotedTextSize = CVText.measureLabel(config: quotedTextLabelConfig,
                                                 maxWidth: maxLabelWidth)
        innerVStackSubviewInfos.append(quotedTextSize.asManualSubviewInfo)

        let innerVStackMeasurement = ManualStackView.measure(config: innerVStackConfig,
                                                             measurementBuilder: measurementBuilder,
                                                             measurementKey: Self.measurementKey_innerVStack,
                                                             subviewInfos: innerVStackSubviewInfos)

        var hStackSubviewInfos = [ManualStackSubviewInfo]()

        let stripeSize = CGSize(width: configurator.stripeThickness, height: 0)
        hStackSubviewInfos.append(stripeSize.asManualSubviewInfo(hasFixedWidth: true))

        hStackSubviewInfos.append(innerVStackMeasurement.measuredSize.asManualSubviewInfo)

        if hasQuotedThumbnail {
            if hasReaction {
                let attachmentPlusReactionSize = quotedAttachmentSize + CGSize(width: quotedReactionRect.width / 2, height: 0)
                hStackSubviewInfos.append(attachmentPlusReactionSize.asManualSubviewInfo(hasFixedWidth: true))
            } else {
                hStackSubviewInfos.append(quotedAttachmentSize.asManualSubviewInfo(hasFixedWidth: true))
            }
        } else if hasReaction {
            hStackSubviewInfos.append(CGSize(width: quotedReactionRect.width, height: quotedAttachmentSize.height).asManualSubviewInfo(hasFixedWidth: true))
        } else {
            hStackSubviewInfos.append(CGSize.zero.asManualSubviewInfo(hasFixedWidth: true))
        }

        if configurator.isForPreview {
            let cancelIconSize = CGSize.square(configurator.cancelIconSize)
            let cancelWrapperSize = cancelIconSize + configurator.cancelIconMargins.asSize
            hStackSubviewInfos.append(cancelWrapperSize.asManualSubviewInfo(hasFixedWidth: true))
        }

        let hStackMeasurement = ManualStackView.measure(config: hStackConfig,
                                                        measurementBuilder: measurementBuilder,
                                                        measurementKey: Self.measurementKey_hStack,
                                                        subviewInfos: hStackSubviewInfos)

        var outerVStackSubviewInfos = [ManualStackSubviewInfo]()

        outerVStackSubviewInfos.append(hStackMeasurement.measuredSize.asManualSubviewInfo)

        if quotedReplyModel.isRemotelySourced {
            let remotelySourcedContentIconSize = CGSize.square(configurator.remotelySourcedContentIconSize)

            let quoteContentSourceLabelConfig = configurator.quoteContentSourceLabelConfig
            let quoteContentSourceSize = CVText.measureLabel(config: quoteContentSourceLabelConfig,
                                                             maxWidth: maxLabelWidth)

            let innerVStackMeasurement = ManualStackView.measure(config: configurator.remotelySourcedContentStackConfig,
                                                                 measurementBuilder: measurementBuilder,
                                                                 measurementKey: Self.measurementKey_remotelySourcedContentStack,
                                                                 subviewInfos: [
                                                                    remotelySourcedContentIconSize.asManualSubviewInfo(hasFixedSize: true),
                                                                    quoteContentSourceSize.asManualSubviewInfo
                                                                 ])
            outerVStackSubviewInfos.append(innerVStackMeasurement.measuredSize.asManualSubviewInfo)
        }

        let outerVStackMeasurement = ManualStackView.measure(config: outerVStackConfig,
                                                             measurementBuilder: measurementBuilder,
                                                             measurementKey: Self.measurementKey_outerVStack,
                                                             subviewInfos: outerVStackSubviewInfos)

        var outerStackSubviewInfos = [ManualStackSubviewInfo]()

        if hasReaction {
            let reactionLabelConfig = configurator.quoteReactionHeaderLabelConfig
            let reactionLabelSize = CVText.measureLabel(config: reactionLabelConfig, maxWidth: maxLabelWidth)
            outerStackSubviewInfos.append(reactionLabelSize.asManualSubviewInfo)
        }

        outerStackSubviewInfos.append(outerVStackMeasurement.measuredSize.asManualSubviewInfo)

        let outerStackMeasurement = ManualStackView.measure(config: outerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_outerStack,
                                                            subviewInfos: outerStackSubviewInfos,
                                                            maxWidth: maxWidth)
        return outerStackMeasurement.measuredSize
    }

    // MARK: - Spoiler Animations

    private lazy var quotedTextSpoilerConfigBuilder = SpoilerableTextConfig.Builder(isViewVisible: false) {
        didSet {
            quotedTextLabelSpoilerAnimator.updateAnimationState(quotedTextSpoilerConfigBuilder)
        }
    }

    private lazy var quotedTextLabelSpoilerAnimator: SpoilerableLabelAnimator = {
        let animator = SpoilerableLabelAnimator(label: quotedTextLabel)
        animator.updateAnimationState(quotedTextSpoilerConfigBuilder)
        return animator
    }()

    // MARK: -

    @objc
    private func didTapCancel() {
        delegate?.didCancelQuotedReply()
    }

    @objc
    private func didTapFailedThumbnailDownload(_ sender: UITapGestureRecognizer) {
        Logger.debug("in didTapFailedThumbnailDownload")

        guard let state = self.state else {
            owsFailDebug("Missing state.")
            return
        }
        let quotedReplyModel = state.quotedReplyModel

        guard let thumbnailAttachmentPointer = quotedReplyModel.failedThumbnailAttachmentPointer else {
            owsFailDebug("thumbnailAttachmentPointer was unexpectedly nil")
            return
        }

        delegate?.didTapQuotedReply(quotedReplyModel,
                                    failedThumbnailDownloadAttachmentPointer: thumbnailAttachmentPointer)
    }

    public func updateAppearance() {
        chatColorView.updateAppearance()
    }

    public override func reset() {
        super.reset()

        self.state = nil
        self.delegate = nil

        hStack.reset()
        innerVStack.reset()
        outerVStack.reset()
        remotelySourcedContentStack.reset()

        quotedAuthorLabel.text = nil
        quotedTextLabel.text = nil
        quoteContentSourceLabel.text = nil
        quoteReactionHeaderLabel.text = nil
        quoteReactionLabel.text = nil
        quotedImageView.image = nil
        remotelySourcedContentIconView.image = nil

        bubbleView.reset()
        bubbleView.removeFromSuperview()
        chatColorView.reset()
        chatColorView.removeFromSuperview()
        tintView.reset()
        tintView.removeFromSuperview()
    }
}
