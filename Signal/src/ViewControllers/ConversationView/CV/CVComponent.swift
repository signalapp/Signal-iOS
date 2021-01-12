//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// Represents some _renderable_ portion of an Conversation View item.
// It could be the entire item or some part thereof.
public protocol CVComponent: class {

    var itemModel: CVItemModel { get }

    func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView

    func configureForRendering(componentView: CVComponentView,
                               cellMeasurement: CVCellMeasurement,
                               componentDelegate: CVComponentDelegate)

    // This method should only be called on workQueue.
    func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize

    // return true IFF the tap was handled.
    func handleTap(sender: UITapGestureRecognizer,
                   componentDelegate: CVComponentDelegate,
                   componentView: CVComponentView,
                   renderItem: CVRenderItem) -> Bool

    func findLongPressHandler(sender: UILongPressGestureRecognizer,
                              componentDelegate: CVComponentDelegate,
                              componentView: CVComponentView,
                              renderItem: CVRenderItem) -> CVLongPressHandler?

    func findPanHandler(sender: UIPanGestureRecognizer,
                        componentDelegate: CVComponentDelegate,
                        componentView: CVComponentView,
                        renderItem: CVRenderItem,
                        swipeToReplyState: CVSwipeToReplyState) -> CVPanHandler?
    func startPanGesture(sender: UIPanGestureRecognizer,
                         panHandler: CVPanHandler,
                         componentDelegate: CVComponentDelegate,
                         componentView: CVComponentView,
                         renderItem: CVRenderItem,
                         swipeToReplyState: CVSwipeToReplyState)
    func handlePanGesture(sender: UIPanGestureRecognizer,
                          panHandler: CVPanHandler,
                          componentDelegate: CVComponentDelegate,
                          componentView: CVComponentView,
                          renderItem: CVRenderItem,
                          swipeToReplyState: CVSwipeToReplyState)

    func cellDidLayoutSubviews(componentView: CVComponentView,
                               renderItem: CVRenderItem,
                               swipeToReplyState: CVSwipeToReplyState)

    func cellDidBecomeVisible(componentView: CVComponentView,
                              renderItem: CVRenderItem,
                              swipeToReplyState: CVSwipeToReplyState)

    func incompleteAttachmentInfo(componentView: CVComponentView) -> IncompleteAttachmentInfo?
}

// MARK: -

public struct IncompleteAttachmentInfo {
    let attachment: TSAttachment
    let attachmentView: UIView
    let shouldShowDownloadProgress: Bool
}

// MARK: -

public struct ProgressViewToken {
    let reset: () -> Void
}

// MARK: -

public protocol CVRootComponent: CVComponent {

    var componentState: CVComponentState { get }

    var cellReuseIdentifier: CVCellReuseIdentifier { get }

    func configure(cellView: UIView,
                   cellMeasurement: CVCellMeasurement,
                   componentDelegate: CVComponentDelegate,
                   cellSelection: CVCellSelection,
                   swipeToReplyState: CVSwipeToReplyState,
                   componentView: CVComponentView)

    var isDedicatedCell: Bool { get }
}

// MARK: -

// CVCellMeasurement captures the measurement state from the load.
// This lets us pin cell views to their measured sizes.  This is
// necessary because some UIViews (like UIImageView) set up
// layout contraints based on their content that we want to override.
public struct CVCellMeasurement: Equatable {
    let cellSize: CGSize
    private let sizes: [String: CGSize]
    private let values: [String: CGFloat]

    public class Builder {
        var cellSize: CGSize = .zero
        private var sizes = [String: CGSize]()
        private var values = [String: CGFloat]()

        func build() -> CVCellMeasurement {
            CVCellMeasurement(cellSize: cellSize,
                              sizes: sizes,
                              values: values)
        }

        func setSize(key: String, size: CGSize) {
            sizes[key] = size
        }

        func setValue(key: String, value: CGFloat) {
            values[key] = value
        }
    }

    func size(key: String) -> CGSize? {
        sizes[key]
    }

    func value(key: String) -> CGFloat? {
        values[key]
    }

    public var debugDescription: String {
        "[cellSize: \(cellSize), sizes: \(sizes), values: \(values)]"
    }

    public func debugLog() {
        Logger.verbose("cellSize: \(cellSize)")
        Logger.verbose("sizes: \(sizes)")
        Logger.verbose("values: \(values)")
    }
}

// MARK: -

@objc
public class CVComponentBase: NSObject {
    @objc
    public let itemModel: CVItemModel

    init(itemModel: CVItemModel) {
        self.itemModel = itemModel
    }

    public func handleTap(sender: UITapGestureRecognizer,
                          componentDelegate: CVComponentDelegate,
                          componentView: CVComponentView,
                          renderItem: CVRenderItem) -> Bool {
        Logger.verbose("Ignoring tap.")
        return false
    }

    public func findLongPressHandler(sender: UILongPressGestureRecognizer,
                                     componentDelegate: CVComponentDelegate,
                                     componentView: CVComponentView,
                                     renderItem: CVRenderItem) -> CVLongPressHandler? {
        Logger.verbose("Ignoring long press.")
        return nil
    }

    public func findPanHandler(sender: UIPanGestureRecognizer,
                               componentDelegate: CVComponentDelegate,
                               componentView: CVComponentView,
                               renderItem: CVRenderItem,
                               swipeToReplyState: CVSwipeToReplyState) -> CVPanHandler? {
        Logger.verbose("Ignoring pan.")
        return nil
    }

    public func startPanGesture(sender: UIPanGestureRecognizer,
                                panHandler: CVPanHandler,
                                componentDelegate: CVComponentDelegate,
                                componentView: CVComponentView,
                                renderItem: CVRenderItem,
                                swipeToReplyState: CVSwipeToReplyState) {
        owsFailDebug("No pan in progress.")
    }

    public func handlePanGesture(sender: UIPanGestureRecognizer,
                                 panHandler: CVPanHandler,
                                 componentDelegate: CVComponentDelegate,
                                 componentView: CVComponentView,
                                 renderItem: CVRenderItem,
                                 swipeToReplyState: CVSwipeToReplyState) {
        owsFailDebug("No pan in progress.")
    }

    public func cellDidLayoutSubviews(componentView: CVComponentView,
                                      renderItem: CVRenderItem,
                                      swipeToReplyState: CVSwipeToReplyState) {
        // Do nothing.
    }

    public func cellDidBecomeVisible(componentView: CVComponentView,
                                     renderItem: CVRenderItem,
                                     swipeToReplyState: CVSwipeToReplyState) {
        // Do nothing.
    }

    var isShowingSelectionUI: Bool {
        itemModel.itemViewState.isShowingSelectionUI
    }

    public func incompleteAttachmentInfo(componentView: CVComponentView) -> IncompleteAttachmentInfo? { nil }

    func incompleteAttachmentInfoIfNecessary(attachment: TSAttachment,
                                             attachmentView: UIView,
                                             shouldShowDownloadProgress: Bool = true) -> IncompleteAttachmentInfo? {

        let buildInfo = {
            IncompleteAttachmentInfo(attachment: attachment,
                                     attachmentView: attachmentView,
                                     shouldShowDownloadProgress: shouldShowDownloadProgress)
        }

        if let attachmentStream = attachment as? TSAttachmentStream {
            guard isOutgoing, !attachmentStream.isUploaded else {
                return nil
            }
            return buildInfo()
        } else if let attachmentPointer = attachment as? TSAttachmentPointer {
            switch attachmentPointer.state {
            case .failed:
                return buildInfo()
            case .enqueued, .downloading, .pendingMessageRequest, .pendingManualDownload:
                switch attachmentPointer.pointerType {
                case .restoring:
                    // TODO: Show "restoring" indicator and possibly progress.
                    return nil
                case .unknown, .incoming:
                    if !shouldShowDownloadProgress {
                        return nil
                    }
                    return buildInfo()
                @unknown default:
                    owsFailDebug("Invalid value.")
                    return nil
                }
            @unknown default:
                owsFailDebug("Invalid value.")
                return nil
            }
        } else {
            owsFailDebug("Invalid attachment.")
            return nil
        }
    }
}

// MARK: -

extension CVComponentBase: CVNode {
    public var thread: TSThread { itemModel.thread }
    public var interaction: TSInteraction { itemModel.interaction }
    public var componentState: CVComponentState { itemModel.componentState }
    public var itemViewState: CVItemViewState { itemModel.itemViewState }
    public var messageCellType: CVMessageCellType { componentState.messageCellType }
    public var conversationStyle: ConversationStyle { itemModel.conversationStyle }
    public var cellMediaCache: NSCache<NSString, AnyObject> { itemModel.cellMediaCache }
    public var isDarkThemeEnabled: Bool { conversationStyle.isDarkThemeEnabled }

    public var isGroupThread: Bool {
        thread.isGroupThread
    }

    public var isBorderless: Bool {
        if componentState.isJumbomojiMessage {
            return true
        }
        if componentState.isBorderlessBodyMediaMessage {
            return true
        }

        switch messageCellType {
        case .stickerMessage:
            return true
        default:
            return false
        }
    }

    var isTextOnlyMessage: Bool { messageCellType == .textOnlyMessage }

    func accessibilityLabel(description descriptionParam: String?) -> String {
        let description = { () -> String in
            if let description = descriptionParam,
               !description.isEmpty {
                return description
            }
            return NSLocalizedString("ACCESSIBILITY_LABEL_MESSAGE", comment: "Accessibility label for message.")
        }()
        if let authorName = itemViewState.accessibilityAuthorName,
           !authorName.isEmpty {
            return "\(authorName) \(description)"
        } else {
            owsFailDebug("Missing sender name.")
            return description
        }
    }

    // TODO: Make sure we're applying everywhere that we need to.
    func addProgressViewsIfNecessary(attachment: TSAttachment,
                                     attachmentView: UIView,
                                     hostView: UIView,
                                     shouldShowDownloadProgress: Bool) -> ProgressViewToken? {
        if let attachmentStream = attachment as? TSAttachmentStream {
            return addUploadViewIfNecessary(attachmentStream: attachmentStream,
                                            hostView: hostView)
        } else if let attachmentPointer = attachment as? TSAttachmentPointer {
            return addDownloadViewIfNecessary(attachmentPointer: attachmentPointer,
                                              attachmentView: attachmentView,
                                              hostView: hostView,
                                              shouldShowDownloadProgress: shouldShowDownloadProgress)
        } else {
            owsFailDebug("Invalid attachment.")
            return nil
        }
    }

    // TODO: Make sure we're applying everywhere that we need to.
    func addUploadViewIfNecessary(attachmentStream: TSAttachmentStream,
                                  hostView: UIView) -> ProgressViewToken? {
        guard isOutgoing, !attachmentStream.isUploaded else {
            return nil
        }

        let uploadView = AttachmentUploadView(attachment: attachmentStream)
        hostView.addSubview(uploadView)
        uploadView.autoPinEdgesToSuperviewEdges()
        uploadView.setContentHuggingLow()
        uploadView.setCompressionResistanceLow()

        return ProgressViewToken(reset: {
            uploadView.removeFromSuperview()
        })
    }

    func addDownloadViewIfNecessary(attachmentPointer: TSAttachmentPointer,
                                    attachmentView: UIView,
                                    hostView: UIView,
                                    shouldShowDownloadProgress: Bool) -> ProgressViewToken? {

        switch attachmentPointer.state {
        case .failed, .pendingMessageRequest, .pendingManualDownload:
            return nil
        case .enqueued, .downloading:
            break
        @unknown default:
            owsFailDebug("Invalid value.")
            return nil
        }

        switch attachmentPointer.pointerType {
        case .restoring:
            // TODO: Show "restoring" indicator and possibly progress.
            return nil
        case .unknown,
             .incoming:
            break
        @unknown default:
            owsFailDebug("Invalid value.")
            return nil
        }
        if !shouldShowDownloadProgress {
            return nil
        }
        let attachmentId = attachmentPointer.uniqueId
        guard nil != Self.attachmentDownloads.downloadProgress(forAttachmentId: attachmentId) else {
            Logger.warn("Missing download progress.")
            return nil
        }

        let overlayView = UIView.container()
        overlayView.backgroundColor = bubbleColorForMessage.withAlphaComponent(0.5)
        hostView.addSubview(overlayView)
        overlayView.autoPinEdgesToSuperviewEdges()
        overlayView.setContentHuggingLow()
        overlayView.setCompressionResistanceLow()

        let radius = conversationStyle.maxMessageWidth * 0.1
        let downloadView = MediaDownloadView(attachmentId: attachmentId, radius: radius)
        // TODO: Is this okay to overlay over the attachment view?
        // Will it have the right alignment?
        hostView.addSubview(downloadView)
        downloadView.autoPinEdgesToSuperviewEdges()
        downloadView.setContentHuggingLow()
        downloadView.setCompressionResistanceLow()

        attachmentView.layer.opacity = 0.5

        return ProgressViewToken(reset: {
            overlayView.removeFromSuperview()
            downloadView.removeFromSuperview()
            attachmentView.layer.opacity = 1
        })
    }

    // This var should only be accessed for messages.
    var bubbleColorForMessage: UIColor {
        guard let message = interaction as? TSMessage else {
            owsFailDebug("Invalid interaction.")
            return conversationStyle.bubbleColor(isIncoming: true)
        }
        return conversationStyle.bubbleColor(message: message)
    }
}

// MARK: -

extension CVComponentBase {

    // MARK: - Dependencies

    static var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    static var profileManager: OWSProfileManager {
        return .shared()
    }

    static var attachmentDownloads: OWSAttachmentDownloads {
        return SSKEnvironment.shared.attachmentDownloads
    }
}

// MARK: -

// Used for rendering some portion of an Conversation View item.
// It could be the entire item or some part thereof.
@objc
public protocol CVComponentView {

    var rootView: UIView { get }

    var isDedicatedCellView: Bool { get set }

    func setIsCellVisible(_ isCellVisible: Bool)

    func reset()
}

// MARK: -

public struct CVComponentAndView {
    let key: CVComponentKey
    let component: CVComponent
    let componentView: CVComponentView
}

// MARK: -

public enum CVComponentKey: CustomStringConvertible, CaseIterable {
    // These components appear in CVComponentMessage.
    case bodyText
    case bodyMedia
    case senderName
    case senderAvatar
    case footer
    case sticker
    case quotedReply
    case linkPreview
    case reactions
    case viewOnce
    case audioAttachment
    case genericAttachment
    case contactShare
    case bottomButtons
    case sendFailureBadge

    case systemMessage
    case dateHeader
    case unreadIndicator
    case typingIndicator
    case threadDetails
    case failedOrPendingDownloads

    public var description: String {
        switch self {
        case .bodyText:
            return ".bodyText"
        case .bodyMedia:
            return ".bodyMedia"
        case .senderName:
            return ".senderName"
        case .senderAvatar:
            return ".senderAvatar"
        case .footer:
            return ".footer"
        case .sticker:
            return ".sticker"
        case .quotedReply:
            return ".quotedReply"
        case .linkPreview:
            return ".linkPreview"
        case .reactions:
            return ".reactions"
        case .viewOnce:
            return ".viewOnce"
        case .audioAttachment:
            return ".audioAttachment"
        case .genericAttachment:
            return ".genericAttachment"
        case .contactShare:
            return ".contactShare"
        case .bottomButtons:
            return ".bottomButtons"
        case .systemMessage:
            return ".systemMessage"
        case .dateHeader:
            return ".dateHeader"
        case .unreadIndicator:
            return ".unreadIndicator"
        case .typingIndicator:
            return ".typingIndicator"
        case .threadDetails:
            return ".threadDetails"
        case .failedOrPendingDownloads:
            return ".failedOrPendingDownloads"
        case .sendFailureBadge:
            return ".sendFailureBadge"
        }
    }

    var asKey: String { description }
}
