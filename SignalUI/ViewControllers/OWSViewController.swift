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

    override open func viewDidLoad() {
        super.viewDidLoad()

        self.lifecycle = .notAppeared

        installContentLayouGuide()

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
            object: nil,
        )
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.lifecycle = .willAppear

        observeKeyboardNotificationsIfNeeded()
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.lifecycle = .appeared

#if DEBUG
        ensureNavbarAccessibilityIds()
#endif
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.lifecycle = .willDisappear
    }

    override open func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.lifecycle = .notAppeared
    }

    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        // Whatever keyboard frame we knew about is now invalidated.
        // They keyboard will update us if its on screen, setting this again.
        lastKnownKeyboardFrame = nil
    }

    override open func viewSafeAreaInsetsDidChange() {
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
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil,
        )
    }

    @objc
    private func owsViewControllerApplicationDidBecomeActive() {
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - Content Layout Guide

    /// Defines an area for static content to be laid in.
    ///
    /// `contentLayoutGuide` is meant to provide subclasses with a unified area for static content.
    /// This layout guide is designed to be used across all devices and interface orientations.
    ///
    ///
    /// These are the margins `contentLayoutGuide` defines relative to root view's edges:
    /// * iPhone portrait (vertical regular, horizontal compact)
    ///   * Top
    ///     * Notch/Dymamic island iPhones: same as safe area.
    ///     * Home button iPhones: same as status bar area (20 pt).
    ///   * Leading/trailing
    ///     * Plus/Max/Air iPhones: 20 pt.
    ///     * Other iPhones: 16 pt.
    ///   * Bottom
    ///     * Notch/Dymamic island iPhones: same as safe area.
    ///     * Home button iPhones: manual 20 pt to match top margin.
    ///
    /// * iPhone Landscape (vertical compact, horizontal regular on Plus/Max iPhones)
    ///   * Top
    ///    * Same as safe area, which is mostly 20 pt but can be zero
    ///      on smaller phones running older iOS versions.
    ///   * Leading/trailing
    ///     * Notch/Dymamic island iPhones: safe area + 16 pts, more if content width is capped at 640 pts.
    ///     * Home button iPhones: 20 pt.
    ///   * Bottom
    ///     * All iPhones: 20 pt.
    ///
    /// * iPad
    ///   * Usable margins (20 or 10 pt) on all sides.
    ///
    public final var contentLayoutGuide = UILayoutGuide()

    private var currentContentLayoutGuideConstraints: [NSLayoutConstraint] = []

    private func installContentLayouGuide() {
        contentLayoutGuide.identifier = "Static Content Layout Guide"
        view.addLayoutGuide(contentLayoutGuide)

        // Permanent constraints.
        NSLayoutConstraint.activate([
            contentLayoutGuide.centerXAnchor.constraint(equalTo: view.layoutMarginsGuide.centerXAnchor),
        ])

        // Flexible constraints.
        updateContentLayoutGuideConstraints()
    }

    private func contentLayoutConstraintsForCurrentTraitCollection() -> [NSLayoutConstraint] {
        var constraints = [NSLayoutConstraint]()

        let isVerticalCompact = traitCollection.verticalSizeClass == .compact
        let isHorizontalCompact = traitCollection.horizontalSizeClass == .compact
        let isiPad = traitCollection.userInterfaceIdiom == .pad

        Logger.debug("Vertical compact: [\(isVerticalCompact ? "Y" : "N")]")
        Logger.debug("Horizontal compact: [\(isHorizontalCompact ? "Y" : "N")]")
        Logger.debug("Layout margins: [\(view.layoutMarginsGuide.layoutFrame)]")

        // Vertical
        if isVerticalCompact {
            // Whole available height.
            constraints += [
                contentLayoutGuide.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
                contentLayoutGuide.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
            ]
        } else {
            var bottomMargin: CGFloat = 0
            // iPhones with home button have zero bottom layout margin for some reason. No bueno!
            if !isiPad, !UIDevice.current.hasIPhoneXNotch {
                bottomMargin = 20
            }
            constraints += [
                contentLayoutGuide.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
                contentLayoutGuide.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: -bottomMargin),
            ]
        }

        // Horizontal
        if isiPad, !isHorizontalCompact {
            // No wider than 628 pts, centered.
            // 628 is the minimum width of `layoutMarginsGuide.frame` when horizonal size class is regular.
            constraints.append({
                let constraint = contentLayoutGuide.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor)
                constraint.priority = .init(UILayoutPriority.required.rawValue - 10)
                return constraint
            }())
            constraints += [
                contentLayoutGuide.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
                contentLayoutGuide.widthAnchor.constraint(lessThanOrEqualToConstant: 628),
            ]
        } else {
            // Whole available width.
            constraints += [
                contentLayoutGuide.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            ]
        }

        return constraints
    }

    private func updateContentLayoutGuideConstraints() {
        NSLayoutConstraint.deactivate(currentContentLayoutGuideConstraints)
        currentContentLayoutGuideConstraints = contentLayoutConstraintsForCurrentTraitCollection()
        NSLayoutConstraint.activate(currentContentLayoutGuideConstraints)
    }

    override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if
            previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass ||
            previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass
        {
            updateContentLayoutGuideConstraints()
        }
    }

    // MARK: - Orientation

    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.defaultSupportedOrientations
    }

    // MARK: - Keyboard Layout Guide

    // On iOS 15 provides access to last known keyboard frame.
    // On newer iOS versions this is a proxy for `view.keyboardLayoutGuide`.
    @available(iOS, deprecated: 16.0)
    public final var keyboardLayoutGuide: UILayoutGuide {
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
        UIResponder.keyboardDidChangeFrameNotification,
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
                object: nil,
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

public extension OWSViewController {

    /// Add provided views to view controller's view hierarchy in a vertical stack.
    ///
    /// Use this method for adding vertically aligned static content to the view controller's view.
    ///
    /// - Parameters:
    ///   - arrangedSubviews: Views to add to the view hierarchy.
    ///   - isScrollable: If set to `true`, stack view will be embedded in a vertical scroll view. Use this if there's a chance that content won't fit screen height.
    ///   - shouldAvoidKeyboard: If set to `true`, bottom edge of the stack view will be pinned to top of the keyboard.
    ///
    /// - Returns:
    ///   A vertical stack view that has been configured using default parameters and added to view controller's view along with necessary auto layout constraints.
    @discardableResult
    func addStaticContentStackView(
        arrangedSubviews: [UIView],
        isScrollable: Bool = false,
        shouldAvoidKeyboard: Bool = false,
    ) -> UIStackView {

        let stackView = UIStackView(arrangedSubviews: arrangedSubviews)
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false

        if isScrollable {
            let scrollView = UIScrollView()
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scrollView)
            scrollView.addSubview(stackView)
            NSLayoutConstraint.activate([
                // Scroll view's top is constrained to `contentLayoutGuide`.
                scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
                // Scroll view's bottom is constrained either to `contentLayouGuide` or to `keyboardLayoutGuide`.
                {
                    if shouldAvoidKeyboard {
                        scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor)
                    } else {
                        scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor)
                    }

                }(),

                // Scroll view is horizontally constrained to root view's safe area.
                // This is done so that scroll view's indicator isn't too close to the content.
                scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

                // Stack view is vertically constrained to scroll view's `contentLayoutGuide`.
                stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),

                // Stack view is stretched vertically to fill scroll view's height.
                stackView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),

                // Stack view is horizontally constrained to `contentLayoutGuide`.
                stackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            ])
        } else {
            view.addSubview(stackView)
            NSLayoutConstraint.activate([
                // Stack view is constrained to `contentLayoutGuide` in all but one directions.
                stackView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
                stackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
                // Stack view's bottom is constrained either to `contentLayouGuide` or to `keyboardLayoutGuide`.
                {
                    if shouldAvoidKeyboard {
                        stackView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor)
                    } else {
                        stackView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor)
                    }
                }(),
            ])
        }

        return stackView
    }
}
