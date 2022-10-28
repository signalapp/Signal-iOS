//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
open class OWSViewController: UIViewController {

    /// If observing keyboard events is unecessary, override this to true to just drop them for a slight performance gain.
    public var shouldIgnoreKeyboardChanges = false

    // If true, the bottom view never "reclaims" layout space if the keyboard is dismissed.
    // Defaults to false.
    public var shouldBottomViewReserveSpaceForKeyboard = false

    /// If true, sets the root view's background color to `Theme.background` on load.
    public var shouldUseTheme: Bool = false

    @discardableResult
    public final func autoPinView(
        toBottomOfViewControllerOrKeyboard view: UIView,
        avoidNotch: Bool,
        adjustmentWithKeyboardPresented adjustment: CGFloat = 0
    ) -> NSLayoutConstraint {
        owsAssertDebug(self.bottomLayoutConstraint == nil)

        self.observeNotificationsForBottomView()

        self.bottomLayoutView = view
        self.keyboardAdjustmentOffsetForAutoPinnedToBottomView = adjustment
        if avoidNotch {
            self.bottomLayoutConstraint = view.autoPin(toBottomLayoutGuideOf: self, withInset: self.lastBottomLayoutInset)
        } else {
            self.bottomLayoutConstraint = view.autoPinEdge(
                .bottom,
                to: .bottom,
                of: self.view,
                withOffset: self.lastBottomLayoutInset
            )
        }
        return self.bottomLayoutConstraint!
    }

    public final func removeBottomLayout() {
        bottomLayoutConstraint?.autoRemove()
        bottomLayoutView = nil
        bottomLayoutConstraint = nil
    }

    @objc
    open dynamic func themeDidChange() {
        AssertIsOnMainThread()

        applyTheme()
    }

    @objc
    open dynamic func applyTheme() {
        AssertIsOnMainThread()

        // Do nothing; this is a convenience hook for subclasses.
    }

    public init() {
        super.init(nibName: nil, bundle: nil)

        self.observeActivation()
    }

    deinit {
        // Surface memory leaks by logging the deallocation of view controllers.
        OWSLogger.verbose("Dealloc: \(type(of: self))")
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        if shouldUseTheme {
            view.backgroundColor = Theme.backgroundColor
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .ThemeDidChange,
            object: nil
        )
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        shouldAnimateBottomLayout = true

        #if DEBUG
        ensureNavbarAccessibilityIds()
        #endif
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        shouldAnimateBottomLayout = false
    }

    #if DEBUG
    func ensureNavbarAccessibilityIds() {
        guard let navigationBar = navigationController?.navigationBar else {
            return
        }
        // There isn't a great way to assign accessibilityIdentifiers to default
        // navbar buttons, e.g. the back button.  As a (DEBUG-only) hack, we
        // assign accessibilityIds to any navbar controls which don't already have
        // one.  This should offer a reliable way for automated scripts to find
        // these controls.
        //
        // UINavigationBar often discards and rebuilds new contents, e.g. between
        // presentations of the view, so we need to do this every time the view
        // appears.  We don't do any checking for accessibilityIdentifier collisions
        // so we're counting on the fact that navbar contents are short-lived.
        var accessibilityIdCounter = 0
        navigationBar.traverseHierarchyDownward { view in
            if view is UIControl, view.accessibilityIdentifier == nil {
                // The view should probably be an instance of _UIButtonBarButton or _UIModernBarButton.
                view.accessibilityIdentifier = String(format: "navbar-%ld", accessibilityIdCounter)
                accessibilityIdCounter += 1
            }
        }
    }
    #endif

    // MARK: - Activation

    private func observeActivation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(owsViewControllerApplicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc
    private func owsViewControllerApplicationDidBecomeActive() {
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - Keyboard Layout

    private var lastBottomLayoutInset: CGFloat = 0
    private var bottomLayoutView: UIView?
    private var bottomLayoutConstraint: NSLayoutConstraint?
    private var shouldAnimateBottomLayout = false
    private var keyboardAdjustmentOffsetForAutoPinnedToBottomView: CGFloat = 0

    private var hasObservedNotifications = false

    private func observeNotificationsForBottomView() {
        AssertIsOnMainThread()

        guard !hasObservedNotifications else {
            return
        }
        self.hasObservedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotificationBase),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotificationBase),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotificationBase),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotificationBase),
            name: UIResponder.keyboardDidHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotificationBase),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardNotificationBase),
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil
        )

    }

    @objc private func handleKeyboardNotificationBase(_ notification: NSNotification) {
        AssertIsOnMainThread()

        guard !shouldIgnoreKeyboardChanges else {
            return
        }

        let userInfo = notification.userInfo

        guard var keyboardEndFrame = (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            owsFailDebug("Missing keyboard end frame")
            return
        }

        if keyboardEndFrame == .zero {
            // If reduce motion+crossfade transitions is on, in iOS 14 UIKit vends out a keyboard end frame
            // of CGRect zero. This breaks the math below.
            //
            // If our keyboard end frame is CGRectZero, build a fake rect that's translated off the bottom edge.
            let deviceBounds = UIScreen.main.bounds
            keyboardEndFrame = deviceBounds.offsetBy(dx: 0, dy: deviceBounds.height)
        }

        let keyboardEndFrameConverted = self.view.convert(keyboardEndFrame, from: nil)
        // Adjust the position of the bottom view to account for the keyboard's
        // intrusion into the view.
        //
        // On iPhones with no physical home button, when no keyboard is present,
        // we include a buffer at the bottom of the screen so the bottom view
        // clears the floating "home button". But because the keyboard includes it's own buffer,
        // we subtract the size of bottom "safe area",
        // else we'd have an unnecessary buffer between the popped keyboard and the input bar.
        let newInset = max(
            0,
            self.view.height
            + self.keyboardAdjustmentOffsetForAutoPinnedToBottomView
            - self.view.safeAreaInsets.bottom
            - keyboardEndFrameConverted.origin.y
        )
        self.lastBottomLayoutInset = newInset

        let rawCurve = userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int
        let curve = UIView.AnimationCurve(rawValue: rawCurve ?? 0) ?? .easeInOut
        let duration = userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0
        // Should we ignore keyboard changes if they're coming from somewhere out-of-process?
        // BOOL isOurKeyboard = [notification.userInfo[UIKeyboardIsLocalUserInfoKey] boolValue];

        let updateLayout = {
            if self.shouldBottomViewReserveSpaceForKeyboard, newInset == 0 {
                // To avoid unnecessary animations / layout jitter,
                // some views never reclaim layout space when the keyboard is dismissed.
                //
                // They _do_ need to relayout if the user switches keyboards.
                return
            }
            self.updateBottomLayoutConstraint(
                fromInset: -1 * (self.bottomLayoutConstraint?.constant ?? 0),
                toInset: newInset
            )
        }
        if self.shouldAnimateBottomLayout, duration > 0, !UIAccessibility.isReduceMotionEnabled {
            UIView.beginAnimations("keyboardStateChange", context: nil)
            UIView.setAnimationBeginsFromCurrentState(true)
            UIView.setAnimationCurve(curve)
            UIView.setAnimationDuration(duration)
            updateLayout()
            UIView.commitAnimations()
        } else {
            // UIKit by default (sometimes? never?) animates all changes in response to keyboard events.
            // We want to suppress those animations if the view isn't visible,
            // otherwise presentation animations don't work properly.
            UIView.performWithoutAnimation {
                updateLayout()
            }
        }
    }

    @objc
    open dynamic func updateBottomLayoutConstraint(fromInset before: CGFloat, toInset after: CGFloat) {
        self.bottomLayoutConstraint?.constant = -after
        self.bottomLayoutView?.superview?.layoutIfNeeded()
    }

    // MARK: - Orientation

    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.defaultSupportedOrientations
    }
}
