//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MessageAction: NSObject {
    @objc
    let block: (_ sender: Any?) -> Void
    let image: UIImage
    let accessibilityIdentifier: String

    public init(image: UIImage,
                accessibilityLabel: String,
                accessibilityIdentifier: String,
                block: @escaping (_ sender: Any?) -> Void) {
        self.image = image
        self.accessibilityIdentifier = accessibilityIdentifier
        self.block = block
        super.init()
        self.accessibilityLabel = accessibilityLabel
    }
}

@objc
protocol MessageActionsViewControllerDelegate: class {
    func messageActionsViewControllerRequestedDismissal(_ messageActionsViewController: MessageActionsViewController, withAction: MessageAction?)
    func messageActionsViewControllerRequestedDismissal(_ messageActionsViewController: MessageActionsViewController, withReaction: String, isRemoving: Bool)
    func messageActionsViewController(_ messageActionsViewController: MessageActionsViewController,
                                      shouldShowReactionPickerForInteraction: TSInteraction) -> Bool
}

@objc
class MessageActionsViewController: UIViewController {
    @objc
    let focusedViewItem: ConversationViewItem
    @objc
    var focusedInteraction: TSInteraction { return focusedViewItem.interaction }
    let focusedView: ConversationViewCell
    private let actionsToolbar: MessageActionsToolbar

    @objc
    let bottomBar = UIView()

    @objc
    let backdropView = UIView()

    @objc
    public weak var delegate: MessageActionsViewControllerDelegate?

    @objc
    init(focusedViewItem: ConversationViewItem, focusedView: ConversationViewCell, actions: [MessageAction]) {
        self.focusedViewItem = focusedViewItem
        self.focusedView = focusedView
        self.actionsToolbar = MessageActionsToolbar(actions: actions)

        super.init(nibName: nil, bundle: nil)

        self.actionsToolbar.actionDelegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView()

        backdropView.backgroundColor = Theme.backdropColor

        view.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()

        bottomBar.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_white
        view.addSubview(bottomBar)
        bottomBar.autoPinWidthToSuperview()

        bottomBar.addSubview(actionsToolbar)
        actionsToolbar.autoPinWidthToSuperview()
        actionsToolbar.autoPinEdge(toSuperviewEdge: .top)
        actionsToolbar.autoPinEdge(toSuperviewSafeArea: .bottom)

        backdropView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop)))
    }

    private var snapshotFocusedView: UIView?
    private func addSnapshotFocusedView() {
        snapshotFocusedView?.removeFromSuperview()
        snapshotFocusedView = nil

        guard let snapshotView = focusedView.snapshotView(afterScreenUpdates: false) else {
            return owsFailDebug("snapshotView was unexpectedly nil")
        }
        view.insertSubview(snapshotView, belowSubview: bottomBar)

        guard let focusedViewSuperview = focusedView.superview else {
            return owsFailDebug("focusedViewSuperview was unexpectedly nil")
        }

        let convertedFrame = view.convert(focusedView.frame, from: focusedViewSuperview)
        snapshotView.frame = convertedFrame
        snapshotView.isUserInteractionEnabled = false

        snapshotFocusedView = snapshotView
    }

    @objc func didTapBackdrop() {
        delegate?.messageActionsViewControllerRequestedDismissal(self, withAction: nil)
    }

    @objc(presentOnWindow:prepareConstraints:animateAlongside:completion:)
    func present(
        on window: UIWindow,
        prepareConstraints: () -> Void,
        animateAlongside: (() -> Void)?,
        completion: (() -> Void)?
    ) {
        guard view.superview == nil else {
            return owsFailDebug("trying to dismiss when already presented")
        }

        window.addSubview(view)
        prepareConstraints()

        backdropView.alpha = 0
        bottomBar.alpha = 0

        window.layoutIfNeeded()

        addSnapshotFocusedView()
        addReactionPickerIfNecessary()

        reactionPicker?.playPresentationAnimation(duration: 0.2)

        UIView.animate(withDuration: 0.2, animations: {
            self.backdropView.alpha = 1
            self.bottomBar.alpha = 1
            animateAlongside?()
        }) { _ in
            completion?()
        }
    }

    @objc(dismissAndAnimateAlongside:completion:)
    func dismiss(animateAlongside: (() -> Void)?, completion: (() -> Void)?) {
        guard view.superview != nil else {
            return owsFailDebug("trying to dismiss when not presented")
        }

        var alreadyRanCompletion = false
        let completeOnce = {
            guard !alreadyRanCompletion else { return }
            AssertIsOnMainThread()
            alreadyRanCompletion = true
            self.view.removeFromSuperview()
            completion?()
        }

        reactionPicker?.playDismissalAnimation(duration: 0.2, completion: completeOnce)

        UIView.animate(withDuration: 0.2,
                       animations: {
                        self.backdropView.alpha = 0
                        self.bottomBar.alpha = 0
                        self.snapshotFocusedView?.alpha = 0
                        animateAlongside?()
        }, completion: { _ in completeOnce() })
    }

    // MARK: - Reaction handling

    var interactionAllowsReactions: Bool {
        guard let delegate = delegate else { return false }
        return delegate.messageActionsViewController(self, shouldShowReactionPickerForInteraction: focusedInteraction)
    }

    private var reactionPicker: MessageReactionPicker?
    private func addReactionPickerIfNecessary() {
        guard interactionAllowsReactions, reactionPicker == nil else { return }

        let picker = MessageReactionPicker(selectedEmoji: focusedViewItem.reactionState?.localUserEmoji, delegate: self)
        view.addSubview(picker)

        view.setNeedsLayout()
        view.layoutIfNeeded()

        // The position of the picker is calculated relative to the
        // starting touch point of the presenting gesture.

        var pickerOrigin = initialTouchLocation.minus(CGPoint(x: picker.width() / 2, y: picker.height() / 2))

        // The picker always starts 25pts above the touch point
        pickerOrigin.y -= 25 + picker.height()

        // If the picker is not at least 16pts away from the edge
        // of the screen, we offset it so that it is.

        let edgeThresholds: UIEdgeInsets = { () -> UIEdgeInsets in
            guard #available(iOS 11, *) else { return .zero }
            return backdropView.safeAreaInsets
        }().plus(16)

        if pickerOrigin.x < backdropView.frame.origin.x + edgeThresholds.left {
            pickerOrigin.x = backdropView.frame.origin.x + edgeThresholds.left
        } else if pickerOrigin.x > backdropView.frame.maxX - edgeThresholds.right - picker.width() {
            pickerOrigin.x = backdropView.frame.maxX - edgeThresholds.right - picker.width()
        }

        if pickerOrigin.y < backdropView.frame.origin.y + edgeThresholds.top {
            pickerOrigin.y = backdropView.frame.origin.y + edgeThresholds.top
        } else if pickerOrigin.y > backdropView.frame.maxY - edgeThresholds.bottom - picker.height() {
            pickerOrigin.y = backdropView.frame.maxY - edgeThresholds.bottom - picker.height()
        }

        picker.autoPinEdge(.leading, to: .leading, of: view, withOffset: pickerOrigin.x)
        picker.autoPinEdge(.top, to: .top, of: view, withOffset: pickerOrigin.y)

        reactionPicker = picker
    }

    private lazy var initialTouchLocation = currentTouchLocation
    private var currentTouchLocation: CGPoint {
        guard let cell = focusedView as? OWSMessageCell else {
            owsFailDebug("unexpected cell type")
            return view.center
        }

        return cell.longPressGestureRecognizer.location(in: view)
    }

    private var gestureExitedDeadZone = false
    private let deadZoneRadius: CGFloat = 30

    @objc
    func didChangeLongpress() {
        // Do nothing if reactions aren't enabled.
        guard interactionAllowsReactions else { return }

        guard let reactionPicker = reactionPicker else {
            return owsFailDebug("unexpectedly missing reaction picker")
        }

        // Only start gesture based interactions once the touch
        // has moved out of the dead zone.
        if !gestureExitedDeadZone {
            let distanceFromInitialLocation = abs(hypot(
                currentTouchLocation.x - initialTouchLocation.x,
                currentTouchLocation.y - initialTouchLocation.y
            ))
            gestureExitedDeadZone = distanceFromInitialLocation >= deadZoneRadius
            if !gestureExitedDeadZone { return }
        }

        reactionPicker.updateFocusPosition(reactionPicker.convert(currentTouchLocation, from: view), animated: true)
    }

    @objc
    func didEndLongpress() {
        // If the long press never moved, do nothing when we release.
        // The menu should continue to display until the user dismisses.
        guard gestureExitedDeadZone else { return }

        // If there's not a focused reaction, dismiss the menu with no action
        guard let focusedEmoji = reactionPicker?.focusedEmoji else {
            delegate?.messageActionsViewControllerRequestedDismissal(self, withAction: nil)
            return
        }

        // Otherwise, dismiss the menu and send the focused emoji
        delegate?.messageActionsViewControllerRequestedDismissal(
            self,
            withReaction: focusedEmoji,
            isRemoving: focusedEmoji == focusedViewItem.reactionState?.localUserEmoji
        )
    }
}

extension MessageActionsViewController: MessageReactionPickerDelegate {
    func didSelectReaction(reaction: String, isRemoving: Bool) {
        delegate?.messageActionsViewControllerRequestedDismissal(self, withReaction: reaction, isRemoving: isRemoving)
    }
}

extension MessageActionsViewController: MessageActionsToolbarDelegate {
    fileprivate func messageActionsToolbar(_ messageActionsToolbar: MessageActionsToolbar, executedAction: MessageAction) {
        delegate?.messageActionsViewControllerRequestedDismissal(self, withAction: executedAction)
    }
}

private protocol MessageActionsToolbarDelegate: class {
    func messageActionsToolbar(_ messageActionsToolbar: MessageActionsToolbar, executedAction: MessageAction)
}

private class MessageActionsToolbar: UIToolbar {

    weak var actionDelegate: MessageActionsToolbarDelegate?

    let actions: [MessageAction]

    deinit {
        Logger.verbose("")
    }

    required init(actions: [MessageAction]) {
        self.actions = actions

        super.init(frame: .zero)

        isTranslucent = false
        isOpaque = true

        autoresizingMask = .flexibleHeight
        translatesAutoresizingMaskIntoConstraints = false
        barTintColor = Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_white
        setShadowImage(UIImage(), forToolbarPosition: .any)

        buildItems()
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: -

    private var itemToAction = [UIBarButtonItem: MessageAction]()
    private func buildItems() {
        var newItems = [UIBarButtonItem]()

        for action in actions {
            let actionItem = UIBarButtonItem(
                image: action.image.withRenderingMode(.alwaysTemplate),
                style: .plain,
                target: self,
                action: #selector(didTapItem(_:))
            )
            actionItem.tintColor = Theme.primaryIconColor
            actionItem.accessibilityLabel = action.accessibilityLabel
            newItems.append(actionItem)
            itemToAction[actionItem] = action

            if action != actions.last {
                newItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
            }
        }

        // If we only have a single button, center it.
        if newItems.count == 1 {
            newItems.insert(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), at: 0)
            newItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        }

        items = newItems
    }

    @objc func didTapItem(_ item: UIBarButtonItem) {
        guard let action = itemToAction[item] else {
            return owsFailDebug("missing action for item")
        }

        actionDelegate?.messageActionsToolbar(self, executedAction: action)
    }
}
