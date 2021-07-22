//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

/// UIContextMenuInteractionDelegate analog
protocol ContextMenuInteractionDelegate: AnyObject {
    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint) -> ContextMenuConfiguration?
    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: ContextMenuConfiguration) -> ContextMenuTargetedPreview?
}

/// UIContextMenuInteraction analog
class ContextMenuInteraction: NSObject, UIInteraction {

    weak var delegate: ContextMenuInteractionDelegate?
    private var contextMenuController: ContextMenuController?

    private var longPressGestureRecognizer: UIGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressRecognized(sender:)))
        recognizer.minimumPressDuration = 0.3
        return recognizer
    }()

    // MARK: UIInteraction
    public var view: UIView?

    func willMove(to view: UIView?) {
        if view != self.view {
            self.view?.removeGestureRecognizer(longPressGestureRecognizer)
        }
    }

    func didMove(to view: UIView?) {
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

        guard let contextMenuConfiguration = delegate.contextMenuInteraction(self, configurationForMenuAtLocation: locationInView) else {
            owsFailDebug("Failed to get context menu configuration from delegate")
            return
        }

        let targetedPreview = delegate.contextMenuInteraction(self, previewForHighlightingMenuWithConfiguration: contextMenuConfiguration) ?? ContextMenuTargetedPreview(view: view, accessoryViews: nil)

        for accessory in targetedPreview.accessoryViews {
            accessory.delegate = self
        }

        presentMenu(locationInView: locationInView, contextMenuConfiguration: contextMenuConfiguration, targetedPreview: targetedPreview)
    }

    public func presentMenu(locationInView: CGPoint, contextMenuConfiguration: ContextMenuConfiguration, targetedPreview: ContextMenuTargetedPreview) {
        let contextMenuController = ContextMenuController(configuration: contextMenuConfiguration, preview: targetedPreview)
        contextMenuController.delegate = self
        self.contextMenuController = contextMenuController
        ImpactHapticFeedback.impactOccured(style: .light)
        OWSWindowManager.shared.presentContextMenu(contextMenuController)
    }

    public func dismissMenu() {
        OWSWindowManager.shared.dismissContextMenu()
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
class ChatHistoryContextMenuInteraction: ContextMenuInteraction {

    public let itemViewModel: CVItemViewModelImpl
    public let messageActions: [MessageAction]

    /// Default initializer
    /// - Parameters:
    ///   - delegate: ContextMenuInteraction delegate
    ///   - itemViewModel: CVItemViewModelImpl related to context menu item
    ///   - messageActions: Message actions related to context menu item
    public init (
        delegate: ContextMenuInteractionDelegate,
        itemViewModel: CVItemViewModelImpl,
        messageActions: [MessageAction]
    ) {
        self.itemViewModel = itemViewModel
        self.messageActions = messageActions
        super.init(delegate: delegate)
    }

    public override func willMove(to view: UIView?) { }

    public override func didMove(to view: UIView?) {
        self.view = view
    }
}
