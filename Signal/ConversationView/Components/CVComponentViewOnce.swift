//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

enum ViewOnceState: Equatable {
    case unknown
    case incomingExpired
    case incomingDownloading(attachmentPointer: AttachmentPointer, renderingFlag: AttachmentReference.RenderingFlag)
    case incomingFailed
    case incomingPending
    case incomingAvailable(attachmentStream: AttachmentStream, renderingFlag: AttachmentReference.RenderingFlag)
    case incomingUndownloadable
    case incomingInvalidContent
    case outgoingSending
    case outgoingFailed
    case outgoingSentExpired

    static func == (lhs: ViewOnceState, rhs: ViewOnceState) -> Bool {
        switch (lhs, rhs) {
        case
            (.unknown, .unknown),
            (.incomingExpired, .incomingExpired),
            (.incomingFailed, .incomingFailed),
            (.incomingPending, .incomingPending),
            (.incomingUndownloadable, .incomingUndownloadable),
            (.incomingInvalidContent, .incomingInvalidContent),
            (.outgoingSending, .outgoingSending),
            (.outgoingFailed, .outgoingFailed),
            (.outgoingSentExpired, .outgoingSentExpired):
            return true
        case let (.incomingDownloading(lhsPointer, lhsFlag), .incomingDownloading(rhsPointer, rhsFlag)):
            return lhsPointer.id == rhsPointer.id
                && lhsFlag == rhsFlag
        case let (.incomingAvailable(lhsStream, lhsFlag), .incomingAvailable(rhsStream, rhsFlag)):
            return lhsStream.id == rhsStream.id
                && lhsFlag == rhsFlag
        case
            (.unknown, _),
            (.incomingExpired, _),
            (.incomingFailed, _),
            (.incomingPending, _),
            (.incomingUndownloadable, _),
            (.incomingInvalidContent, _),
            (.outgoingSending, _),
            (.outgoingFailed, _),
            (.outgoingSentExpired, _),
            (.incomingDownloading, _),
            (.incomingAvailable, _):
            return false
        }
    }
}

// MARK: -

final public class CVComponentViewOnce: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .viewOnce }

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
    private var attachmentStream: AttachmentStream? {
        if case .incomingAvailable(let attachmentStream, _) = viewOnceState {
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

        var subviews = [UIView]()

        switch viewOnceState {
        case .incomingDownloading(let attachmentPointer, _):
            let progressView = CVAttachmentProgressView(
                direction: .download(
                    attachmentPointer: attachmentPointer,
                    downloadState: .enqueuedOrDownloading
                ),
                diameter: iconSize,
                isDarkThemeEnabled: conversationStyle.isDarkThemeEnabled,
                mediaCache: mediaCache
            )
            subviews.append(progressView)
        default:
            if shouldShowIcon, let iconName = self.iconName {
                let iconView = componentView.iconView
                iconView.setTemplateImageName(iconName, tintColor: iconColor)
                subviews.append(iconView)
            }
        }

        let label = componentView.label
        labelConfig.applyForRendering(label: label)
        subviews.append(label)

        let stackView = componentView.stackView
        stackView.reset()
        stackView.configure(config: stackViewConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: Self.measurementKey_stackView,
                            subviews: subviews)
    }

    private let iconSize: CGFloat = 24

    private var downloadProgressRadius: CGFloat {
        iconSize * 0.5
    }

    private var stackViewConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: 8,
                          layoutMargins: .zero)
    }

    private static let measurementKey_stackView = "CVComponentViewOnce.measurementKey_stackView"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var subviewInfos = [ManualStackSubviewInfo]()

        let hasIcon = shouldShowIcon && iconName != nil
        let hasIconOrProgress = hasIcon || shouldShowProgress

        var availableWidth = maxWidth
        if hasIconOrProgress {
            availableWidth = max(0, availableWidth - (iconSize + stackViewConfig.spacing))
            subviewInfos.append(CGSize.square(iconSize).asManualSubviewInfo(hasFixedSize: true))
        }
        let textSize = CVText.measureLabel(config: labelConfig, maxWidth: availableWidth)
        subviewInfos.append(textSize.asManualSubviewInfo)

        let stackMeasurement = ManualStackView.measure(config: stackViewConfig,
                                                       measurementBuilder: measurementBuilder,
                                                       measurementKey: Self.measurementKey_stackView,
                                                       subviewInfos: subviewInfos,
                                                       maxWidth: maxWidth)
        var result = stackMeasurement.measuredSize
        // We use this "min width" to reduce/avoid "flutter"
        // in the bubble's size as the message changes states.
        let minContentWidth: CGFloat = maxWidth * 0.4
        result.width = max(result.width, minContentWidth)
        return result
    }

    // MARK: - Events

    public override func handleTap(sender: UIGestureRecognizer,
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
            componentDelegate.didTapFailedOrPendingDownloads(message)
        case .incomingAvailable:
            componentDelegate.didTapViewOnceAttachment(message)
        case .incomingExpired, .outgoingSentExpired:
            componentDelegate.didTapViewOnceExpired(message)
        case .outgoingFailed,
             .outgoingSending:
            break
        case .incomingUndownloadable:
            componentDelegate.didTapUndownloadableMedia()
        }
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewViewOnce: NSObject, CVComponentView {

        fileprivate let stackView = ManualStackView(name: "viewOnce")
        fileprivate let iconView = CVImageView()
        fileprivate let label = CVLabel()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            stackView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            stackView.reset()
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
            return "view_once-dash"
        case .incomingExpired, .incomingUndownloadable:
            return "view_once-dash"
        case .incomingDownloading:
            owsFailDebug("Unexpected state.")
            return nil
        case .incomingFailed, .incomingPending:
            return "arrow-circle-down"
        case .incomingAvailable:
            return "view_once"
        case .outgoingFailed:
            return "refresh"
        case .outgoingSending,
             .outgoingSentExpired:
            return "view_once-dash"
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
             .incomingAvailable,
             .incomingUndownloadable:
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
        case .incomingExpired, .incomingUndownloadable:
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
            return CVLabelConfig.unstyledText(
                text,
                font: UIFont.dynamicTypeSubheadline.semibold(),
                textColor: textColor,
                numberOfLines: 1,
                lineBreakMode: .byTruncatingTail
            )
        }

        switch viewOnceState {
        case .unknown:
            owsFailDebug("Invalid value.")
            return buildDefaultConfig(text: CommonStrings.genericError)
        case .incomingExpired:
            let text = OWSLocalizedString("PER_MESSAGE_EXPIRATION_VIEWED",
                                         comment: "Label for view-once messages indicating that the local user has viewed the message's contents.")
            return buildDefaultConfig(text: text)
        case .incomingUndownloadable:
            let text = OWSLocalizedString(
                "PER_MESSAGE_EXPIRATION_EXPIRED",
                comment: "Label for view-once messages indicating that the message's contents are expired and unavailable to download."
            )
            return buildDefaultConfig(text: text)
        case .incomingDownloading:
            let text = OWSLocalizedString("MESSAGE_STATUS_DOWNLOADING", comment: "message status while message is downloading.")
            return buildDefaultConfig(text: text)
        case .incomingFailed:
            let text = CommonStrings.retryButton
            return buildDefaultConfig(text: text)
        case .incomingPending:
            let text = OWSLocalizedString("ACTION_TAP_TO_DOWNLOAD", comment: "A label for 'tap to download' buttons.")
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
            let text = OWSLocalizedString(
                "PER_MESSAGE_EXPIRATION_OUTGOING_MESSAGE", comment: "Label for outgoing view-once messages.")
            return buildDefaultConfig(text: text)
        case .incomingInvalidContent:
            let text = OWSLocalizedString(
                "PER_MESSAGE_EXPIRATION_INVALID_CONTENT", comment: "Label for view-once messages that have invalid content.")
            // Reconfigure label for this state only.
            return CVLabelConfig.unstyledText(
                text,
                font: UIFont.dynamicTypeSubheadline,
                textColor: Theme.secondaryTextAndIconColor,
                numberOfLines: 0,
                lineBreakMode: .byWordWrapping
            )
        }
    }

    private var viewOnceMessageType: ViewOnceMessageType {
        switch viewOnceState {
        case let .incomingAvailable(attachmentStream, _):
            switch attachmentStream.contentType {
            case .file, .invalid, .audio:
                owsFailDebug("Invalid view once type")
                return .unknown
            case .image:
                return .photo
            case .video:
                return .video
            case .animatedImage:
                return .photo
            }
        case .unknown,
             .incomingExpired,
             .incomingDownloading,
             .incomingFailed,
             .incomingPending,
             .incomingUndownloadable,
             .incomingInvalidContent,
             .outgoingSending,
             .outgoingFailed,
             .outgoingSentExpired:
            // The attachment doesn't exist for outgoing
            // messages so we'd need to store the content type if
            // we wanted to distinguish between photo and video

            // For incoming messages viewed messages, it doesn't matter
            // because we show generic "View" text, regardless of the
            // content type
            return .unknown
        }
    }
}

// MARK: -

extension CVComponentViewOnce: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        // TODO: We could include the media type (video, image, animated image).
        labelConfig.text.accessibilityDescription
    }
}
