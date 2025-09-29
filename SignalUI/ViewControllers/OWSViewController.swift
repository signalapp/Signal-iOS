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
}

final private class PassthroughTouchSpacerView: SpacerView {

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        if view == self {
            return nil
        }
        return view
    }
}
