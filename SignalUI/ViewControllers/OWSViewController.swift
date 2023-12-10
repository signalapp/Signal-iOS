//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public enum ViewControllerLifecycle: Equatable {
    /// `viewDidLoad` hasn't happened yet.
    case notLoaded
    /// Prior to `viewWillAppear` and after `viewDidDisappear`.
    case notAppeared
    /// After `viewWillAppear` and before `viewDidAppear`.
    case willAppear
    /// After `viewDidAppear` and before `viewWillDisappear`.
    case appeared
    /// After `viewWillDisappear` and before `viewDidDisappear`.
    case willDisappear

    var isLoaded: Bool {
        return self != .notLoaded
    }

    var isVisible: Bool {
        switch self {
        case .willAppear, .appeared, .willDisappear:
            return true
        default:
            return false
        }
    }
}

open class OWSViewController: UIViewController {

    /// Current state of the view lifecycle.
    /// Note changes are triggered by the lifecycle methods `viewDidLoad` `viewWillAppear` `viewDidAppear`
    /// `viewWillDisappear` `viewDidDisappear`; those can be overridden to get state change hooks as per normal.
    public private(set) final var lifecycle = ViewControllerLifecycle.notLoaded {
        didSet {
            achievedLifecycleStates.insert(lifecycle)
        }
    }

    /// All lifecycle states achieved so far in the lifetime of this view controller.
    public private(set) final var achievedLifecycleStates = Set<ViewControllerLifecycle>()

    // MARK: - Keyboard handling

    public enum KeyboardObservationBehavior {
        /// Don't observe keyboard frame changes.
        /// WARNING: makes `keyboardFrameDidChange` non-functional.
        case never
        /// Only observe keyboard frame changes while the view is between `willAppear` and `didDisappear`.
        case whileLifecycleVisible
        /// Always observe keyboard frame changes.
        case always
    }

    public final var keyboardObservationBehavior: KeyboardObservationBehavior = .always {
        didSet {
            observeKeyboardNotificationsIfNeeded()
        }
    }

    /// Subclasses can override this method for a hook on keyboard frame changes.
    /// NOTE: overrides _must_ call the superclass version of this method, similarly to other view lifecycle methods.
    /// - Parameter newFrame: The frame of the keyboard _after_ any animations, in the view controller's view's coordinates.
    open func keyboardFrameDidChange(
        _ newFrame: CGRect,
        animationDuration: TimeInterval,
        animationOptions: UIView.AnimationOptions
    ) {
        self.handleKeyboardFrameChange(newFrame, animationDuration, animationOptions)
    }

    /// A non-rendering spacer view that tracks the space _not_ covered by the keyboard.
    /// When the keyboard is collapsed, the bottom of this view is the bottom of the root view _not_ respecting safe area.
    public final var keyboardLayoutGuideView: SpacerView { getOrCreateKeyboardLayoutView(safeArea: false) }

    /// A non-rendering spacer view that tracks the space _not_ covered by the keyboard.
    /// When the keyboard is collapsed, the bottom of this view is the bottom of the root view respecting safe area.
    public final var keyboardLayoutGuideViewSafeArea: SpacerView { getOrCreateKeyboardLayoutView(safeArea: true) }

    // MARK: - Themeing and content size categories

    /// An overridable method for subclasses to hook into theme changes, to
    /// adjust their contents.
    @objc
    open func themeDidChange() {
        AssertIsOnMainThread()
    }

    /// An overridable method for subclasses to hook into content size category
    /// changes, to ensure their content adapts.
    @objc
    open func contentSizeCategoryDidChange() {
        AssertIsOnMainThread()
    }

    // MARK: - Init

    public init() {
        super.init(nibName: nil, bundle: nil)

        self.observeAppState()
    }

    deinit {
        // Surface memory leaks by logging the deallocation of view controllers.
        Logger.verbose("Dealloc: \(type(of: self))")
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    /// Subclasses can override to respond to application state changes.
    /// NOTE: overrides _must_ call the superclass version of this method, similarly to other view lifecycle methods.
    @objc
    open func appWillEnterForeground() {
        // Do nothing; just a hook for subclasses
    }

    /// Subclasses can override to respond to application state changes.
    /// NOTE: overrides _must_ call the superclass version of this method, similarly to other view lifecycle methods.
    @objc
    open func appDidBecomeActive() {
        setNeedsStatusBarAppearanceUpdate()
    }

    /// Subclasses can override to respond to application state changes.
    /// NOTE: overrides _must_ call the superclass version of this method, similarly to other view lifecycle methods.
    @objc
    open func appWillResignActive() {
        // Do nothing; just a hook for subclasses
    }

    /// Subclasses can override to respond to application state changes.
    /// NOTE: overrides _must_ call the superclass version of this method, similarly to other view lifecycle methods.
    @objc
    open func appDidEnterBackground() {
        // Do nothing; just a hook for subclasses
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        self.lifecycle = .notAppeared

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil
        )
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.lifecycle = .willAppear

        observeKeyboardNotificationsIfNeeded()
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.lifecycle = .appeared

        #if DEBUG
        ensureNavbarAccessibilityIds()
        #endif
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.lifecycle = .willDisappear
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.lifecycle = .notAppeared

        observeKeyboardNotificationsIfNeeded()
    }

    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        updateKeyboardLayoutOffsets()
    }

    open override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)

        // Whatever keyboard frame we knew about is now invalidated.
        // They keyboard will update us if its on screen, setting this again.
        lastKnownKeyboardFrame = nil

        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateKeyboardLayoutOffsets()
        }
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

    private func observeAppState() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )
    }

    @objc
    private func owsViewControllerApplicationDidBecomeActive() {
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - Keyboard Layout

    private var isObservingKeyboardNotifications = false

    static var keyboardNotificationNames: [Notification.Name] = [
        UIResponder.keyboardWillShowNotification,
        UIResponder.keyboardDidShowNotification,
        UIResponder.keyboardWillHideNotification,
        UIResponder.keyboardDidHideNotification,
        UIResponder.keyboardWillChangeFrameNotification,
        UIResponder.keyboardDidChangeFrameNotification
    ]

    private func observeKeyboardNotificationsIfNeeded() {
        switch keyboardObservationBehavior {
        case .always:
            break
        case .never:
            stopObservingKeyboardNotifications()
            return
        case .whileLifecycleVisible:
            if !lifecycle.isVisible {
                stopObservingKeyboardNotifications()
                return
            }
        }

        if isObservingKeyboardNotifications { return }
        isObservingKeyboardNotifications = true

        Self.keyboardNotificationNames.forEach {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleKeyboardNotificationBase(_:)),
                name: $0,
                object: nil
            )
        }
    }

    private func stopObservingKeyboardNotifications() {
        Self.keyboardNotificationNames.forEach {
            NotificationCenter.default.removeObserver(self, name: $0, object: nil)
        }
        isObservingKeyboardNotifications = false
    }

    private var lastKnownKeyboardFrame: CGRect?

    @objc
    private func handleKeyboardNotificationBase(_ notification: NSNotification) {
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
            let deviceBounds = CurrentAppContext().frame
            keyboardEndFrame = CGRect(
                x: deviceBounds.minX,
                y: deviceBounds.maxY,
                width: deviceBounds.width,
                height: 0
            )
        }

        let keyboardEndFrameConverted = self.view.convert(keyboardEndFrame, from: nil)

        guard keyboardEndFrameConverted != lastKnownKeyboardFrame else {
            // No change.
            return
        }
        lastKnownKeyboardFrame = keyboardEndFrameConverted

        let animationOptions: UIView.AnimationOptions
        if let rawCurve = userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt {
            animationOptions = .init(rawValue: rawCurve << 16)
        } else {
            animationOptions = .curveEaseInOut
        }
        let duration = userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0
        // Should we ignore keyboard changes if they're coming from somewhere out-of-process?
        // BOOL isOurKeyboard = [notification.userInfo[UIKeyboardIsLocalUserInfoKey] boolValue];

        keyboardFrameDidChange(keyboardEndFrameConverted, animationDuration: duration, animationOptions: animationOptions)
    }

    // This should be able to be a UILayoutGuide instead, but alas, PureLayout doesn't support those.
    private var _keyboardLayoutView: SpacerView?
    private var keyboardLayoutViewBottomConstraint: NSLayoutConstraint?
    private var _keyboardLayoutViewSafeArea: SpacerView?
    private var keyboardLayoutViewSafeAreaBottomConstraint: NSLayoutConstraint?

    private func getOrCreateKeyboardLayoutView(safeArea: Bool) -> SpacerView {
        if let keyboardLayoutView = safeArea ? _keyboardLayoutViewSafeArea : _keyboardLayoutView {
            return keyboardLayoutView
        }
        let view = PassthroughTouchSpacerView()
        self.view.addSubview(view)
        if safeArea {
            view.autoPinEdgesToSuperviewSafeArea(with: .zero, excludingEdge: .bottom)
            keyboardLayoutViewSafeAreaBottomConstraint = view.autoPinEdge(toSuperviewSafeArea: .bottom)
            _keyboardLayoutViewSafeArea = view
        } else {
            view.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
            keyboardLayoutViewBottomConstraint = view.autoPinEdge(.bottom, to: .bottom, of: self.view)
            _keyboardLayoutView = view
        }
        updateKeyboardLayoutOffsets()
        return view
    }

    private func handleKeyboardFrameChange(_ keyboardEndFrame: CGRect, _ duration: TimeInterval, _ animationOptions: UIView.AnimationOptions) {
        guard lifecycle.isVisible, duration > 0, !UIAccessibility.isReduceMotionEnabled else {
            // UIKit by default (sometimes? never?) animates all changes in response to keyboard events.
            // We want to suppress those animations if the view isn't visible,
            // otherwise presentation animations don't work properly.
            UIView.performWithoutAnimation {
                self.updateKeyboardLayoutOffsets()
            }
            return
        }
        updateKeyboardLayoutOffsets()
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: animationOptions,
            animations: {
                self.view.layoutIfNeeded()
            }
        )
    }

    private func updateKeyboardLayoutOffsets() {
        guard let lastKnownKeyboardFrame = lastKnownKeyboardFrame else {
            return
        }
        if let keyboardLayoutViewBottomConstraint = self.keyboardLayoutViewBottomConstraint {
            keyboardLayoutViewBottomConstraint.constant = lastKnownKeyboardFrame.minY - view.bounds.height
        }
        if let keyboardLayoutViewSafeAreaBottomConstraint = self.keyboardLayoutViewSafeAreaBottomConstraint {
            if lastKnownKeyboardFrame.minY < view.height - view.safeAreaInsets.bottom {
                keyboardLayoutViewSafeAreaBottomConstraint.constant =
                    lastKnownKeyboardFrame.minY - (view.bounds.height - view.safeAreaInsets.bottom)
            } else {
                keyboardLayoutViewSafeAreaBottomConstraint.constant = 0
            }
        }
    }

    // MARK: - Orientation

    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.defaultSupportedOrientations
    }
}

private class PassthroughTouchSpacerView: SpacerView {

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        if view == self {
            return nil
        }
        return view
    }
}
