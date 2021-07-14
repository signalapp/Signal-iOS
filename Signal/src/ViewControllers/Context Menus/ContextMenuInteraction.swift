//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol ContextMenuInteractionDelegate: AnyObject {
    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint) -> ContextMenuConfiguration?
    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: ContextMenuConfiguration) -> ContextMenuTargetedPreview?
}

class ContextMenuInteraction: NSObject, UIInteraction {
    weak var delegate: ContextMenuInteractionDelegate?

    private var longPressGestureRecognizer: UIGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressRecognized(sender:)))
        recognizer.minimumPressDuration = 0.3
        return recognizer
    }()

    private var contextMenuController: ContextMenuController?

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

    public init(delegate: ContextMenuInteractionDelegate) {
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

        presentMenu(locationInView: locationInView, contextMenuConfiguration: contextMenuConfiguration, targetedPreview: targetedPreview)
    }

    public func presentMenu(locationInView: CGPoint, contextMenuConfiguration: ContextMenuConfiguration, targetedPreview: ContextMenuTargetedPreview) {
        let contextMenuController = ContextMenuController(configuration: contextMenuConfiguration, preview: targetedPreview)
        contextMenuController.delegate = self
        self.contextMenuController = contextMenuController
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

extension ContextMenuInteraction: ContextMenuControllerDelegate {

    func contextMenuControllerRequestsDismissal(_ contextMenuController: ContextMenuController) {
        dismissMenu()
    }

}

protocol TranscriptContextMenuInteractionDelegate: AnyObject {
    func contextMenuInteraction(
        _ interaction: TranscriptContextMenuInteraction,
        accessoryViewsForContextMenuWIthWithConfiguration configuration: ContextMenuConfiguration) -> [ContextMenuTargetedPreview.ContextMenuTargetedPreviewAccessory]?
}

// Custom subclass for transcript CVC interactions
class TranscriptContextMenuInteraction: ContextMenuInteraction {
    weak var transcriptDelegate: TranscriptContextMenuInteractionDelegate?

    public let itemViewModel: CVItemViewModelImpl
    public let messageActions: [MessageAction]

    public init(delegate: ContextMenuInteractionDelegate, itemViewModel: CVItemViewModelImpl, messageActions: [MessageAction]) {
        self.itemViewModel = itemViewModel
        self.messageActions = messageActions
        super.init(delegate: delegate)
    }

    public override func willMove(to view: UIView?) { }

    public override func didMove(to view: UIView?) {
        self.view = view
    }

    public override func presentMenu(locationInView: CGPoint) {

        guard let view = self.view else {
            owsFailDebug("Missing view")
            return
        }

        let configuration = ContextMenuConfiguration(identifier: nil, actionProvider: nil)

        let accessoryViews: [ContextMenuTargetedPreview.ContextMenuTargetedPreviewAccessory]?
        if let delegate = self.transcriptDelegate {
            accessoryViews = delegate.contextMenuInteraction(self, accessoryViewsForContextMenuWIthWithConfiguration: configuration)
        } else {
            accessoryViews = nil
        }

        let targetedPreview = ContextMenuTargetedPreview(view: view, accessoryViews: accessoryViews)

        presentMenu(locationInView: locationInView, contextMenuConfiguration: configuration, targetedPreview: targetedPreview)
    }
}
