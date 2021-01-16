//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

enum ViewOnceState: Equatable {
    case unknown
    case incomingExpired
    case incomingDownloading(attachmentPointer: TSAttachmentPointer)
    case incomingFailed
    case incomingPending
    case incomingAvailable(attachmentStream: TSAttachmentStream)
    case incomingInvalidContent
    case outgoingSending
    case outgoingFailed
    case outgoingSentExpired
}

// MARK: -

@objc
public class CVComponentViewOnce: CVComponentBase, CVComponent {

    private enum ViewOnceMessageType: Equatable {
        case unknown
        case photo
        case video
    }

    // MARK: -

    private let viewOnce: CVComponentState.ViewOnce
    private var viewOnceState: ViewOnceState {
        viewOnce.viewOnceState
    }
    private var isExpired: Bool {
        switch viewOnce.viewOnceState {
        case .incomingExpired, .outgoingSentExpired:
            return true
        default:
            return false
        }
    }
    private var attachmentStream: TSAttachmentStream? {
        if case .incomingAvailable(let attachmentStream) = viewOnceState {
            return attachmentStream
        }
        return nil
    }
    private var shouldShowIcon: Bool {
        switch viewOnceState {
        case .incomingInvalidContent, .incomingDownloading:
            return false
        default:
            return true
        }
    }
    private var shouldShowProgress: Bool {
        switch viewOnceState {
        case .incomingDownloading:
            return true
        default:
            return false
        }
    }

    init(itemModel: CVItemModel, viewOnce: CVComponentState.ViewOnce) {
        self.viewOnce = viewOnce

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewViewOnce()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewViewOnce else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        componentView.hStackView.apply(config: hStackViewConfig)

        switch viewOnceState {
        case .incomingDownloading(let attachmentPointer):
            let progressView = MediaDownloadView(attachmentId: attachmentPointer.uniqueId, radius: downloadProgressRadius)
            progressView.progressColor = textColor
            progressView.autoSetDimensions(to: CGSize(square: iconSize))
            progressView.setContentHuggingHigh()
            progressView.setCompressionResistanceHigh()
            componentView.hStackView.addArrangedSubview(progressView)
        default:
            if shouldShowIcon, let iconName = self.iconName {
                let iconView = componentView.iconView
                iconView.setTemplateImageName(iconName, tintColor: iconColor)
                iconView.autoSetDimensions(to: CGSize(square: iconSize))
                iconView.setContentHuggingHigh()
                iconView.setCompressionResistanceHigh()
                componentView.hStackView.addArrangedSubview(iconView)
            }
        }

        labelConfig.applyForRendering(label: componentView.label)
        componentView.hStackView.addArrangedSubview(componentView.label)
    }

    private let iconSize: CGFloat = 24

    private var downloadProgressRadius: CGFloat {
        iconSize * 0.5
    }

    private var hStackViewConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: 8,
                          layoutMargins: .zero)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let hasIcon = shouldShowIcon && iconName != nil
        let hasIconOrProgress = hasIcon || shouldShowProgress

        var availableWidth = maxWidth
        if hasIconOrProgress {
            availableWidth = max(0, availableWidth - (iconSize + hStackViewConfig.spacing))
        }
        let textSize = CVText.measureLabel(config: labelConfig, maxWidth: availableWidth)
        var width = textSize.width
        var height = textSize.height
        if hasIconOrProgress {
            width += iconSize + hStackViewConfig.spacing
            height = max(height, iconSize)
        }
        width += hStackViewConfig.layoutMargins.totalWidth
        height += hStackViewConfig.layoutMargins.totalHeight

        // We use this "min width" to reduce/avoid "flutter"
        // in the bubble's size as the message changes states.
        let minContentWidth: CGFloat = maxWidth * 0.4
        width = max(width, minContentWidth)

        return CGSize(width: width, height: height).ceil
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {
        AssertIsOnMainThread()

        guard let message = interaction as? TSMessage else {
            owsFailDebug("Invalid interaction.")
            return false
        }

        switch viewOnceState {
        case .unknown:
            owsFailDebug("Invalid value.")
        case .incomingDownloading,
             .incomingInvalidContent:
            break
        case .incomingFailed, .incomingPending:
            componentDelegate.cvc_didTapFailedOrPendingDownloads(message)
        case .incomingAvailable:
            componentDelegate.cvc_didTapViewOnceAttachment(message)
        case .incomingExpired, .outgoingSentExpired:
            componentDelegate.cvc_didTapViewOnceExpired(message)
        case .outgoingFailed,
             .outgoingSending:
            break
        }
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewViewOnce: NSObject, CVComponentView {

        fileprivate let hStackView = OWSStackView(name: "viewOnce")
        fileprivate let iconView = UIImageView()
        fileprivate let label = UILabel()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            hStackView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            hStackView.reset()
            iconView.image = nil
            label.text = nil
        }
    }
}

// MARK: -

fileprivate extension CVComponentViewOnce {
    var iconName: String? {
        switch viewOnceState {
        case .unknown:
            owsFailDebug("Invalid value.")
            return "viewed-once-24"
        case .incomingExpired:
            return "viewed-once-24"
        case .incomingDownloading:
            owsFailDebug("Unexpected state.")
            return nil
        case .incomingFailed, .incomingPending:
            return "arrow-down-circle-outline-24"
        case .incomingAvailable:
            return "view-once-24"
        case .outgoingFailed:
            return "retry-24"
        case .outgoingSending,
             .outgoingSentExpired:
            return "viewed-once-24"
        case .incomingInvalidContent:
            owsFailDebug("Unexpected state.")
            return nil
        }
    }

    var textColor: UIColor {
        switch viewOnceState {
        case .unknown:
            owsFailDebug("Invalid value.")
            return conversationStyle.bubbleTextColorIncoming
        case .incomingExpired,
             .incomingDownloading,
             .incomingFailed,
             .incomingPending,
             .incomingAvailable:
            return conversationStyle.bubbleTextColorIncoming
        case .outgoingFailed,
             .outgoingSending,
             .outgoingSentExpired:
            return conversationStyle.bubbleTextColorOutgoing
        case .incomingInvalidContent:
            return Theme.secondaryTextAndIconColor
        }
    }

    var iconColor: UIColor {
        let pendingColor: UIColor = (Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray75)

        switch viewOnceState {
        case .unknown:
            owsFailDebug("Invalid value.")
            return conversationStyle.bubbleTextColorIncoming
        case .incomingExpired:
            return conversationStyle.bubbleTextColorIncoming
        case .incomingDownloading,
             .incomingFailed,
             .incomingPending:
            return pendingColor
        case .incomingAvailable:
            return conversationStyle.bubbleTextColorIncoming
        case .outgoingFailed:
            return pendingColor
        case .outgoingSending,
             .outgoingSentExpired:
            return conversationStyle.bubbleTextColorOutgoing
        case .incomingInvalidContent:
            return Theme.secondaryTextAndIconColor
        }
    }

    var labelConfig: CVLabelConfig {
        func buildDefaultConfig(text: String) -> CVLabelConfig {
            return CVLabelConfig(text: text,
                                 font: UIFont.ows_dynamicTypeSubheadline.ows_semibold,
                                 textColor: textColor,
                                 numberOfLines: 1,
                                 lineBreakMode: .byTruncatingTail)
        }

        switch viewOnceState {
        case .unknown:
            owsFailDebug("Invalid value.")
            return buildDefaultConfig(text: CommonStrings.genericError)
        case .incomingExpired:
            let text = NSLocalizedString("PER_MESSAGE_EXPIRATION_VIEWED",
                                         comment: "Label for view-once messages indicating that the local user has viewed the message's contents.")
            return buildDefaultConfig(text: text)
        case .incomingDownloading:
            let text = NSLocalizedString("MESSAGE_STATUS_DOWNLOADING", comment: "message status while message is downloading.")
            return buildDefaultConfig(text: text)
        case .incomingFailed:
            let text = CommonStrings.retryButton
            return buildDefaultConfig(text: text)
        case .incomingPending:
            let text = NSLocalizedString("ACTION_TAP_TO_DOWNLOAD", comment: "A label for 'tap to download' buttons.")
            return buildDefaultConfig(text: text)
        case .incomingAvailable:
            let text: String
            switch viewOnceMessageType {
            case .photo:
                text = MessageStrings.viewOnceViewPhoto
            case .video:
                text = MessageStrings.viewOnceViewVideo
            case .unknown:
                owsFailDebug("unexpected viewOnceMessageType for IncomingFailed.")
                text = MessageStrings.viewOnceViewPhoto
            }
            return buildDefaultConfig(text: text)
        case .outgoingFailed:
            let text = CommonStrings.retryButton
            return buildDefaultConfig(text: text)
        case .outgoingSending,
             .outgoingSentExpired:
            let text = NSLocalizedString(
                "PER_MESSAGE_EXPIRATION_OUTGOING_MESSAGE", comment: "Label for outgoing view-once messages.")
            return buildDefaultConfig(text: text)
        case .incomingInvalidContent:
            let text = NSLocalizedString(
                "PER_MESSAGE_EXPIRATION_INVALID_CONTENT", comment: "Label for view-once messages that have invalid content.")
            // Reconfigure label for this state only.
            return CVLabelConfig(text: text,
                                 font: UIFont.ows_dynamicTypeSubheadline,
                                 textColor: Theme.secondaryTextAndIconColor,
                                 numberOfLines: 0,
                                 lineBreakMode: .byWordWrapping)
        }
    }

    private var viewOnceMessageType: ViewOnceMessageType {
        guard let attachmentStream = self.attachmentStream else {
            // The attachment doesn't exist for outgoing
            // messages so we'd need to store the content type if
            // we wanted to distinguish between photo and video

            // For incoming messages viewed messages, it doesn't matter
            // because we show generic "View" text, regardless of the
            // content type
            return .unknown
        }

        if attachmentStream.isVideo {
            return .video
        } else {
            owsAssertDebug(attachmentStream.isImage || attachmentStream.isAnimated)
            return .photo
        }
    }
}
