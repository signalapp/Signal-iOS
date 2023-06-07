//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

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
    func contextMenuInteraction(_ interaction: ContextMenuInteraction,
                                didEndForConfiguration: ContextMenuConfiguration)

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
                        self.targetedPreview?.view.transform = CGAffineTransform.identity
                    },
                    completion: nil
                )
            }
        }
    }
    fileprivate var locationInView = CGPoint.zero
    fileprivate var configuration: ContextMenuConfiguration?
    fileprivate var targetedPreview: ContextMenuTargetedPreview?

    private lazy var longPressGestureRecognizer: UIGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressRecognized(sender:)))
        recognizer.minimumPressDuration = 0.2
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

    public func initiateContextMenuGesture(locationInView: CGPoint, presentImmediately: Bool) {
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
            return
        }

        configuration = contextMenuConfiguration

        guard let targetedPreview = delegate.contextMenuInteraction(self, previewForHighlightingMenuWithConfiguration: contextMenuConfiguration) ?? ContextMenuTargetedPreview(view: view, alignment: .center, accessoryViews: nil) else { return }

        for accessory in targetedPreview.accessoryViews {
            accessory.delegate = self
        }

        self.targetedPreview = targetedPreview

        if presentImmediately {
            self.presentMenu(locationInView: self.locationInView, presentImmediately: true)
        } else {
            UIView.animate(
                withDuration: sourceViewBounceDuration,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: {
                    targetedPreview.view.transform = .scale(0.95)
                },
                completion: { finished in
                    let shouldPresent = finished && self.gestureEligibleForMenuPresentation

                    if shouldPresent {
                        self.presentMenu(locationInView: self.locationInView, presentImmediately: false)
                        // Animate back out
                        self.gestureEligibleForMenuPresentation = false
                    }
                }
            )
        }
    }

    public func presentMenu(locationInView: CGPoint, presentImmediately: Bool) {
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

        presentMenu(window: window, contextMenuConfiguration: configuration, targetedPreview: targetedPreview, presentImmediately: presentImmediately)
    }

    public func presentMenu(window: UIWindow, contextMenuConfiguration: ContextMenuConfiguration, targetedPreview: ContextMenuTargetedPreview, presentImmediately: Bool) {

        let menuAccessory = menuAccessory(configuration: contextMenuConfiguration, targetedPreview: targetedPreview)
        let contextMenuController = ContextMenuController(configuration: contextMenuConfiguration, preview: targetedPreview, initiatingGestureRecognizer: initiatingGestureRecognizer(), menuAccessory: menuAccessory, presentImmediately: presentImmediately)
        contextMenuController.delegate = self
        self.contextMenuController = contextMenuController

        delegate?.contextMenuInteraction(self, willDisplayMenuForConfiguration: contextMenuConfiguration)
        ImpactHapticFeedback.impactOccurred(style: .medium, intensity: 0.8)

        window.addSubview(contextMenuController.view)
        contextMenuController.view.frame = window.bounds
    }

    public func initiatingGestureRecognizer() -> UIGestureRecognizer? {
        return longPressGestureRecognizer
    }

    public func menuAccessory(configuration: ContextMenuConfiguration, targetedPreview: ContextMenuTargetedPreview) -> ContextMenuActionsAccessory {

        var alignments: [(ContextMenuTargetedPreviewAccessory.AccessoryAlignment.Edge, ContextMenuTargetedPreviewAccessory.AccessoryAlignment.Origin)] = [(.bottom, .exterior)]

        switch targetedPreview.alignment {
        case .left:
            alignments.append((CurrentAppContext().isRTL ? .trailing : .leading, .interior))
        case .right:
            alignments.append((CurrentAppContext().isRTL ? .leading : .trailing, .interior))
        case .center:
            break
        }

        let menu = configuration.actionProvider?([]) ?? ContextMenu([])
        let alignment = ContextMenuTargetedPreviewAccessory.AccessoryAlignment(alignments: alignments, alignmentOffset: targetedPreview.alignmentOffset ?? CGPoint(x: 0, y: 12))
        let accessory = ContextMenuActionsAccessory(menu: menu, accessoryAlignment: alignment, forceDarkTheme: configuration.forceDarkTheme)
        accessory.delegate = self
        return accessory
    }

    public func dismissMenu(animated: Bool, completion: @escaping() -> Void ) {
        guard let configuration = self.configuration else {
            return
        }

        delegate?.contextMenuInteraction(self, willEndForConfiguration: configuration)

        if animated {
            contextMenuController?.animateOut({
                completion()
                self.delegate?.contextMenuInteraction(self, didEndForConfiguration: configuration)
                self.contextMenuController?.view.removeFromSuperview()
                self.contextMenuController = nil
            })
        } else {
            targetedPreview?.view.isHidden = false
            targetedPreview?.auxiliaryView?.isHidden = false
            delegate?.contextMenuInteraction(self, didEndForConfiguration: configuration)
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
            initiateContextMenuGesture(locationInView: locationInView, presentImmediately: false)
        case .changed:
            contextMenuController?.gestureDidChange()
        case .ended, .cancelled:
            contextMenuController?.gestureDidEnd()
            gestureEligibleForMenuPresentation = false
        default:
            break
        }
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

    func contextMenuControllerAccessoryFrameOffset(_ contextMenuController: ContextMenuController) -> CGPoint? {
        nil
    }

    func contextMenuTargetedPreviewAccessoryRequestsEmojiPicker(
        for message: TSMessage,
        accessory: ContextMenuTargetedPreviewAccessory,
        completion: @escaping (String) -> Void
    ) {
        contextMenuController?.showEmojiSheet(message: message, completion: { emojiString in
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
    public let keyboardWasActive: Bool
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
        initiatingGestureRecognizer: UIGestureRecognizer?,
        keyboardWasActive: Bool
    ) {
        self.itemViewModel = itemViewModel
        self.thread = thread
        self.messageActions = messageActions
        self.keyboardWasActive = keyboardWasActive
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

        if contextMenuController == nil {
            cancelPresentationGesture()
        } else {
            contextMenuController?.gestureDidEnd()
        }

    }

    public func cancelPresentationGesture() {
        gestureEligibleForMenuPresentation = false

        if contextMenuController == nil, let configuration = self.configuration {
            delegate?.contextMenuInteraction(self, willEndForConfiguration: configuration)
            delegate?.contextMenuInteraction(self, didEndForConfiguration: configuration)
        }
    }

    public override func initiatingGestureRecognizer() -> UIGestureRecognizer? {
        return chatHistoryLongPressGesture
    }

    public override func menuAccessory(configuration: ContextMenuConfiguration, targetedPreview: ContextMenuTargetedPreview) -> ContextMenuActionsAccessory {
        let isRTL = CurrentAppContext().isRTL
        let menu = configuration.actionProvider?([]) ?? ContextMenu([])
        let isIncomingMessage = itemViewModel.interaction.interactionType == .incomingMessage
        let isMessageType = itemViewModel.interaction.interactionType == .outgoingMessage || isIncomingMessage
        let horizontalEdgeAlignment: ContextMenuTargetedPreviewAccessory.AccessoryAlignment.Edge = isIncomingMessage ? (isRTL ? .trailing : .leading) : (isRTL ? .leading : .trailing)
        let alignment = ContextMenuTargetedPreviewAccessory.AccessoryAlignment(alignments: [(.bottom, .exterior), (horizontalEdgeAlignment, .interior)], alignmentOffset: CGPoint(x: 0, y: 12))
        let accessory = ContextMenuActionsAccessory(menu: menu, accessoryAlignment: alignment)
        let landscapeAlignmentOffset = isMessageType ? CGPoint(x: isIncomingMessage ? (isRTL ? -12 : 12) : (isRTL ? 12 : -12), y: 0) : alignment.alignmentOffset
        let horizontalLandscapeEdgeAlignment: ContextMenuTargetedPreviewAccessory.AccessoryAlignment.Edge = isIncomingMessage ? (isRTL ? .leading : .trailing) : (isRTL ? .trailing : .leading)
        accessory.landscapeAccessoryAlignment = ContextMenuTargetedPreviewAccessory.AccessoryAlignment(alignments: [isMessageType ? (.top, .interior) : (.bottom, .exterior), (horizontalLandscapeEdgeAlignment, .exterior)], alignmentOffset: landscapeAlignmentOffset)
        accessory.delegate = self
        return accessory
    }
}
