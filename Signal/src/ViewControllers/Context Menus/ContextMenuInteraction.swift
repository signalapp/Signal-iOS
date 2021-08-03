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
                                willDisplayMenuForConfiguration: ContextMenuConfiguration)
    func contextMenuInteraction(_ interaction: ContextMenuInteraction,
                                willEndForConfiguration: ContextMenuConfiguration)

}

/// UIContextMenuInteraction analog
public class ContextMenuInteraction: NSObject, UIInteraction {

    weak var delegate: ContextMenuInteractionDelegate?
    fileprivate var contextMenuController: ContextMenuController?

    private let sourceViewBounceDuration = 0.2
    fileprivate var gestureEligibleForMenuPresentation: Bool {
        didSet {
            if !gestureEligibleForMenuPresentation {
                // Animate back out
                UIView.animate(
                    withDuration: sourceViewBounceDuration,
                    delay: 0,
                    options: [.curveEaseInOut, .beginFromCurrentState],
                    animations: {
                        self.targetedPreview?.view?.transform = CGAffineTransform.identity
                    },
                    completion: nil
                )
            }
        }
    }
    fileprivate var locationInView = CGPoint.zero
    fileprivate var configuration: ContextMenuConfiguration?
    fileprivate var targetedPreview: ContextMenuTargetedPreview?

    private var longPressGestureRecognizer: UIGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressRecognized(sender:)))
        recognizer.minimumPressDuration = 0.1
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
        gestureEligibleForMenuPresentation = false
        super.init()
    }

    public func initiateContextMenuGesture(locationInView: CGPoint) {
        self.locationInView = locationInView
        gestureEligibleForMenuPresentation = true

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

        configuration = contextMenuConfiguration

        let targetedPreview = delegate.contextMenuInteraction(self, previewForHighlightingMenuWithConfiguration: contextMenuConfiguration) ?? ContextMenuTargetedPreview(view: view, alignment: .center, accessoryViews: nil)

        for accessory in targetedPreview.accessoryViews {
            accessory.delegate = self
        }

        self.targetedPreview = targetedPreview

        UIView.animate(
            withDuration: sourceViewBounceDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                targetedPreview.view?.transform = .scale(0.95)
            },
            completion: { finished in
                let shouldPresent = finished && self.gestureEligibleForMenuPresentation

                if shouldPresent {
                    self.presentMenu(locationInView: self.locationInView)
                    // Animate back out
                    self.gestureEligibleForMenuPresentation = false
                }
            }
        )

    }

    public func presentMenu(locationInView: CGPoint) {
        guard let view = self.view else {
            owsFailDebug("Missing view")
            return
        }

        guard let window = view.window else {
            owsFailDebug("View must be in a window!")
            return
        }

        guard let configuration = self.configuration else {
            owsFailDebug("Missing context menu configuration")
            return
        }

        guard let targetedPreview = self.targetedPreview else {
            owsFailDebug("Missing targeted preview")
            return
        }

        presentMenu(window: window, contextMenuConfiguration: configuration, targetedPreview: targetedPreview)
    }

    public func presentMenu(window: UIWindow, contextMenuConfiguration: ContextMenuConfiguration, targetedPreview: ContextMenuTargetedPreview) {
        delegate?.contextMenuInteraction(self, willDisplayMenuForConfiguration: contextMenuConfiguration)
        ImpactHapticFeedback.impactOccured(style: .medium, intensity: 0.8)

        let menuAccessory = menuAccessory(configuration: contextMenuConfiguration)
        let contextMenuController = ContextMenuController(configuration: contextMenuConfiguration, preview: targetedPreview, initiatingGestureRecognizer: initiatingGestureRecognizer(), menuAccessory: menuAccessory)
        contextMenuController.delegate = self
        self.contextMenuController = contextMenuController

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

    public func dismissMenu(animated: Bool, completion: @escaping() -> Void ) {
        if let configuarion = self.configuration {
            delegate?.contextMenuInteraction(self, willEndForConfiguration: configuarion)
        }

        if animated {
            contextMenuController?.animateOut({
                completion()
                self.contextMenuController?.view.removeFromSuperview()
                self.contextMenuController = nil
            })
        } else {
            targetedPreview?.view?.isHidden = false
            completion()
            self.contextMenuController?.view.removeFromSuperview()
            self.contextMenuController = nil
        }
    }

    // MARK: Private

    @objc
    private func longPressRecognized(sender: UIGestureRecognizer) {
        let locationInView = sender.location(in: self.view)
        switch sender.state {
        case .began:
            initiateContextMenuGesture(locationInView: locationInView)
        case .ended, .cancelled:
            gestureEligibleForMenuPresentation = false
        default:
            break
        }
        presentMenu(locationInView: locationInView)
    }
}

extension ContextMenuInteraction: ContextMenuControllerDelegate, ContextMenuTargetedPreviewAccessoryInteractionDelegate {

    func contextMenuTargetedPreviewAccessoryRequestsDismissal(_ accessory: ContextMenuTargetedPreviewAccessory, completion: @escaping () -> Void) {
        dismissMenu(animated: true, completion: completion)
    }

    func contextMenuTargetedPreviewAccessoryPreviewAlignment(_ accessory: ContextMenuTargetedPreviewAccessory) -> ContextMenuTargetedPreview.Alignment {
        return contextMenuController?.contextMenuPreview.alignment ?? .center
    }

    func contextMenuControllerRequestsDismissal(_ contextMenuController: ContextMenuController) {
        dismissMenu(animated: true, completion: { })
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
    public var contextMenuVisible: Bool {
        return contextMenuController != nil
    }

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
        gestureEligibleForMenuPresentation = false

        if contextMenuController == nil, let configuarion = self.configuration {
            delegate?.contextMenuInteraction(self, willEndForConfiguration: configuarion)
        }

        contextMenuController?.gestureDidEnd()
    }

    public override func initiatingGestureRecognizer() -> UIGestureRecognizer? {
        return chatHistoryLongPressGesture
    }

    public override func menuAccessory(configuration: ContextMenuConfiguration) -> ContextMenuActionsAccessory {
        let menu = configuration.actionProvider?([]) ?? ContextMenu([])
        let isIncomingMessage = itemViewModel.interaction.interactionType() == .incomingMessage
        let isMessageType = itemViewModel.interaction.interactionType() == .outgoingMessage || isIncomingMessage
        let alignment = ContextMenuTargetedPreviewAccessory.AccessoryAlignment(alignments: [(.bottom, .exterior), (isIncomingMessage ? .leading : .trailing, .interior)], alignmentOffset: CGPoint(x: 0, y: 12))
        let accessory = ContextMenuActionsAccessory(menu: menu, accessoryAlignment: alignment)
        let landscapeAlignmentOffset = isMessageType ? CGPoint(x: isIncomingMessage ? 12 : -12, y: 0) : alignment.alignmentOffset
        accessory.landscapeAccessoryAlignment = ContextMenuTargetedPreviewAccessory.AccessoryAlignment(alignments: [isMessageType ? (.top, .interior) : (.bottom, .exterior), (isIncomingMessage ? .trailing : .leading, .exterior)], alignmentOffset: landscapeAlignmentOffset)
        accessory.delegate = self
        return accessory
    }
}
