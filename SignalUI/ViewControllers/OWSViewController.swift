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

        if #unavailable(iOS 16) {
            let layoutGuide = UILayoutGuide()
            layoutGuide.identifier = "iOS15KeyboardLayoutGuide"
            view.addLayoutGuide(layoutGuide)
            let heightConstraint = layoutGuide.heightAnchor.constraint(equalToConstant: view.safeAreaInsets.bottom)
            NSLayoutConstraint.activate([
                layoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                layoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                layoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                heightConstraint,
            ])
            iOS15KeyboardLayoutGuide = layoutGuide
            iOS15KeyboardLayoutGuideHeightConstraint = heightConstraint
        }

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
    }

    open override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        // Whatever keyboard frame we knew about is now invalidated.
        // They keyboard will update us if its on screen, setting this again.
        lastKnownKeyboardFrame = nil
    }

    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        updateiOS15KeyboardLayoutGuide()
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

    // MARK: - Orientation

    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.defaultSupportedOrientations
    }

    // MARK: - Keyboard Layout Guide

    // On iOS 15 provides access to last known keyboard frame.
    // On newer iOS versions this is a proxy for `view.keyboardLayoutGuide`.
    @available(iOS, deprecated: 16.0)
    final public var keyboardLayoutGuide: UILayoutGuide {
        return iOS15KeyboardLayoutGuide ?? view.keyboardLayoutGuide
    }

    @available(iOS, deprecated: 16.0)
    private var iOS15KeyboardLayoutGuide: UILayoutGuide?

    @available(iOS, deprecated: 16.0)
    private var iOS15KeyboardLayoutGuideHeightConstraint: NSLayoutConstraint?

    @available(iOS, deprecated: 16.0)
    private var isObservingKeyboardNotifications = false

    @available(iOS, deprecated: 16.0)
    private var lastKnownKeyboardFrame: CGRect?

    @available(iOS, deprecated: 16.0)
    private static var keyboardNotificationNames: [Notification.Name] = [
        UIResponder.keyboardWillShowNotification,
        UIResponder.keyboardDidShowNotification,
        UIResponder.keyboardWillHideNotification,
        UIResponder.keyboardDidHideNotification,
        UIResponder.keyboardWillChangeFrameNotification,
        UIResponder.keyboardDidChangeFrameNotification
    ]

    @available(iOS, deprecated: 16.0)
    private func observeKeyboardNotificationsIfNeeded() {
        guard #unavailable(iOS 16.0) else { return }

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

    @available(iOS, deprecated: 16.0)
    private func stopObservingKeyboardNotifications() {
        Self.keyboardNotificationNames.forEach {
            NotificationCenter.default.removeObserver(self, name: $0, object: nil)
        }
        isObservingKeyboardNotifications = false
    }

    @objc
    @available(iOS, deprecated: 16.0)
    private func handleKeyboardNotificationBase(_ notification: NSNotification) {
        let userInfo = notification.userInfo
        guard let keyboardEndFrame = (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            owsFailDebug("Missing keyboard end frame")
            return
        }

        let keyboardEndFrameConverted = view.convert(keyboardEndFrame, from: nil)
        guard keyboardEndFrameConverted != lastKnownKeyboardFrame else {
            // No change.
            return
        }
        lastKnownKeyboardFrame = keyboardEndFrameConverted
        updateiOS15KeyboardLayoutGuide()
    }

    @available(iOS, deprecated: 16.0)
    private func updateiOS15KeyboardLayoutGuide() {
        guard let iOS15KeyboardLayoutGuideHeightConstraint else { return }

        var keyboardHeight = view.safeAreaInsets.bottom
        if let lastKnownKeyboardFrame {
            keyboardHeight = max(keyboardHeight, view.bounds.maxY - lastKnownKeyboardFrame.minY)
        }
        guard iOS15KeyboardLayoutGuideHeightConstraint.constant != keyboardHeight else { return }
        iOS15KeyboardLayoutGuideHeightConstraint.constant = keyboardHeight
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
