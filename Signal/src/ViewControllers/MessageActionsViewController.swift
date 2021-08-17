//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MessageAction: NSObject {
    @objc
    let block: (_ sender: Any?) -> Void
    let accessibilityIdentifier: String
    let contextMenuTitle: String
    let contextMenuAttributes: ContextMenuAction.Attributes

    public enum MessageActionType {
        case reply
        case copy
        case info
        case delete
        case share
        case forward
        case select
    }

    let actionType: MessageActionType

    public init(_ actionType: MessageActionType,
                accessibilityLabel: String,
                accessibilityIdentifier: String,
                contextMenuTitle: String,
                contextMenuAttributes: ContextMenuAction.Attributes,
                block: @escaping (_ sender: Any?) -> Void) {
        self.actionType = actionType
        self.accessibilityIdentifier = accessibilityIdentifier
        self.contextMenuTitle = contextMenuTitle
        self.contextMenuAttributes = contextMenuAttributes
        self.block = block
        super.init()
        self.accessibilityLabel = accessibilityLabel
    }

    var image: UIImage {
        switch actionType {
        case .reply:
            return Theme.iconImage(.messageActionReply)
        case .copy:
            return Theme.iconImage(.messageActionCopy)
        case .info:
            if FeatureFlags.contextMenus {
                return Theme.iconImage(.contextMenuInfo)
            } else {
                return Theme.iconImage(.info)
            }
        case .delete:
            return Theme.iconImage(.messageActionDelete)
        case .share:
            return Theme.iconImage(.messageActionShare)
        case .forward:
            return Theme.iconImage(.messageActionForward)
        case .select:
            if FeatureFlags.contextMenus {
                return Theme.iconImage(.contextMenuSelect)
            } else {
                return Theme.iconImage(.messageActionSelect)
            }
        }
    }
}

@objc
public protocol MessageActionsViewControllerDelegate: AnyObject {
    func messageActionsViewControllerRequestedDismissal(_ messageActionsViewController: MessageActionsViewController, withAction: MessageAction?)
    func messageActionsViewControllerRequestedDismissal(_ messageActionsViewController: MessageActionsViewController, withReaction: String, isRemoving: Bool)
    func messageActionsViewController(_ messageActionsViewController: MessageActionsViewController,
                                      shouldShowReactionPickerForInteraction: TSInteraction) -> Bool
    func messageActionsViewControllerRequestedKeyboardDismissal(_ messageActionsViewController: MessageActionsViewController, focusedView: UIView)
    func messageActionsViewControllerLongPressGestureRecognizer(_ messageActionsViewController: MessageActionsViewController) -> UILongPressGestureRecognizer
}

@objc
public class MessageActionsViewController: UIViewController {

    private let itemViewModel: CVItemViewModelImpl
    @objc
    public var focusedInteraction: TSInteraction { itemViewModel.interaction }
    var thread: TSThread { itemViewModel.thread }
    public var reactionState: InteractionReactionState? { itemViewModel.reactionState }

    let focusedView: UIView
    private let actionsToolbar: MessageActionsToolbar

    @objc
    let bottomBar = UIView()

    @objc
    let backdropView = UIView()

    @objc
    public weak var delegate: MessageActionsViewControllerDelegate?

    @objc
    init(itemViewModel: CVItemViewModelImpl, focusedView: UIView, actions: [MessageAction]) {
        self.itemViewModel = itemViewModel
        self.focusedView = focusedView

        let toolbarMode = MessageActionsToolbar.Mode.normal(messagesActions: actions)
        self.actionsToolbar = MessageActionsToolbar(mode: toolbarMode)

        super.init(nibName: nil, bundle: nil)

        self.actionsToolbar.actionDelegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameWillChange), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
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

        guard let snapshotView = focusedView.snapshotView(afterScreenUpdates: true) else {
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

    func updateSnapshotPosition() {
        guard let snapshotFocusedView = snapshotFocusedView else { return }

        guard let focusedViewSuperview = focusedView.superview else {
            return owsFailDebug("focusedViewSuperview was unexpectedly nil")
        }

        let convertedFrame = view.convert(focusedView.frame, from: focusedViewSuperview)
        snapshotFocusedView.frame = convertedFrame
    }

    @objc func keyboardFrameWillChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
            let rawAnimationCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
            let animationCurve = UIView.AnimationCurve(rawValue: rawAnimationCurve) else {
                return owsFailDebug("keyboard notification missing expected userInfo properties")
        }

        // If the keyboard frame changes (likely due to a first responder change)
        // we need to make sure the snapshot of the latest message updates its
        // position and stays on top of the original message. We want this to
        // animate alongside the keyboard animation, so we use old-school UIView
        // animation route in order to set the appropriate curve.
        UIView.beginAnimations("messageActionKeyboardStateChange", context: nil)
        UIView.setAnimationBeginsFromCurrentState(true)
        UIView.setAnimationCurve(animationCurve)
        UIView.setAnimationDuration(animationDuration)
        updateSnapshotPosition()
        UIView.commitAnimations()
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

        ImpactHapticFeedback.impactOccured(style: .light)

        window.addSubview(view)
        prepareConstraints()

        backdropView.alpha = 0
        bottomBar.alpha = 0

        window.layoutIfNeeded()

        addSnapshotFocusedView()
        addReactionPickerIfNecessary()

        quickReactionPicker?.playPresentationAnimation(duration: 0.2)

        UIView.animate(withDuration: 0.2, animations: {
            self.backdropView.alpha = 1
            self.bottomBar.alpha = 1
            animateAlongside?()
        }) { _ in
            completion?()
        }
    }

    @objc
    func dismissWithoutAnimating() {
        AssertIsOnMainThread()

        guard view.superview != nil else {
            return owsFailDebug("trying to dismiss when not presented")
        }

        view.removeFromSuperview()
        anyReactionPicker?.dismiss(animated: false)
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

        anyReactionPicker?.dismiss(animated: true, completion: completeOnce)
        quickReactionPicker?.playDismissalAnimation(duration: 0.2, completion: completeOnce)

        UIView.animate(withDuration: 0.2,
                       animations: {
                        self.backdropView.alpha = 0
                        self.bottomBar.alpha = 0
                        self.snapshotFocusedView?.alpha = 0
                        animateAlongside?()
        }, completion: { _ in completeOnce() })
    }

    // MARK: - Reaction handling

    var canAddReact: Bool {
        guard thread.canSendReactionToThread else { return false }
        guard let delegate = delegate else { return false }
        return delegate.messageActionsViewController(self, shouldShowReactionPickerForInteraction: focusedInteraction)
    }

    private var quickReactionPicker: MessageReactionPicker?
    private func addReactionPickerIfNecessary() {
        guard canAddReact, quickReactionPicker == nil else { return }

        let picker = MessageReactionPicker(selectedEmoji: reactionState?.localUserEmoji, delegate: self)
        view.addSubview(picker)

        view.setNeedsLayout()
        view.layoutIfNeeded()

        // The position of the picker is calculated relative to the
        // starting touch point of the presenting gesture.

        var pickerOrigin = initialTouchLocation.minus(CGPoint(x: picker.width / 2, y: picker.height / 2))

        // The picker always starts 25pts above the touch point
        pickerOrigin.y -= 25 + picker.height

        // If the picker is not at least 16pts away from the edge
        // of the screen, we offset it so that it is.

        let edgeThresholds = backdropView.safeAreaInsets.plus(16)

        if pickerOrigin.x < backdropView.frame.origin.x + edgeThresholds.left {
            pickerOrigin.x = backdropView.frame.origin.x + edgeThresholds.left
        } else if pickerOrigin.x > backdropView.frame.maxX - edgeThresholds.right - picker.width {
            pickerOrigin.x = backdropView.frame.maxX - edgeThresholds.right - picker.width
        }

        if pickerOrigin.y < backdropView.frame.origin.y + edgeThresholds.top {
            pickerOrigin.y = backdropView.frame.origin.y + edgeThresholds.top
        } else if pickerOrigin.y > backdropView.frame.maxY - edgeThresholds.bottom - picker.height {
            pickerOrigin.y = backdropView.frame.maxY - edgeThresholds.bottom - picker.height
        }

        picker.autoPinEdge(.leading, to: .leading, of: view, withOffset: pickerOrigin.x)
        picker.autoPinEdge(.top, to: .top, of: view, withOffset: pickerOrigin.y)

        quickReactionPicker = picker
    }

    private lazy var initialTouchLocation = currentTouchLocation
    private var currentTouchLocation: CGPoint {
        guard let delegate = delegate else {
            owsFailDebug("unexpectedly missing delegate")
            return view.center
        }

        return delegate.messageActionsViewControllerLongPressGestureRecognizer(self).location(in: view)
    }

    private var gestureExitedDeadZone = false
    private let deadZoneRadius: CGFloat = 30

    @objc
    func didChangeLongpress() {
        // Do nothing if reactions aren't enabled.
        guard canAddReact else { return }

        guard let reactionPicker = quickReactionPicker else {
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
        guard let focusedEmoji = quickReactionPicker?.focusedEmoji else {
            delegate?.messageActionsViewControllerRequestedDismissal(self, withAction: nil)
            return
        }

        if focusedEmoji == MessageReactionPicker.anyEmojiName {
            showAnyEmojiPicker()
        } else {
            // Otherwise, dismiss the menu and send the focused emoji
            delegate?.messageActionsViewControllerRequestedDismissal(
                self,
                withReaction: focusedEmoji,
                isRemoving: focusedEmoji == reactionState?.localUserEmoji
            )
        }
    }

    private var anyReactionPicker: EmojiPickerSheet?
    func showAnyEmojiPicker() {
        let picker = EmojiPickerSheet { [weak self] emoji in
            guard let self = self else { return }

            guard let emojiString = emoji?.rawValue else {
                self.delegate?.messageActionsViewControllerRequestedDismissal(self, withAction: nil)
                return
            }

            self.delegate?.messageActionsViewControllerRequestedDismissal(
                self,
                withReaction: emojiString,
                isRemoving: emojiString == self.reactionState?.localUserEmoji
            )
        }
        picker.externalBackdropView = backdropView
        anyReactionPicker = picker

        // Presenting the emoji picker causes the conversation view controller
        // to lose first responder status. This is expected. Unfortunately, to
        // do a bug with window wrangling it doesn't properly become first responder
        // again when all is done. Instead, we get into a broken state half way
        // between the keyboad being presented and not. This results in the user
        // being unable to send messages. In order to work around this, we notify
        // the CVC we're going to present so it can manually resign first responder
        // status ahead of time. This allows the user to return to a good state
        // after posting a custom reaction.
        delegate?.messageActionsViewControllerRequestedKeyboardDismissal(self, focusedView: focusedView)

        present(picker, animated: true)
        quickReactionPicker?.playDismissalAnimation(duration: 0.2) {
            self.quickReactionPicker?.removeFromSuperview()
            self.quickReactionPicker = nil
            self.bottomBar.alpha = 0
        }
    }
}

extension MessageActionsViewController: MessageReactionPickerDelegate {
    func didSelectReaction(reaction: String, isRemoving: Bool) {
        delegate?.messageActionsViewControllerRequestedDismissal(self, withReaction: reaction, isRemoving: isRemoving)
    }

    func didSelectAnyEmoji() {
        showAnyEmojiPicker()
    }
}

extension MessageActionsViewController: MessageActionsToolbarDelegate {
    public func messageActionsToolbar(_ messageActionsToolbar: MessageActionsToolbar, executedAction: MessageAction) {
        delegate?.messageActionsViewControllerRequestedDismissal(self, withAction: executedAction)
    }
}

public protocol MessageActionsToolbarDelegate: AnyObject {
    func messageActionsToolbar(_ messageActionsToolbar: MessageActionsToolbar, executedAction: MessageAction)
}

public class MessageActionsToolbar: UIToolbar {

    weak var actionDelegate: MessageActionsToolbarDelegate?

    enum Mode {
        case normal(messagesActions: [MessageAction])
        case selection(deleteMessagesAction: MessageAction,
                       forwardMessagesAction: MessageAction)
    }
    private let mode: Mode

    deinit {
        Logger.verbose("")
    }

    required init(mode: Mode) {
        self.mode = mode

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

    private func buildItems() {
        switch mode {
        case .normal(let messagesActions):
            buildNormalItems(messagesActions: messagesActions)
        case .selection(let deleteMessagesAction, let forwardMessagesAction):
            buildSelectionItems(deleteMessagesAction: deleteMessagesAction,
                                forwardMessagesAction: forwardMessagesAction)
        }
    }

    var actionItems = [MessageActionsToolbarButton]()

    private func buildNormalItems(messagesActions: [MessageAction]) {
        var newItems = [UIBarButtonItem]()

        var actionItems = [MessageActionsToolbarButton]()
        for action in messagesActions {
            if !newItems.isEmpty {
                newItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
            }

            let actionItem = MessageActionsToolbarButton(actionsToolbar: self, messageAction: action)
            actionItem.tintColor = Theme.primaryIconColor
            actionItem.accessibilityLabel = action.accessibilityLabel
            newItems.append(actionItem)
            actionItems.append(actionItem)
        }

        // If we only have a single button, center it.
        if newItems.count == 1 {
            newItems.insert(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), at: 0)
            newItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        }

        items = newItems
        self.actionItems = actionItems
    }

    private func buildSelectionItems(deleteMessagesAction: MessageAction,
                                     forwardMessagesAction: MessageAction) {

        let deleteItem = MessageActionsToolbarButton(actionsToolbar: self, messageAction: deleteMessagesAction)
        let forwardItem = MessageActionsToolbarButton(actionsToolbar: self, messageAction: forwardMessagesAction)

        let selectedCount: Int = 0
        let labelTitle: String
        if selectedCount == 0 {
            labelTitle = NSLocalizedString("MESSAGE_ACTIONS_TOOLBAR_LABEL_0",
                                           comment: "Label for the toolbar used in the multi-select mode of conversation view when 0 items are selected.")
        } else if selectedCount == 1 {
            labelTitle = NSLocalizedString("MESSAGE_ACTIONS_TOOLBAR_LABEL_1",
                                           comment: "Label for the toolbar used in the multi-select mode of conversation view when 1 item is selected.")
        } else {
            let labelFormat = NSLocalizedString("MESSAGE_ACTIONS_TOOLBAR_LABEL_N_FORMAT",
                                                comment: "Format for the toolbar used in the multi-select mode of conversation view. Embeds: {{ %@ the number of currently selected items }}.")
            labelTitle = String(format: labelFormat, OWSFormat.formatInt(selectedCount))
        }
        let labelItem = UIBarButtonItem(title: labelTitle, style: .plain, target: nil, action: nil)

        var newItems = [UIBarButtonItem]()
        newItems.append(deleteItem)
        newItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        newItems.append(labelItem)
        newItems.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        newItems.append(forwardItem)

        items = newItems
        self.actionItems = [ deleteItem, forwardItem ]
    }

    public func buttonItem(for actionType: MessageAction.MessageActionType) -> UIBarButtonItem? {
        for actionItem in actionItems {
            if actionItem.messageAction.actionType == actionType {
                return actionItem
            }
        }
        owsFailDebug("Missing action item: \(actionType).")
        return nil
    }
}

// MARK: -

class MessageActionsToolbarButton: UIBarButtonItem {
    private weak var actionsToolbar: MessageActionsToolbar?
    fileprivate let messageAction: MessageAction

    required init(actionsToolbar: MessageActionsToolbar,
                  messageAction: MessageAction) {
        self.actionsToolbar = actionsToolbar
        self.messageAction = messageAction

        super.init(image: messageAction.image.withRenderingMode(.alwaysTemplate),
                   style: .plain,
                   target: nil,
                   action: nil)
        self.target = self
        self.action = #selector(didTapItem(_:))
        self.tintColor = Theme.primaryIconColor
        self.accessibilityLabel = messageAction.accessibilityLabel
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func didTapItem(_ item: UIBarButtonItem) {
        AssertIsOnMainThread()

        guard let actionsToolbar = actionsToolbar,
              let actionDelegate = actionsToolbar.actionDelegate else {
            return
        }
        actionDelegate.messageActionsToolbar(actionsToolbar, executedAction: messageAction)
    }
}
