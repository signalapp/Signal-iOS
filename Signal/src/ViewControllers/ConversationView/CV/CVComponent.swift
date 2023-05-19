//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

// Represents some _renderable_ portion of an Conversation View item.
// It could be the entire item or some part thereof.
public protocol CVComponent: AnyObject {

    var componentKey: CVComponentKey { get }

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

    func findLongPressHandler(sender: UIGestureRecognizer,
                              componentDelegate: CVComponentDelegate,
                              componentView: CVComponentView,
                              renderItem: CVRenderItem) -> CVLongPressHandler?

    func findPanHandler(sender: UIPanGestureRecognizer,
                        componentDelegate: CVComponentDelegate,
                        componentView: CVComponentView,
                        renderItem: CVRenderItem,
                        messageSwipeActionState: CVMessageSwipeActionState) -> CVPanHandler?
    func startPanGesture(sender: UIPanGestureRecognizer,
                         panHandler: CVPanHandler,
                         componentDelegate: CVComponentDelegate,
                         componentView: CVComponentView,
                         renderItem: CVRenderItem,
                         messageSwipeActionState: CVMessageSwipeActionState)
    func handlePanGesture(sender: UIPanGestureRecognizer,
                          panHandler: CVPanHandler,
                          componentDelegate: CVComponentDelegate,
                          componentView: CVComponentView,
                          renderItem: CVRenderItem,
                          messageSwipeActionState: CVMessageSwipeActionState)

    func cellDidLayoutSubviews(componentView: CVComponentView,
                               renderItem: CVRenderItem,
                               messageSwipeActionState: CVMessageSwipeActionState)

    func cellDidBecomeVisible(componentView: CVComponentView,
                              renderItem: CVRenderItem,
                              messageSwipeActionState: CVMessageSwipeActionState)

    func updateScrollingContent(componentView: CVComponentView)

    func contextMenuAccessoryViews(componentView: CVComponentView) -> [ContextMenuTargetedPreviewAccessory]?

    func apply(layoutAttributes: CVCollectionViewLayoutAttributes,
               componentView: CVComponentView)
}

// MARK: -

public protocol CVRootComponent: CVComponent {

    var componentState: CVComponentState { get }

    var cellReuseIdentifier: CVCellReuseIdentifier { get }

    func configureCellRootComponent(cellView: UIView,
                                    cellMeasurement: CVCellMeasurement,
                                    componentDelegate: CVComponentDelegate,
                                    messageSwipeActionState: CVMessageSwipeActionState,
                                    componentView: CVComponentView)

    var isDedicatedCell: Bool { get }
}

// MARK: -

public protocol CVAccessibilityComponent: CVComponent {
    var accessibilityDescription: String { get }

    // TODO: We should have a getter for "accessiblity actions",
    //       presumably as [CVMessageAction].
}

// MARK: -

public class CVComponentBase: NSObject {
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

    public func findLongPressHandler(sender: UIGestureRecognizer,
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
                               messageSwipeActionState: CVMessageSwipeActionState) -> CVPanHandler? {
        Logger.verbose("Ignoring pan.")
        return nil
    }

    public func startPanGesture(sender: UIPanGestureRecognizer,
                                panHandler: CVPanHandler,
                                componentDelegate: CVComponentDelegate,
                                componentView: CVComponentView,
                                renderItem: CVRenderItem,
                                messageSwipeActionState: CVMessageSwipeActionState) {
        owsFailDebug("No pan in progress.")
    }

    public func handlePanGesture(sender: UIPanGestureRecognizer,
                                 panHandler: CVPanHandler,
                                 componentDelegate: CVComponentDelegate,
                                 componentView: CVComponentView,
                                 renderItem: CVRenderItem,
                                 messageSwipeActionState: CVMessageSwipeActionState) {
        owsFailDebug("No pan in progress.")
    }

    public func cellDidLayoutSubviews(componentView: CVComponentView,
                                      renderItem: CVRenderItem,
                                      messageSwipeActionState: CVMessageSwipeActionState) {
        // Do nothing.
    }

    public func cellDidBecomeVisible(componentView: CVComponentView,
                                     renderItem: CVRenderItem,
                                     messageSwipeActionState: CVMessageSwipeActionState) {
        // Do nothing.
    }

    public func contextMenuAccessoryViews(componentView: CVComponentView) -> [ContextMenuTargetedPreviewAccessory]? {
        return nil
    }

    public func apply(layoutAttributes: CVCollectionViewLayoutAttributes,
                      componentView: CVComponentView) {
        // Do nothing.
    }

    var uiMode: ConversationUIMode { itemModel.itemViewState.uiMode }
    var previousUIMode: ConversationUIMode { itemModel.itemViewState.previousUIMode }
    var isShowingSelectionUI: Bool { uiMode.hasSelectionUI }
    var wasShowingSelectionUI: Bool { previousUIMode.hasSelectionUI }

    // MARK: - Root Components

    public static func configureCellRootComponent(rootComponent: CVRootComponent,
                                                  cellView: UIView,
                                                  cellMeasurement: CVCellMeasurement,
                                                  componentDelegate: CVComponentDelegate,
                                                  componentView: CVComponentView) {
        owsAssertDebug(cellView.layoutMargins == .zero)

        rootComponent.configureForRendering(componentView: componentView,
                                            cellMeasurement: cellMeasurement,
                                            componentDelegate: componentDelegate)

        let rootView = componentView.rootView
        if rootView.superview == nil {
            owsAssertDebug(cellView.subviews.isEmpty)

            cellView.addSubview(rootView)
            cellView.layoutMargins = .zero
            rootView.autoPinEdgesToSuperviewEdges()
        }
    }

    // MARK: - 

    public func wallpaperBlurView(componentView: CVComponentView) -> CVWallpaperBlurView? {
        nil
    }

    public func configureWallpaperBlurView(wallpaperBlurView: CVWallpaperBlurView,
                                           maskCornerRadius: CGFloat,
                                           componentDelegate: CVComponentDelegate) {
        Self.configureWallpaperBlurView(wallpaperBlurView: wallpaperBlurView,
                                        maskCornerRadius: maskCornerRadius,
                                        componentDelegate: componentDelegate)
    }

    public static func configureWallpaperBlurView(wallpaperBlurView: CVWallpaperBlurView,
                                                  maskCornerRadius: CGFloat,
                                                  componentDelegate: CVComponentDelegate) {
        if componentDelegate.isConversationPreview {
            wallpaperBlurView.configureForPreview(maskCornerRadius: maskCornerRadius)
        } else if let wallpaperBlurProvider = componentDelegate.wallpaperBlurProvider {
            wallpaperBlurView.configure(provider: wallpaperBlurProvider,
                                        maskCornerRadius: maskCornerRadius)
        } else {
            owsFailDebug("Missing wallpaperBlurProvider.")
            wallpaperBlurView.configureForPreview(maskCornerRadius: maskCornerRadius)
        }
    }

    public func updateScrollingContent(componentView: CVComponentView) {
        updateWallpaperBlur(componentView: componentView)
    }

    private func updateWallpaperBlur(componentView: CVComponentView) {
        guard let wallpaperBlurView = self.wallpaperBlurView(componentView: componentView) else {
            return
        }
        wallpaperBlurView.updateIfNecessary()
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
    public var mediaCache: CVMediaCache { itemModel.mediaCache }
    public var isDarkThemeEnabled: Bool { conversationStyle.isDarkThemeEnabled }

    public var isGroupThread: Bool {
        thread.isGroupThread
    }

    public var isBorderless: Bool {
        if componentState.isBorderlessJumbomojiMessage {
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

    // Allows component opportunity to configure and return a subview for context menu previews
    @objc
    optional func contextMenuContentView() -> UIView?

    // Allows component opportunity to configure and return an auxiliary content subview for context menu previews
    // This will only be used if contextMenuContentView() is implemented
    @objc
    optional func contextMenuAuxiliaryContentView() -> UIView?

    // Called when the context menu presentation will begin,
    // can be used to configure component view below presenting context menu
    @objc
    optional func contextMenuPresentationWillBegin()

    // Called once the context menu presentation ends
    @objc
    optional func contextMenuPresentationDidEnd()
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
    case footer
    case bodyText
    case bodyMedia
    case senderName
    case senderAvatar
    case sticker
    case quotedReply
    case linkPreview
    case giftBadge
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
    case unknownThreadWarning
    case defaultDisappearingMessageTimer
    case messageRoot

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
        case .giftBadge:
            return ".giftBadge"
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
        case .unknownThreadWarning:
            return ".unknownThreadWarning"
        case .failedOrPendingDownloads:
            return ".failedOrPendingDownloads"
        case .sendFailureBadge:
            return ".sendFailureBadge"
        case .defaultDisappearingMessageTimer:
            return ".defaultDisappearingMessageTimer"
        case .messageRoot:
            return ".messageRoot"
        }
    }

    var asKey: String { description }
}
