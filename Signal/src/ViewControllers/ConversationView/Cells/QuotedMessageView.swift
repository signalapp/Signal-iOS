//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
public class QuotedMessageView: ManualStackViewWithLayer {

    public struct State: Equatable {
        let quotedReplyModel: OWSQuotedReplyModel
        let displayableQuotedText: DisplayableText?
        let conversationStyle: ConversationStyle
        let isOutgoing: Bool
        let isForPreview: Bool
        let quotedAuthorName: String
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
    private let quotedImageView = CVImageView()
    private let remotelySourcedContentIconView = CVImageView()

    // Background
    private let bubbleView = ManualLayoutViewWithLayer(name: "bubbleView")
    private let chatColorView = CVColorOrGradientView()
    private let tintView = ManualLayoutViewWithLayer(name: "tintView")

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
        var isIncoming: Bool { !isOutgoing }
        var isForPreview: Bool { state.isForPreview }
        var quotedAuthorName: String { state.quotedAuthorName }

        let stripeThickness: CGFloat = 4
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
        let remotelySourcedContentIconSize: CGFloat = 16
        let cancelIconSize: CGFloat = 20
        let cancelIconMargins = UIEdgeInsets(top: 6, leading: 6, bottom: 0, trailing: 6)

        var outerStackConfig: CVStackViewConfig {
            CVStackViewConfig(axis: .vertical,
                              alignment: .fill,
                              spacing: 0,
                              layoutMargins: UIEdgeInsets(hMargin: isForPreview ? 0 : 6,
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
                              layoutMargins: UIEdgeInsets(hMargin: 0, vMargin: 7))
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

        var hasQuotedAttachmentThumbnailImage: Bool {
            guard let contentType = self.contentType,
                  OWSMimeTypeOversizeTextMessage != contentType,
                  TSAttachmentStream.hasThumbnail(forMimeType: contentType) else {
                return false
            }
            return true
        }

        var highlightColor: UIColor {
            conversationStyle.quotedReplyHighlightColor()
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
                                 numberOfLines: isForPreview || hasQuotedAttachment ? 1 : 2,
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
    }

    private func createBubbleView(sharpCorners: OWSDirectionalRectCorner,
                                  conversationStyle: ConversationStyle,
                                  configurator: Configurator,
                                  componentDelegate: CVComponentDelegate) -> ManualLayoutView {
        let sharpCornerRadius: CGFloat = 4
        let wideCornerRadius: CGFloat = 12

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
            bubbleView.layer.cornerRadius = sharpCorners.isEmpty ? wideCornerRadius : sharpCornerRadius
        } else {
            // Slow path. CA isn't optimized to handle corners of multiple radii
            // Let's do it by hand with a CAShapeLayer
            let maskLayer = CAShapeLayer()
            bubbleView.addLayoutBlock { view in
                let sharpCorners = UIView.uiRectCorner(forOWSDirectionalRectCorner: sharpCorners)
                let bezierPath = UIBezierPath.roundedRect(view.bounds,
                                                          sharpCorners: sharpCorners,
                                                          sharpCornerRadius: sharpCornerRadius,
                                                          wideCornerRadius: wideCornerRadius)
                maskLayer.path = bezierPath.cgPath
            }
            bubbleView.layer.mask = maskLayer
        }

        return bubbleView
    }

    public func configureForRendering(state: State,
                                      delegate: QuotedMessageViewDelegate?,
                                      componentDelegate: CVComponentDelegate,
                                      sharpCorners: OWSDirectionalRectCorner,
                                      cellMeasurement: CVCellMeasurement) {
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
        innerVStackSubviews.append(quotedTextLabel)

        innerVStack.configure(config: configurator.innerVStackConfig,
                              cellMeasurement: cellMeasurement,
                              measurementKey: Self.measurementKey_innerVStack,
                              subviews: innerVStackSubviews)
        hStackSubviews.append(innerVStack)

        let trailingView: UIView = {
            guard configurator.hasQuotedAttachment else {
                // If there's no attachment, add an empty view so that
                // the stack view's spacing serves as a margin between
                // the text views and the trailing edge.
                return UIView.transparentSpacer()
            }

            let quotedImageView = self.quotedImageView
            // Use trilinear filters for better scaling quality at
            // some performance cost.
            quotedImageView.layer.minificationFilter = .trilinear
            quotedImageView.layer.magnificationFilter = .trilinear

            func tryToLoadThumbnailImage() -> UIImage? {
                guard configurator.hasQuotedAttachmentThumbnailImage else {
                    return nil
                }

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
                    let contentImageView = CVImageView()
                    contentImageView.setTemplateImageName("attachment_play_button", tintColor: .white)
                    wrapper.addSubviewToCenterOnSuperviewWithDesiredSize(contentImageView)
                }
                return wrapper
            } else if quotedReplyModel.thumbnailDownloadFailed {
                let wrapper = ManualLayoutViewWithLayer(name: "thumbnailDownloadFailedWrapper")
                wrapper.backgroundColor = configurator.highlightColor

                // TODO: design review icon and color
                quotedImageView.setTemplateImageName("btnRefresh--white", tintColor: .white)
                quotedImageView.contentMode = .scaleAspectFit
                quotedImageView.clipsToBounds = false
                let iconSize = CGSize.square(configurator.quotedAttachmentSize * 0.5)
                wrapper.addSubviewToCenterOnSuperview(quotedImageView, size: iconSize)

                wrapper.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                                    action: #selector(didTapFailedThumbnailDownload)))
                wrapper.isUserInteractionEnabled = true

                return wrapper
            } else {
                quotedImageView.setTemplateImageName("generic-attachment", tintColor: .clear)
                quotedImageView.contentMode = .scaleAspectFit
                quotedImageView.clipsToBounds = false
                quotedImageView.tintColor = nil

                let wrapper = ManualLayoutView(name: "genericAttachmentWrapper")
                let iconSize = CGSize.square(configurator.quotedAttachmentSize * 0.5)
                wrapper.addSubviewToCenterOnSuperview(quotedImageView, size: iconSize)
                return wrapper
            }
        }()
        hStackSubviews.append(trailingView)

        if configurator.isForPreview {
            let cancelButton = UIButton(type: .custom)
            let cancelIcon = UIImage(named: "compose-cancel")?.withRenderingMode(.alwaysTemplate)
            cancelButton.setImage(cancelIcon, for: .normal)
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
            remotelySourcedContentIconView.setTemplateImageName("ic_broken_link",
                                                                tintColor: Theme.lightThemePrimaryColor)

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

        let bubbleView = createBubbleView(sharpCorners: sharpCorners,
                                          conversationStyle: conversationStyle,
                                          configurator: configurator,
                                          componentDelegate: componentDelegate)
        bubbleView.addSubviewToFillSuperviewEdges(outerVStack)
        bubbleView.clipsToBounds = true

        self.configure(config: configurator.outerStackConfig,
                       cellMeasurement: cellMeasurement,
                       measurementKey: Self.measurementKey_outerStack,
                       subviews: [ bubbleView ])
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
        let hasQuotedAttachment = configurator.hasQuotedAttachment
        let quotedAttachmentSize = configurator.quotedAttachmentSize
        let quotedReplyModel = configurator.quotedReplyModel

        var maxLabelWidth = (maxWidth - (configurator.stripeThickness +
                                            hStackConfig.spacing * 2 +
                                            hStackConfig.layoutMargins.totalWidth +
                                            innerVStackConfig.layoutMargins.totalWidth +
                                            outerVStackConfig.layoutMargins.totalWidth +
                                            outerStackConfig.layoutMargins.totalWidth))
        if hasQuotedAttachment {
            maxLabelWidth -= quotedAttachmentSize
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

        let avatarSize: CGSize = (hasQuotedAttachment
                                    ? .square(quotedAttachmentSize)
                                    : .square(0))
        hStackSubviewInfos.append(avatarSize.asManualSubviewInfo(hasFixedWidth: true))

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

        let outerStackMeasurement = ManualStackView.measure(config: outerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_outerStack,
                                                            subviewInfos: [
                                                                outerVStackMeasurement.measuredSize.asManualSubviewInfo
                                                            ],
                                                            maxWidth: maxWidth)
        return outerStackMeasurement.measuredSize
    }

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
