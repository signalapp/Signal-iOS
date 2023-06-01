//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

extension UIWindow.Level {

    // Behind everything, especially the root window.
    public static let _background: UIWindow.Level = .init(rawValue: -1)

    fileprivate static let _returnToCall: UIWindow.Level = .init(rawValue: UIWindow.Level.statusBar.rawValue - 1)

    // In front of the root window, behind the screen blocking window.

    // In front of the root window, behind the screen blocking window.
    fileprivate static let _callView: UIWindow.Level = .init(rawValue: UIWindow.Level.normal.rawValue + 2)

    // In front of the status bar and CallView
    fileprivate static let _screenBlocking: UIWindow.Level = .init(rawValue: UIWindow.Level.statusBar.rawValue + 2)
}

class WindowManager {

    init() {
        AssertIsOnMainThread()
        SwiftSingletons.register(self)
    }

    func setupWithRootWindow(_ rootWindow: UIWindow, screenBlockingWindow: UIWindow) {
        AssertIsOnMainThread()
        owsAssertBeta(self.rootWindow == nil)
        owsAssertBeta(self.screenBlockingWindow == nil)

        self.rootWindow = rootWindow
        self.screenBlockingWindow = screenBlockingWindow

        ensureWindowState()
    }

    func isAppWindow(_ window: UIWindow) -> Bool {
        return window == rootWindow || window == returnToCallWindow || window == callViewWindow || window == screenBlockingWindow
    }

    var isScreenBlockActive: Bool = false {
        didSet {
            AssertIsOnMainThread()
            ensureWindowState()
        }
    }

    func updateWindowFrames() {
        let desiredFrame = CurrentAppContext().frame
        for window in [ rootWindow!, callViewWindow, screenBlockingWindow! ] {
            guard window.frame != desiredFrame else { continue }
            window.frame = desiredFrame
        }
    }

    // MARK: Windows

    // UIWindow.Level.normal
    var rootWindow: UIWindow!

    // UIWindow.Level._returnToCall
    private lazy var returnToCallWindow: UIWindow = {
        AssertIsOnMainThread()
        guard let rootWindow else {
            owsFail("rootWindow is nil")
        }

        let window = OWSWindow(frame: rootWindow.bounds)
        window.windowLevel = ._returnToCall
        window.isHidden = true
        window.isOpaque = true
        window.clipsToBounds = true
        window.rootViewController = returnToCallViewController

        return window
    }()
    private lazy var returnToCallViewController = ReturnToCallViewController()

    // UIWindow.Level._callView
    lazy var callViewWindow: UIWindow = {
        AssertIsOnMainThread()
        guard let rootWindow else {
            owsFail("rootWindow is nil")
        }

        let window = OWSWindow(frame: rootWindow.bounds)
        window.windowLevel = ._callView
        window.isHidden = true
        window.isOpaque = true
        window.backgroundColor = Theme.launchScreenBackgroundColor
        window.rootViewController = callNavigationController

        return window

    }()
    private lazy var callNavigationController: UINavigationController = {
        let viewController = WindowRootViewController()
        viewController.view.backgroundColor = Theme.launchScreenBackgroundColor

        // NOTE: Do not use OWSNavigationController for call window.
        // It adjusts the size of the navigation bar to reflect the
        // call window.  We don't want those adjustments made within
        // the call window itself.
        let navigationController = WindowRootNavigationViewController(rootViewController: viewController)
        navigationController.isNavigationBarHidden = true
        return navigationController
    }()

    // UIWindow.Level._background if inactive,
    // UIWindow.Level._screenBlocking() if active.
    private var screenBlockingWindow: UIWindow!

    // MARK: Window State

    private func ensureWindowState() {
        AssertIsOnMainThread()

        // To avoid bad frames, we never want to hide the blocking window, so we manipulate
        // its window level to "hide" it behind other windows.  The other windows have fixed
        // window level and are shown/hidden as necessary.
        //
        // Note that we always "hide" before we "show".
        if isScreenBlockActive {
            ensureRootWindowHidden()
            ensureReturnToCallWindowHidden()
            ensureCallViewWindowHidden()
            ensureScreenBlockWindowShown()
        }
        // Show Call View
        else if shouldShowCallView && callViewController != nil {
            ensureRootWindowHidden()
            ensureCallViewWindowShown()
            ensureReturnToCallWindowHidden()
            ensureScreenBlockWindowHidden()
        }
        // Show Root Window
        else {
            ensureRootWindowShown()
            ensureScreenBlockWindowHidden()

            // Add "Return to Call" banner
            if callViewController != nil {
               ensureReturnToCallWindowShown()
            } else {
                ensureReturnToCallWindowHidden()
            }

            ensureCallViewWindowHidden()
        }
    }

    private func ensureRootWindowShown() {
        AssertIsOnMainThread()

        if rootWindow.isHidden {
            Logger.info("showing root window.")
        }

        // By calling makeKeyAndVisible we ensure the rootViewController becomes first responder.
        // In the normal case, that means the SignalViewController will call `becomeFirstResponder`
        // on the vc on top of its navigation stack.
        if !rootWindow.isKeyWindow || rootWindow.isHidden {
            rootWindow.makeKeyAndVisible()
        }

        fixit_workAroundRotationIssue(rootWindow)
    }

    private func ensureRootWindowHidden() {
        AssertIsOnMainThread()

        guard !rootWindow.isHidden else { return }

        Logger.info("hiding root window.")
        rootWindow.isHidden = true
    }

    private func ensureReturnToCallWindowShown() {
        AssertIsOnMainThread()

        guard returnToCallWindow.isHidden else { return }

        guard let callViewController else {
            owsFailBeta("callViewController is nil")
            return
        }

        Logger.info("showing 'return to call' window.")
        returnToCallWindow.isHidden = false
        returnToCallViewController.displayForCallViewController(callViewController)
    }

    private func ensureReturnToCallWindowHidden() {
        AssertIsOnMainThread()

        guard !returnToCallWindow.isHidden else { return }

        Logger.info("hiding 'return to call' window.")
        returnToCallWindow.isHidden = true
    }

    private func ensureCallViewWindowShown() {
        AssertIsOnMainThread()

        if callViewWindow.isHidden {
            Logger.info("showing call window.")
        }

        callViewWindow.makeKeyAndVisible()
    }

    private func ensureCallViewWindowHidden() {
        AssertIsOnMainThread()

        guard !callViewWindow.isHidden else { return }

        Logger.info("hiding call window.")
        callViewWindow.isHidden = true
    }

    private func ensureScreenBlockWindowShown() {
        AssertIsOnMainThread()

        if screenBlockingWindow.windowLevel != ._screenBlocking {
            Logger.info("showing block window.")
        }

        screenBlockingWindow.windowLevel = ._screenBlocking
        screenBlockingWindow.makeKeyAndVisible()
    }

    private func ensureScreenBlockWindowHidden() {
        AssertIsOnMainThread()

        guard screenBlockingWindow.windowLevel != ._background else { return }

        Logger.info("hiding block window.")

        // Never hide the blocking window (that can lead to bad frames).
        // Instead, manipulate its window level to move it in front of
        // or behind the root window.
        screenBlockingWindow.windowLevel = ._background
    }

    // MARK: Calls

    var shouldShowCallView: Bool = false

    var hasCall: Bool {
        AssertIsOnMainThread()
        return callViewController != nil
    }

    private var callViewController: CallViewControllerWindowReference?

    func startCall<T: UIViewController & CallViewControllerWindowReference>(viewController: T) {
        AssertIsOnMainThread()
        Logger.info("startCall")

        callViewController = viewController

        // Attach callViewController to window.
        callNavigationController.popToRootViewController(animated: false)
        callNavigationController.pushViewController(viewController, animated: false)

        shouldShowCallView = true

        // CallViewController only supports portrait for iPhones, but if we're _already_ landscape it won't
        // automatically switch.
        if !UIDevice.current.isIPad {
            UIDevice.current.ows_setOrientation(.portrait)
        }

        ensureWindowState()
    }

    func endCall<T: UIViewController & CallViewControllerWindowReference>(viewController: T) {
        AssertIsOnMainThread()

        guard callViewController === viewController else {
            Logger.warn("Ignoring end call request from obsolete call view controller.")
            return
        }

        callNavigationController.popViewController(animated: false)
        callViewController = nil

        shouldShowCallView = false

        ensureWindowState()
    }

    func leaveCallView() {
        AssertIsOnMainThread()

        owsAssertBeta(callViewController != nil)
        owsAssertBeta(shouldShowCallView)

        shouldShowCallView = false
        ensureWindowState()
    }

    func returnToCallView() {
        AssertIsOnMainThread()

        guard let callViewController else {
            owsFailBeta("callViewController == nil")
            return
        }

        guard !shouldShowCallView else {
            ensureWindowState()
            return
        }

        shouldShowCallView = true

        returnToCallViewController.resignCall()
        callViewController.returnFromPip(pipWindow: returnToCallWindow)

        ensureWindowState()
    }
}

// This VC can become first responder
// when presented to ensure that the input accessory is updated.
private class WindowRootViewController: UIViewController {

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.defaultSupportedOrientations
    }
}

private class WindowRootNavigationViewController: UINavigationController {

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.defaultSupportedOrientations
    }
}
