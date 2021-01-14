//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol QuotedMessageViewDelegate {

    func didTapQuotedReply(_ quotedReply: OWSQuotedReplyModel,
                           failedThumbnailDownloadAttachmentPointer attachmentPointer: TSAttachmentPointer)

    func didCancelQuotedReply()
}

// MARK: -

// TODO: Remove OWSQuotedMessageView.
@objc
public class QuotedMessageView: UIView {

    @objc
    public weak var delegate: QuotedMessageViewDelegate?

    public struct State: Equatable {
        let quotedReplyModel: OWSQuotedReplyModel
        let displayableQuotedText: DisplayableText?
        let conversationStyle: ConversationStyle
        let isOutgoing: Bool
        let isForPreview: Bool
        let quotedAuthorName: String
    }
    private let state: State

    private var quotedReplyModel: OWSQuotedReplyModel { state.quotedReplyModel }

    private let sharpCorners: OWSDirectionalRectCorner

    required init(state: State, sharpCorners: OWSDirectionalRectCorner) {
        self.state = state
        self.sharpCorners = sharpCorners

        super.init(frame: .zero)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let quotedAuthorLabel = UILabel()
    private let quotedTextLabel = UILabel()
    private let quoteContentSourceLabel = UILabel()

    static func stateForConversation(quotedReplyModel: OWSQuotedReplyModel,
                                     displayableQuotedText: DisplayableText?,
                                     conversationStyle: ConversationStyle,
                                     isOutgoing: Bool,
                                     transaction: SDSAnyReadTransaction) -> State {

        let quotedAuthorName = contactsManager.displayName(for: quotedReplyModel.authorAddress,
                                                           transaction: transaction)

        return State(quotedReplyModel: quotedReplyModel,
                     displayableQuotedText: displayableQuotedText,
                     conversationStyle: conversationStyle,
                     isOutgoing: isOutgoing,
                     isForPreview: false,
                     quotedAuthorName: quotedAuthorName)
    }

    static func stateForPreview(quotedReplyModel: OWSQuotedReplyModel,
                                conversationStyle: ConversationStyle,
                                transaction: SDSAnyReadTransaction) -> State {

        let quotedAuthorName = contactsManager.displayName(for: quotedReplyModel.authorAddress,
                                                           transaction: transaction)

        var displayableQuotedText: DisplayableText?
        if let body = quotedReplyModel.body, !body.isEmpty {
            let messageBody = MessageBody(text: body, ranges: quotedReplyModel.bodyRanges ?? .empty)
            displayableQuotedText = DisplayableText.displayableText(withMessageBody: messageBody,
                                                                    mentionStyle: .quotedReply,
                                                                    transaction: transaction)
        }

        return State(quotedReplyModel: quotedReplyModel,
                     displayableQuotedText: displayableQuotedText,
                     conversationStyle: conversationStyle,
                     isOutgoing: true,
                     isForPreview: true,
                     quotedAuthorName: quotedAuthorName)
    }

    @objc
    public var sharpCornersForPreview: OWSDirectionalRectCorner {
        OWSDirectionalRectCorner(rawValue: OWSDirectionalRectCorner.bottomLeading.rawValue |
                                    OWSDirectionalRectCorner.bottomTrailing.rawValue)
    }

    public func createContents() {
        Configurator(state: state).createContents(rootView: self,
                                                  quotedAuthorLabel: quotedAuthorLabel,
                                                  quotedTextLabel: quotedTextLabel,
                                                  quoteContentSourceLabel: quoteContentSourceLabel,
                                                  sharpCorners: sharpCorners)
    }

    // The Configurator can be used to:
    //
    // * Configure this view for rendering.
    // * Measure this view _without_ creating its views.
    private struct Configurator {
        let state: State

        var quotedReplyModel: OWSQuotedReplyModel { state.quotedReplyModel }
        var displayableQuotedText: DisplayableText? { state.displayableQuotedText }
        var conversationStyle: ConversationStyle { state.conversationStyle }
        var isOutgoing: Bool { state.isOutgoing }
        var isForPreview: Bool { state.isForPreview }
        var quotedAuthorName: String { state.quotedAuthorName }

        var bubbleHMargin: CGFloat { isForPreview ? 0 : 6 }

        let hSpacing: CGFloat = 8
        let vSpacing: CGFloat = 2
        let stripeThickness: CGFloat = 4
        let textVMargin: CGFloat = 7
        var quotedAuthorFont: UIFont { UIFont.ows_dynamicTypeSubheadline.ows_semibold }
        var quotedAuthorColor: UIColor { conversationStyle.quotedReplyAuthorColor() }
        var quotedTextColor: UIColor { conversationStyle.quotedReplyTextColor() }
        var quotedTextFont: UIFont { UIFont.ows_dynamicTypeBody }
        var fileTypeTextColor: UIColor { conversationStyle.quotedReplyAttachmentColor() }
        var fileTypeFont: UIFont { quotedTextFont.ows_italic }
        var filenameTextColor: UIColor { conversationStyle.quotedReplyAttachmentColor() }
        var filenameFont: UIFont { quotedTextFont }
        var quotedAuthorHeight: CGFloat { quotedAuthorFont.lineHeight }
        let quotedAttachmentSize: CGFloat = 54
        let kRemotelySourcedContentGlyphLength: CGFloat = 16
        let kRemotelySourcedContentRowMargin: CGFloat = 4
        let kRemotelySourcedContentRowSpacing: CGFloat = 3

        var hasQuotedAttachment: Bool {
            contentType != nil && OWSMimeTypeOversizeTextMessage != contentType
        }

        var contentType: String? {
            guard let contentType = quotedReplyModel.contentType,
                  !contentType.isEmpty else {
                return nil
            }
            return contentType
        }

        var hasQuotedAttachmentThumbnailImage: Bool {
            guard let contentType = self.contentType,
                  OWSMimeTypeOversizeTextMessage != contentType,
                  TSAttachmentStream.hasThumbnail(forMimeType: contentType) else {
                return false
            }
            return true
        }

        var highlightColor: UIColor {
            let isQuotingSelf = quotedReplyModel.authorAddress.isLocalAddress
            return (isQuotingSelf
                        ? conversationStyle.bubbleColor(isIncoming: false)
                        : conversationStyle.quotingSelfHighlightColor())
        }

        func createContents(rootView: UIView,
                            quotedAuthorLabel: UILabel,
                            quotedTextLabel: UILabel,
                            quoteContentSourceLabel: UILabel,
                            sharpCorners: OWSDirectionalRectCorner) {
            // Ensure only called once.
            owsAssertDebug(rootView.subviews.isEmpty)

            rootView.isUserInteractionEnabled = true
            rootView.layoutMargins = .zero
            rootView.clipsToBounds = true

            let maskLayer = CAShapeLayer()

            let innerBubbleView = OWSLayerView(frame: .zero) { (layerView: UIView) in
                let layerFrame = layerView.bounds

                let bubbleLeft: CGFloat = 0
                let bubbleRight = layerFrame.width
                let bubbleTop: CGFloat = 0
                let bubbleBottom = layerFrame.height

                let sharpCornerRadius: CGFloat = 4
                let wideCornerRadius: CGFloat = 12

                let bezierPath = OWSBubbleView.roundedBezierRect(withBubbleTop: bubbleTop,
                                                                 bubbleLeft: bubbleLeft,
                                                                 bubbleBottom: bubbleBottom,
                                                                 bubbleRight: bubbleRight,
                                                                 sharpCornerRadius: sharpCornerRadius,
                                                                 wideCornerRadius: wideCornerRadius,
                                                                 sharpCorners: sharpCorners)

                maskLayer.path = bezierPath.cgPath
            }

            innerBubbleView.layer.mask = maskLayer
            innerBubbleView.backgroundColor = conversationStyle.quotedReplyBubbleColor
            rootView.addSubview(innerBubbleView)
            innerBubbleView.autoPinLeadingToSuperviewMargin(withInset: bubbleHMargin)
            innerBubbleView.autoPinTrailingToSuperviewMargin(withInset: bubbleHMargin)
            innerBubbleView.autoPinTopToSuperviewMargin()
            innerBubbleView.autoPinBottomToSuperviewMargin()
            innerBubbleView.setContentHuggingHorizontalLow()
            innerBubbleView.setCompressionResistanceHorizontalLow()

            let hStackView = UIStackView()
            hStackView.axis = .horizontal
            hStackView.spacing = hSpacing

            let stripeView = UIView()
            if isForPreview {
                stripeView.backgroundColor = conversationStyle.quotedReplyStripeColor(isIncoming: true)
            } else {
                stripeView.backgroundColor = conversationStyle.quotedReplyStripeColor(isIncoming: !isOutgoing)
            }
            stripeView.autoSetDimension(.width, toSize: stripeThickness)
            stripeView.setContentHuggingHigh()
            stripeView.setCompressionResistanceHigh()
            hStackView.addArrangedSubview(stripeView)

            let vStackView = UIStackView()
            vStackView.axis = .vertical
            vStackView.layoutMargins = UIEdgeInsets(hMargin: 0, vMargin: textVMargin)
            vStackView.isLayoutMarginsRelativeArrangement = true
            vStackView.spacing = vSpacing
            vStackView.setContentHuggingHorizontalLow()
            vStackView.setCompressionResistanceHorizontalLow()
            hStackView.addArrangedSubview(vStackView)

            quotedAuthorLabelConfig.applyForRendering(label: quotedAuthorLabel)
            vStackView.addArrangedSubview(quotedAuthorLabel)
            quotedAuthorLabel.autoSetDimension(.height, toSize: quotedAuthorHeight)
            quotedAuthorLabel.setContentHuggingVerticalHigh()
            quotedAuthorLabel.setContentHuggingHorizontalLow()
            quotedAuthorLabel.setCompressionResistanceHorizontalLow()

            quotedTextLabelConfig.applyForRendering(label: quotedTextLabel)
            vStackView.addArrangedSubview(quotedTextLabel)
            quotedTextLabel.setContentHuggingHorizontalLow()
            quotedTextLabel.setCompressionResistanceHorizontalLow()
            quotedTextLabel.setCompressionResistanceVerticalHigh()

            if hasQuotedAttachment {
                let quotedAttachmentView: UIView
                if let thumbnailImage = tryToLoadThumbnailImage() {
                    quotedAttachmentView = imageView(forImage: thumbnailImage)
                    quotedAttachmentView.clipsToBounds = true

                    if isVideoAttachment {
                        let contentIcon = UIImage(named: "attachment_play_button")?.withRenderingMode(.alwaysTemplate)
                        let contentImageView = imageView(forImage: contentIcon)
                        contentImageView.tintColor = .white
                        quotedAttachmentView.addSubview(contentImageView)
                        contentImageView.autoCenterInSuperview()
                    }
                } else if quotedReplyModel.thumbnailDownloadFailed {
                    // TODO: design review icon and color
                    let contentIcon = UIImage(named: "btnRefresh--white")?.withRenderingMode(.alwaysTemplate)
                    let contentImageView = imageView(forImage: contentIcon)
                    contentImageView.contentMode = .scaleAspectFit
                    contentImageView.tintColor = .white

                    quotedAttachmentView = UIView.container()
                    quotedAttachmentView.addSubview(contentImageView)
                    quotedAttachmentView.backgroundColor = highlightColor
                    contentImageView.autoCenterInSuperview()
                    let imageSize = quotedAttachmentSize * 0.5
                    contentImageView.autoSetDimensions(to: CGSize(square: imageSize))

                    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapFailedThumbnailDownload))
                    quotedAttachmentView.addGestureRecognizer(tapGesture)
                    quotedAttachmentView.isUserInteractionEnabled = true
                } else {
                    let contentIcon = UIImage(named: "generic-attachment")
                    let contentImageView = imageView(forImage: contentIcon)
                    contentImageView.contentMode = .scaleAspectFit

                    let wrapper = UIView.container()
                    wrapper.addSubview(contentImageView)
                    contentImageView.autoCenterInSuperview()
                    contentImageView.autoSetDimension(.width, toSize: quotedAttachmentSize * 0.5)
                    quotedAttachmentView = wrapper
                }

                quotedAttachmentView.autoPinToSquareAspectRatio()
                quotedAttachmentView.setContentHuggingHigh()
                quotedAttachmentView.setCompressionResistanceHigh()
                hStackView.addArrangedSubview(quotedAttachmentView)
            } else {
                // If there's no attachment, add an empty view so that
                // the stack view's spacing serves as a margin between
                // the text views and the trailing edge.
                let emptyView = UIView.container()
                hStackView.addArrangedSubview(emptyView)
                emptyView.setContentHuggingHigh()
                emptyView.autoSetDimension(.width, toSize: 0)
            }

            var contentView = hStackView

            if quotedReplyModel.isRemotelySourced {
                let quoteSourceWrapper = UIStackView(arrangedSubviews: [
                    contentView,
                    buildRemoteContentSourceView(quoteContentSourceLabel: quoteContentSourceLabel)
                ])
                quoteSourceWrapper.axis = .vertical
                contentView = quoteSourceWrapper
            }

            if isForPreview {
                let cancelButton = UIButton(type: .custom)
                cancelButton.setImage(UIImage(named: "compose-cancel")?.withRenderingMode(.alwaysTemplate),
                                      for: .normal)
                cancelButton.imageView?.tintColor = Theme.secondaryTextAndIconColor
                cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
                cancelButton.setContentHuggingHorizontalHigh()
                cancelButton.setCompressionResistanceHorizontalHigh()

                let cancelStack = UIStackView(arrangedSubviews: [ cancelButton ])
                cancelStack.axis = .horizontal
                cancelStack.alignment = .top
                cancelStack.isLayoutMarginsRelativeArrangement = true
                let hMarginLeading: CGFloat = 0
                let hMarginTrailing: CGFloat = 6
                cancelStack.layoutMargins = UIEdgeInsets(top: 6, leading: hMarginLeading, bottom: 0, trailing: hMarginTrailing)
                cancelStack.setContentHuggingHorizontalHigh()
                cancelStack.setCompressionResistanceHorizontalHigh()

                let cancelWrapper = UIStackView(arrangedSubviews: [
                    contentView,
                    cancelStack
                ])
                cancelWrapper.axis = .horizontal

                contentView = cancelWrapper
            }

            contentView.setContentHuggingHorizontalLow()
            contentView.setCompressionResistanceHorizontalLow()

            innerBubbleView.addSubview(contentView)
            contentView.autoPinEdgesToSuperviewEdges()
        }

        func buildRemoteContentSourceView(quoteContentSourceLabel: UILabel) -> UIView {

            let glyphImage = UIImage(named: "ic_broken_link")!.withRenderingMode(.alwaysTemplate)
            owsAssertDebug(CGSize(square: kRemotelySourcedContentGlyphLength) == glyphImage.size)
            let glyphView = UIImageView(image: glyphImage)
            glyphView.tintColor = Theme.lightThemePrimaryColor
            glyphView.autoSetDimensions(to: CGSize(square: kRemotelySourcedContentGlyphLength))

            quoteContentSourceLabelConfig.applyForRendering(label: quoteContentSourceLabel)
            let sourceRow = UIStackView(arrangedSubviews: [glyphView, quoteContentSourceLabel])
            sourceRow.axis = .horizontal
            sourceRow.alignment = .center
            // TODO verify spacing w/ design
            sourceRow.spacing = kRemotelySourcedContentRowSpacing
            sourceRow.isLayoutMarginsRelativeArrangement = true

            // TODO: Should this be leading?
            let leftMargin: CGFloat = 8
            sourceRow.layoutMargins = UIEdgeInsets(top: kRemotelySourcedContentRowMargin,
                                                   left: leftMargin,
                                                   bottom: kRemotelySourcedContentRowMargin,
                                                   right: kRemotelySourcedContentRowMargin)

            let backgroundColor = UIColor.white.withAlphaComponent(0.4)
            sourceRow.addBackgroundView(withBackgroundColor: backgroundColor)

            return sourceRow
        }

        func tryToLoadThumbnailImage() -> UIImage? {
            guard hasQuotedAttachmentThumbnailImage else {
                return nil
            }

            // TODO: Possibly ignore data that is too large.
            let image = quotedReplyModel.thumbnailImage
            // TODO: Possibly ignore images that are too large.
            return image
        }

        func imageView(forImage image: UIImage?) -> UIImageView {
            owsAssertDebug(image != nil)

            let imageView = UIImageView()
            imageView.image = image
            // We need to specify a contentMode since the size of the image
            // might not match the aspect ratio of the view.
            imageView.contentMode = .scaleAspectFill
            // Use trilinear filters for better scaling quality at
            // some performance cost.
            imageView.layer.minificationFilter = .trilinear
            imageView.layer.magnificationFilter = .trilinear
            return imageView
        }

        var quotedTextLabelConfig: CVLabelConfig {
            let attributedText: NSAttributedString
            var textAlignment: NSTextAlignment?

            if let displayableQuotedText = self.displayableQuotedText,
               !displayableQuotedText.displayAttributedText.isEmpty {
                let displayAttributedText = displayableQuotedText.displayAttributedText
                let mutableText = NSMutableAttributedString(attributedString: displayAttributedText)
                mutableText.addAttributesToEntireString([
                    .font: quotedTextFont,
                    .foregroundColor: quotedTextColor
                ])
                attributedText = mutableText
                textAlignment = displayableQuotedText.displayTextNaturalAlignment
            } else if let fileTypeForSnippet = self.fileTypeForSnippet {
                attributedText = NSAttributedString(string: fileTypeForSnippet,
                                                    attributes: [
                                                        .font: fileTypeFont,
                                                        .foregroundColor: fileTypeTextColor
                                                    ])
            } else if let sourceFilename = quotedReplyModel.sourceFilename?.filterStringForDisplay() {
                attributedText = NSAttributedString(string: sourceFilename,
                                                    attributes: [
                                                        .font: filenameFont,
                                                        .foregroundColor: filenameTextColor
                                                    ])
            } else {
                let string = NSLocalizedString("QUOTED_REPLY_TYPE_ATTACHMENT",
                                               comment: "Indicates this message is a quoted reply to an attachment of unknown type.")
                attributedText = NSAttributedString(string: string,
                                                    attributes: [
                                                        .font: fileTypeFont,
                                                        .foregroundColor: fileTypeTextColor
                                                    ])
            }

            return CVLabelConfig(attributedText: attributedText,
                                 font: quotedTextFont,
                                 textColor: quotedTextColor,
                                 numberOfLines: isForPreview ? 1 : 2,
                                 lineBreakMode: .byTruncatingTail,
                                 textAlignment: textAlignment)
        }

        var quoteContentSourceLabelConfig: CVLabelConfig {
            let text = NSLocalizedString("QUOTED_REPLY_CONTENT_FROM_REMOTE_SOURCE",
                                         comment: "Footer label that appears below quoted messages when the quoted content was not derived locally. When the local user doesn't have a copy of the message being quoted, e.g. if it had since been deleted, we instead show the content specified by the sender.")
            return CVLabelConfig(text: text,
                                 font: UIFont.ows_dynamicTypeFootnote,
                                 textColor: Theme.lightThemePrimaryColor)
        }

        var fileTypeForSnippet: String? {
            // TODO: Are we going to use the filename?  For all mimetypes?
            guard let contentType = self.contentType else {
                return nil
            }

            if MIMETypeUtil.isAudio(contentType) {
                return NSLocalizedString("QUOTED_REPLY_TYPE_AUDIO",
                                         comment: "Indicates this message is a quoted reply to an audio file.")
            } else if MIMETypeUtil.isVideo(contentType) {
                return NSLocalizedString("QUOTED_REPLY_TYPE_VIDEO",
                                         comment: "Indicates this message is a quoted reply to a video file.")
            } else if MIMETypeUtil.isImage(contentType) {
                return NSLocalizedString("QUOTED_REPLY_TYPE_IMAGE",
                                         comment: "Indicates this message is a quoted reply to an image file.")
            } else if MIMETypeUtil.isAnimated(contentType) {
                if contentType.caseInsensitiveCompare(OWSMimeTypeImageGif) == .orderedSame {
                    return NSLocalizedString("QUOTED_REPLY_TYPE_GIF",
                                             comment: "Indicates this message is a quoted reply to animated GIF file.")
                } else {
                    return NSLocalizedString("QUOTED_REPLY_TYPE_IMAGE",
                                             comment: "Indicates this message is a quoted reply to an image file.")
                }
            }
            return nil
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

        var quotedAuthorLabelConfig: CVLabelConfig {
            let text: String
            if quotedReplyModel.authorAddress.isLocalAddress {
                text = NSLocalizedString("QUOTED_REPLY_AUTHOR_INDICATOR_YOU",
                                         comment: "message header label when someone else is quoting you")
            } else {
                let format = NSLocalizedString("QUOTED_REPLY_AUTHOR_INDICATOR_FORMAT",
                                               comment: "Indicates the author of a quoted message. Embeds {{the author's name or phone number}}.")
                text = String(format: format, quotedAuthorName)
            }

            return CVLabelConfig(text: text,
                                 font: quotedAuthorFont,
                                 textColor: quotedAuthorColor,
                                 numberOfLines: 1,
                                 lineBreakMode: .byTruncatingTail)
        }

        // MARK: - Measurement

        func measure(maxWidth: CGFloat) -> CGSize {
            var result = CGSize.zero

            result.width += bubbleHMargin * 2 + stripeThickness + hSpacing * 2

            var thumbnailHeight: CGFloat = 0
            if hasQuotedAttachment {
                result.width += quotedAttachmentSize
                thumbnailHeight += quotedAttachmentSize
            }

            // Quoted Author
            var textWidth: CGFloat = 0
            let maxTextWidth = maxWidth - result.width
            var textHeight = textVMargin * 2 + vSpacing
            do {
                let quotedAuthorLabelConfig = self.quotedAuthorLabelConfig
                let textSize = CVText.measureLabel(config: quotedAuthorLabelConfig, maxWidth: maxWidth)
                textWidth = max(textWidth, textSize.width)
                textHeight += textSize.height
            }

            do {
                let textSize = CVText.measureLabel(config: quotedTextLabelConfig, maxWidth: maxWidth)
                textWidth = max(textWidth, textSize.width)
                textHeight += textSize.height
            }

            if quotedReplyModel.isRemotelySourced {
                let textSize = CVText.measureLabel(config: quoteContentSourceLabelConfig, maxWidth: maxWidth)
                //            textWidth = max(textWidth, textSize.width)
                //            textHeight += textSize.height

                let sourceStackViewHeight = max(kRemotelySourcedContentGlyphLength, textSize.height)

                textWidth = max(textWidth, textSize.width + kRemotelySourcedContentGlyphLength + kRemotelySourcedContentRowSpacing)
                result.height += kRemotelySourcedContentRowMargin * 2 + sourceStackViewHeight
            }

            textWidth = min(textWidth, maxTextWidth)
            result.width += textWidth
            result.height += max(textHeight, thumbnailHeight)

            return result.ceil
        }
    }

    // MARK: - Measurement

    private func measure(maxWidth: CGFloat) -> CGSize {
        Self.measure(state: state, maxWidth: maxWidth)
    }

    static func measure(state: State, maxWidth: CGFloat) -> CGSize {
        Configurator(state: state).measure(maxWidth: maxWidth)
    }

    // MARK: -

    // TODO: Do we need this method?
    @objc
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        // TODO: Should we honor the size param?
        self.measure(maxWidth: CGFloat.greatestFiniteMagnitude)
    }

    @objc
    func didTapCancel() {
        delegate?.didCancelQuotedReply()
    }

    @objc
    func didTapFailedThumbnailDownload(_ sender: UITapGestureRecognizer) {
        Logger.debug("in didTapFailedThumbnailDownload")

        if !quotedReplyModel.thumbnailDownloadFailed {
            owsFailDebug("thumbnailDownloadFailed was unexpectedly false")
            return
        }

        guard let thumbnailAttachmentPointer = quotedReplyModel.thumbnailAttachmentPointer else {
            owsFailDebug("thumbnailAttachmentPointer was unexpectedly nil")
            return
        }

        delegate?.didTapQuotedReply(quotedReplyModel,
                                    failedThumbnailDownloadAttachmentPointer: thumbnailAttachmentPointer)
    }
}
