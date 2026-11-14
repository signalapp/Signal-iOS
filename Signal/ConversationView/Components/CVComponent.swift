//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// Represents some _renderable_ portion of an Conversation View item.
// It could be the entire item or some part thereof.
protocol CVComponent: AnyObject {

    var componentKey: CVComponentKey { get }

    var itemModel: CVItemModel { get }

    func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView

    func configureForRendering(
        componentView: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    )

    // This method should only be called on workQueue.
    func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize

    // return true IFF the tap was handled.
    func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool

    func canHandleDoubleTap(
        sender: UIGestureRecognizer,
        componentDelegate: any CVComponentDelegate,
        renderItem: CVRenderItem,
    ) -> Bool

    func handleDoubleTap(
        sender: UIGestureRecognizer,
        componentDelegate: any CVComponentDelegate,
        renderItem: CVRenderItem,
    ) -> Bool

    func findLongPressHandler(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> CVLongPressHandler?

    func findPanHandler(
        sender: UIPanGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
        messageSwipeActionState: CVMessageSwipeActionState,
    ) -> CVPanHandler?
    func startPanGesture(
        sender: UIPanGestureRecognizer,
        panHandler: CVPanHandler,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
        messageSwipeActionState: CVMessageSwipeActionState,
    )
    func handlePanGesture(
        sender: UIPanGestureRecognizer,
        panHandler: CVPanHandler,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
        messageSwipeActionState: CVMessageSwipeActionState,
    )

    func cellWillBecomeVisible(componentDelegate: CVComponentDelegate)

    func updateScrollingContent(componentView: CVComponentView)

    func contextMenuAccessoryViews(componentView: CVComponentView) -> [ContextMenuTargetedPreviewAccessory]?

    func apply(
        layoutAttributes: CVCollectionViewLayoutAttributes,
        componentView: CVComponentView,
    )
}

// MARK: -

protocol CVRootComponent: CVComponent {

    var componentState: CVComponentState { get }

    var cellReuseIdentifier: CVCellReuseIdentifier { get }

    func configureCellRootComponent(
        cellView: UIView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
        messageSwipeActionState: CVMessageSwipeActionState,
        componentView: CVComponentView,
    )

    var isDedicatedCell: Bool { get }
}

// MARK: -

protocol CVAccessibilityComponent: CVComponent {
    var accessibilityDescription: String { get }

    // TODO: We should have a getter for "accessiblity actions",
    //       presumably as [CVMessageAction].
}

// MARK: -

class CVComponentBase: NSObject, CVNode {
    let itemModel: CVItemModel

    init(itemModel: CVItemModel) {
        self.itemModel = itemModel
    }

    func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {
        return false
    }

    func canHandleDoubleTap(
        sender: UIGestureRecognizer,
        componentDelegate: any CVComponentDelegate,
        renderItem: CVRenderItem,
    ) -> Bool {
        return false
    }

    func handleDoubleTap(
        sender: UIGestureRecognizer,
        componentDelegate: any CVComponentDelegate,
        renderItem: CVRenderItem,
    ) -> Bool {
        false
    }

    func findLongPressHandler(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> CVLongPressHandler? {
        return nil
    }

    func findPanHandler(
        sender: UIPanGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
        messageSwipeActionState: CVMessageSwipeActionState,
    ) -> CVPanHandler? {
        return nil
    }

    func startPanGesture(
        sender: UIPanGestureRecognizer,
        panHandler: CVPanHandler,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
        messageSwipeActionState: CVMessageSwipeActionState,
    ) {
        owsFailDebug("No pan in progress.")
    }

    func handlePanGesture(
        sender: UIPanGestureRecognizer,
        panHandler: CVPanHandler,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
        messageSwipeActionState: CVMessageSwipeActionState,
    ) {
        owsFailDebug("No pan in progress.")
    }

    func cellWillBecomeVisible(componentDelegate: CVComponentDelegate) {
        // Do nothing.
    }

    func contextMenuAccessoryViews(componentView: CVComponentView) -> [ContextMenuTargetedPreviewAccessory]? {
        return nil
    }

    func apply(
        layoutAttributes: CVCollectionViewLayoutAttributes,
        componentView: CVComponentView,
    ) {
        // Do nothing.
    }

    var uiMode: ConversationUIMode { itemModel.itemViewState.uiMode }
    var previousUIMode: ConversationUIMode { itemModel.itemViewState.previousUIMode }
    var isShowingSelectionUI: Bool { uiMode.hasSelectionUI }
    var wasShowingSelectionUI: Bool { previousUIMode.hasSelectionUI }

    // MARK: - Root Components

    static func configureCellRootComponent(
        rootComponent: CVRootComponent,
        cellView: UIView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
    ) {
        owsAssertDebug(cellView.directionalLayoutMargins == .zero)

        rootComponent.configureForRendering(
            componentView: componentView,
            cellMeasurement: cellMeasurement,
            componentDelegate: componentDelegate,
        )

        let rootView = componentView.rootView
        if rootView.superview == nil {
            owsAssertDebug(cellView.subviews.isEmpty)

            cellView.addSubview(rootView)
            cellView.layoutMargins = .zero
            rootView.autoPinEdgesToSuperviewEdges()
        }
    }

    // MARK: -

    func wallpaperBlurView(componentView: CVComponentView) -> CVWallpaperBlurView? {
        nil
    }

    func configureWallpaperBlurView(
        wallpaperBlurView: CVWallpaperBlurView,
        componentDelegate: CVComponentDelegate,
        bubbleConfig: BubbleConfiguration,
    ) {
        Self.configureWallpaperBlurView(
            wallpaperBlurView: wallpaperBlurView,
            componentDelegate: componentDelegate,
            bubbleConfig: bubbleConfig,
        )
    }

    static func configureWallpaperBlurView(
        wallpaperBlurView: CVWallpaperBlurView,
        componentDelegate: CVComponentDelegate,
        bubbleConfig: BubbleConfiguration,
    ) {
        let wallpaperBlurProvider = componentDelegate.wallpaperBlurProvider
        owsAssertDebug(wallpaperBlurProvider != nil)
        wallpaperBlurView.configure(
            provider: wallpaperBlurProvider,
            bubbleConfig: bubbleConfig,
        )
    }

    func updateScrollingContent(componentView: CVComponentView) {
        updateWallpaperBlur(componentView: componentView)
    }

    private func updateWallpaperBlur(componentView: CVComponentView) {
        guard let wallpaperBlurView = wallpaperBlurView(componentView: componentView) else {
            return
        }
        wallpaperBlurView.updateIfNecessary()
    }

    // MARK: - CVNode

    var thread: TSThread { itemModel.thread }
    var interaction: TSInteraction { itemModel.interaction }
    var componentState: CVComponentState { itemModel.componentState }
    var itemViewState: CVItemViewState { itemModel.itemViewState }
    var messageCellType: CVMessageCellType { componentState.messageCellType }
    var conversationStyle: ConversationStyle { itemModel.conversationStyle }
    var mediaCache: CVMediaCache { itemModel.mediaCache }
    var isDarkThemeEnabled: Bool { conversationStyle.isDarkThemeEnabled }

    var isGroupThread: Bool {
        thread.isGroupThread
    }

    var isBorderless: Bool {
        componentState.isBorderlessJumbomojiMessage
            || componentState.isBorderlessBodyMediaMessage
            || componentState.isBorderlessStickerMessage
    }
}

// MARK: -

// Used for rendering some portion of an Conversation View item.
// It could be the entire item or some part thereof.
@objc
protocol CVComponentView {

    var rootView: UIView { get }

    var isDedicatedCellView: Bool { get set }

    func setIsCellVisible(_ isCellVisible: Bool)

    func reset()

    @objc
    optional func canHandleDoubleTapGesture(_ sender: UIGestureRecognizer) -> Bool

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

struct CVComponentAndView {
    let key: CVComponentKey
    let component: CVComponent
    let componentView: CVComponentView
}

// MARK: -

enum CVComponentKey: CustomStringConvertible, CaseIterable {
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
    case paymentAttachment
    case archivedPaymentAttachment
    case undownloadableAttachment
    case contactShare
    case bottomButtons
    case sendFailureBadge
    case poll
    case bottomLabel

    case systemMessage
    case dateHeader
    case unreadIndicator
    case typingIndicator
    case threadDetails
    case skippedDownloads
    case unknownThreadWarning
    case defaultDisappearingMessageTimer
    case collapseSet
    case messageRoot

    var description: String {
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
        case .paymentAttachment:
            return ".paymentAttchment"
        case .archivedPaymentAttachment:
            return ".archivedPaymentAttachment"
        case .undownloadableAttachment:
            return ".undownloadableAttachment"
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
        case .skippedDownloads:
            return ".skippedDownloads"
        case .sendFailureBadge:
            return ".sendFailureBadge"
        case .defaultDisappearingMessageTimer:
            return ".defaultDisappearingMessageTimer"
        case .collapseSet:
            return ".collapseSet"
        case .messageRoot:
            return ".messageRoot"
        case .poll:
            return ".poll"
        case .bottomLabel:
            return ".bottomLabel"
        }
    }

    var asKey: String { description }
}
