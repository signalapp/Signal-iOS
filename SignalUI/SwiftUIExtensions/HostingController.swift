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

// MARK: - HostingController

/// Extends UIHostingController by wrapping its `rootView` and adding additional
/// values to the wrapped view's environment.
///
/// Adds `EnvironmentValues.appearanceTransitionState` to the wrapped view's
/// environment, allowing SwiftUI views to explicitly control whether animations
/// are performed during a navigation transition, or after completion.
open class HostingController<Wrapped: View>: UIHostingController<_HostingControllerWrapperView<Wrapped>> {
    public init(wrappedView: Wrapped) {
        super.init(rootView: _HostingControllerWrapperView(wrappedView: wrappedView))
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("unimplemented")
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

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

public struct _HostingControllerWrapperView<Wrapped: View>: View {
    fileprivate var wrappedView: Wrapped
    fileprivate var appearanceTransitionState: HostingControllerAppearanceTransitionState?

    public var body: some View {
        wrappedView
            .environment(\.appearanceTransitionState, appearanceTransitionState)
    }
}
