//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

/// UIContextMenuInteractionDelegate analog
public protocol ContextMenuInteractionDelegate: AnyObject {
    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint) -> ContextMenuConfiguration?
    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: ContextMenuConfiguration) -> ContextMenuTargetedPreview?
    func contextMenuInteraction(_ interaction: ContextMenuInteraction,
                                willEndForConfiguration: ContextMenuConfiguration)

}

/// UIContextMenuInteraction analog
public class ContextMenuInteraction: NSObject, UIInteraction {

    weak var delegate: ContextMenuInteractionDelegate?
    fileprivate var contextMenuController: ContextMenuController?
    var configuration: ContextMenuConfiguration?

    private var longPressGestureRecognizer: UIGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressRecognized(sender:)))
        recognizer.minimumPressDuration = 0.3
        return recognizer
    }()

    // MARK: UIInteraction
    public var view: UIView?

    public func willMove(to view: UIView?) {
        if view != self.view {
            self.view?.removeGestureRecognizer(longPressGestureRecognizer)
        }
    }

    public func didMove(to view: UIView?) {
        if view != self.view {
            self.view = view
            self.view?.addGestureRecognizer(longPressGestureRecognizer)
        }
    }

    public init(
        delegate: ContextMenuInteractionDelegate
    ) {
        self.delegate = delegate
        super.init()
    }

    public func presentMenu(locationInView: CGPoint) {

        guard let delegate = self.delegate else {
            owsFailDebug("Missing ContextMenuInteractionDelegate")
            return
        }

        guard let view = self.view else {
            owsFailDebug("Missing view")
            return
        }

        guard let window = view.window else {
            owsFailDebug("View must be in a window!")
            return
        }

        guard let contextMenuConfiguration = delegate.contextMenuInteraction(self, configurationForMenuAtLocation: locationInView) else {
            owsFailDebug("Failed to get context menu configuration from delegate")
            return
        }

        configuration = contextMenuConfiguration

        let targetedPreview = delegate.contextMenuInteraction(self, previewForHighlightingMenuWithConfiguration: contextMenuConfiguration) ?? ContextMenuTargetedPreview(view: view, accessoryViews: nil)

        for accessory in targetedPreview.accessoryViews {
            accessory.delegate = self
        }

        presentMenu(window: window, contextMenuConfiguration: contextMenuConfiguration, targetedPreview: targetedPreview)
    }

    public func presentMenu(window: UIWindow, contextMenuConfiguration: ContextMenuConfiguration, targetedPreview: ContextMenuTargetedPreview) {
        let menuAccessory = menuAccessory(configuration: contextMenuConfiguration)
        let contextMenuController = ContextMenuController(configuration: contextMenuConfiguration, preview: targetedPreview, initiatingGestureRecognizer: initiatingGestureRecognizer(), menuAccessory: menuAccessory)
        contextMenuController.delegate = self
        self.contextMenuController = contextMenuController
        ImpactHapticFeedback.impactOccured(style: .medium)

        window.addSubview(contextMenuController.view)
        contextMenuController.view.frame = window.bounds
    }

    public func initiatingGestureRecognizer() -> UIGestureRecognizer? {
        return longPressGestureRecognizer
    }

    public func menuAccessory(configuration: ContextMenuConfiguration) -> ContextMenuActionsAccessory {
        let menu = configuration.actionProvider?([]) ?? ContextMenu([])
        let alignment = ContextMenuTargetedPreviewAccessory.AccessoryAlignment(alignments: [(.bottom, .exterior)], alignmentOffset: CGPoint(x: 0, y: 12))
        let accessory = ContextMenuActionsAccessory(menu: menu, accessoryAlignment: alignment)
        accessory.delegate = self
        return accessory
    }

    public func dismissMenu() {
        if let configuarion = self.configuration {
            delegate?.contextMenuInteraction(self, willEndForConfiguration: configuarion)
        }

        contextMenuController?.view.removeFromSuperview()
        contextMenuController = nil
    }

    // MARK: Private

    @objc
    private func longPressRecognized(sender: UIGestureRecognizer) {
        let locationInView = sender.location(in: self.view)
        presentMenu(locationInView: locationInView)
    }
}

extension ContextMenuInteraction: ContextMenuControllerDelegate, ContextMenuTargetedPreviewAccessoryInteractionDelegate {

    func contextMenuTargetedPreviewAccessoryRequestsDismissal(_ accessory: ContextMenuTargetedPreviewAccessory) {
        dismissMenu()
    }

    func contextMenuControllerRequestsDismissal(_ contextMenuController: ContextMenuController) {
        dismissMenu()
    }

    func contextMenuTargetedPreviewAccessoryRequestsEmojiPicker(
        _ accessory: ContextMenuTargetedPreviewAccessory,
        completion: @escaping (String) -> Void
    ) {
        contextMenuController?.showEmojiSheet(completion: { emojiString in
            self.contextMenuController?.dismissEmojiSheet(animated: true, completion: {
                completion(emojiString)
            })
        })
    }

}

// Custom subclass for chat history CVC interactions
public class ChatHistoryContextMenuInteraction: ContextMenuInteraction {

    public let itemViewModel: CVItemViewModelImpl
    public let thread: TSThread
    public let messageActions: [MessageAction]
    public let chatHistoryLongPressGesture: UIGestureRecognizer?

    /// Default initializer
    /// - Parameters:
    ///   - delegate: ContextMenuInteraction delegate
    ///   - itemViewModel: CVItemViewModelImpl related to context menu item
    ///   - messageActions: Message actions related to context menu item
    public init (
        delegate: ContextMenuInteractionDelegate,
        itemViewModel: CVItemViewModelImpl,
        thread: TSThread,
        messageActions: [MessageAction],
        initiatingGestureRecognizer: UIGestureRecognizer?
    ) {
        self.itemViewModel = itemViewModel
        self.thread = thread
        self.messageActions = messageActions
        self.chatHistoryLongPressGesture = initiatingGestureRecognizer
        super.init(delegate: delegate)
    }

    public override func willMove(to view: UIView?) { }

    public override func didMove(to view: UIView?) {
        self.view = view
    }

    public func initiatingGestureRecognizerDidChange() {
        contextMenuController?.gestureDidChange()
    }

    public func initiatingGestureRecognizerDidEnd() {
        contextMenuController?.gestureDidEnd()
    }

    public override func initiatingGestureRecognizer() -> UIGestureRecognizer? {
        return chatHistoryLongPressGesture
    }

    public override func menuAccessory(configuration: ContextMenuConfiguration) -> ContextMenuActionsAccessory {
        let menu = configuration.actionProvider?([]) ?? ContextMenu([])
        let isIncomingMessage = itemViewModel.interaction.interactionType() == .incomingMessage
        let alignment = ContextMenuTargetedPreviewAccessory.AccessoryAlignment(alignments: [(.bottom, .exterior), (isIncomingMessage ? .leading : .trailing, .interior)], alignmentOffset: CGPoint(x: 0, y: 12))
        let accessory = ContextMenuActionsAccessory(menu: menu, accessoryAlignment: alignment)
        accessory.delegate = self
        return accessory
    }
}
