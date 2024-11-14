//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI

// MARK: - AppearanceTransitionState

public enum HostingControllerAppearanceTransitionState {
    case appearing
    case finished
    case cancelled
}

private enum AppearanceTransitionStateEnvironmentKey: EnvironmentKey {
    static var defaultValue: HostingControllerAppearanceTransitionState? {
        nil
    }
}

extension EnvironmentValues {
    public var appearanceTransitionState: HostingControllerAppearanceTransitionState? {
        get { self[AppearanceTransitionStateEnvironmentKey.self] }
        set { self[AppearanceTransitionStateEnvironmentKey.self] = newValue }
    }
}

// MARK: - HostingContainer

/// Container view controller around ``HostingController``.
/// Useful when you want to manually set navigation item bar buttons from a
/// UIKit context, to avoid `UIHostingController`'s behavior of only displaying
/// bar buttons once fully appeared.
open class HostingContainer<Wrapped: View>: UIViewController {
    private let hostingController: HostingController<Wrapped>

    public init(wrappedView: Wrapped) {
        self.hostingController = .init(wrappedView: wrappedView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("unimplemented")
    }

    open override func viewDidLoad() {
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.autoPinEdgesToSuperviewEdges()
        hostingController.didMove(toParent: self)
    }
}

extension HostingContainer: OWSNavigationChildController {
    public var childForOWSNavigationConfiguration: (any OWSNavigationChildController)? {
        hostingController
    }
}

// MARK: - HostingController

/// Extends UIHostingController by wrapping its `rootView` and adding additional
/// values to the wrapped view's environment.
///
/// Adds `EnvironmentValues.appearanceTransitionState` to the wrapped view's
/// environment, allowing SwiftUI views to explicitly control whether animations
/// are performed during a navigation transition, or after completion.
open class HostingController<Wrapped: View>: UIHostingController<_HostingControllerWrapperView<Wrapped>> {

    private var scrollOffset: CGFloat = 0 {
        didSet {
            let scrollOffsetDidFlip = scrollOffset * oldValue <= 0
            if scrollOffsetDidFlip {
                owsNavigationController?.updateNavbarAppearance(animated: true)
            }
        }
    }

    public init(wrappedView: Wrapped) {
        super.init(rootView: _HostingControllerWrapperView(wrappedView: wrappedView))
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("unimplemented")
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        rootView.scrollOffsetDidChange = { [weak self] scrollOffset in
            self?.scrollOffset = scrollOffset
        }

        rootView.appearanceTransitionState = .appearing

        if let transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { context in
                self.rootView.appearanceTransitionState = context.isCancelled ? .cancelled : .finished
            }
        }
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if transitionCoordinator == nil {
            rootView.appearanceTransitionState = .finished
        }
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        rootView.appearanceTransitionState = nil
    }
}

extension HostingController: OWSNavigationChildController {
    private var usesSolidNavbarStyle: Bool {
        scrollOffset <= 0
    }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle {
        usesSolidNavbarStyle ? .solid : .blur
    }

    public var navbarBackgroundColorOverride: UIColor? {
        usesSolidNavbarStyle ? UIColor.Signal.groupedBackground : nil
    }
}

public struct _HostingControllerWrapperView<Wrapped: View>: View {
    fileprivate var wrappedView: Wrapped
    fileprivate var appearanceTransitionState: HostingControllerAppearanceTransitionState?
    fileprivate var scrollOffsetDidChange: ((CGFloat) -> Void)?

    public var body: some View {
        wrappedView
            .environment(\.appearanceTransitionState, appearanceTransitionState)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset in
                scrollOffsetDidChange?(scrollOffset)
            }
    }
}
