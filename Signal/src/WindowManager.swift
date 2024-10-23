//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
public import UIKit

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

    var captchaWindow: UIWindow {
        return shouldShowCallView ? callViewWindow : rootWindow
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
        window.rootViewController = nil

        return window

    }()

    private func newCallNavigationController() -> UINavigationController {
        let viewController = WindowRootViewController()
        viewController.view.backgroundColor = Theme.launchScreenBackgroundColor

        // NOTE: Do not use OWSNavigationController for call window.
        // It adjusts the size of the navigation bar to reflect the
        // call window.  We don't want those adjustments made within
        // the call window itself.
        let navigationController = WindowRootNavigationViewController(rootViewController: viewController)
        navigationController.isNavigationBarHidden = true
        return navigationController
    }

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
            ensureScreenBlockWindowShown()
            ensureRootWindowHidden()
            ensureReturnToCallWindowHidden()
            ensureCallViewWindowHidden()
        }
        // Show Call View
        else if shouldShowCallView && callViewController != nil {
            ensureCallViewWindowShown()
            ensureRootWindowHidden()
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

        workAroundRotationIssue(rootWindow)
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
        let callNavigationController = self.newCallNavigationController()
        self.callViewWindow.rootViewController = callNavigationController
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

        callViewWindow.rootViewController = nil
        callViewController = nil

        shouldShowCallView = false

        ensureWindowState()
    }

    func leaveCallView() {
        AssertIsOnMainThread()

        guard let callViewController else {
            owsFailBeta("callViewController == nil")
            return
        }
        owsAssertBeta(shouldShowCallView)

        callViewController.willMoveToPip(pipWindow: returnToCallWindow)

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

    var isCallInPip: Bool {
        return returnToCallViewController.isCallInPip
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

private func workAroundRotationIssue(_ window: UIWindow) {
    // ### Symptom
    //
    // The app can get into a degraded state where the main window will incorrectly remain locked in
    // portrait mode. Worse yet, the status bar and input window will continue to rotate with respect
    // to the device orientation. So once you're in this degraded state, the status bar and input
    // window can be in landscape while simultaneoulsy the view controller behind them is in portrait.
    //
    // ### To Reproduce
    //
    // On an iPhone6 (not reproducible on an iPhoneX)
    //
    // 0. Ensure "screen protection" is enabled (not necessarily screen lock)
    // 1. Enter Conversation View Controller
    // 2. Pop Keyboard
    // 3. Begin dismissing keyboard with one finger, but stopping when it's about 50% dismissed,
    //    keep your finger there with the keyboard partially dismissed.
    // 4. With your other hand, hit the home button to leave Signal.
    // 5. Re-enter Signal
    // 6. Rotate to landscape
    //
    // Expected: Conversation View, Input Toolbar window, and Settings Bar should all rotate to landscape.
    // Actual: The input toolbar and the settings toolbar rotate to landscape, but the Conversation
    //         View remains in portrait, this looks super broken.
    //
    // ### Background
    //
    // Some debugging shows that the `ConversationViewController.view.window.isInterfaceAutorotationDisabled`
    // is true. This is a private property, whose function we don't exactly know, but it seems like
    // `interfaceAutorotation` is disabled when certain transition animations begin, and then
    // re-enabled once the animation completes.
    //
    // My best guess is that autorotation is intended to be disabled for the duration of the
    // interactive-keyboard-dismiss-transition, so when we start the interactive dismiss, autorotation
    // has been disabled, but because we hide the main app window in the middle of the transition,
    // autorotation doesn't have a chance to be re-enabled.
    //
    // ## So, The Fix
    //
    // If we find ourself in a situation where autorotation is disabled while showing the rootWindow,
    // we re-enable autorotation.

    // let encodedSelectorString1 = "isInterfaceAutorotationDisabled".encodedForSelector
    let encodedSelectorString1 = "egVaAAZ2BHdydHZSBwYBBAEGcgZ6AQBVegVyc312dQ=="
    guard let selectorString1 = encodedSelectorString1.decodedForSelector else {
        owsFailDebug("selectorString1 was unexpectedly nil")
        return
    }
    let selector1 = NSSelectorFromString(selectorString1)

    guard window.responds(to: selector1) else {
        owsFailDebug("failure: doesn't respond to selector1")
        return
    }
    let imp1 = window.method(for: selector1)
    typealias Selector1MethodType = @convention(c) (UIWindow, Selector) -> Bool
    let func1: Selector1MethodType = unsafeBitCast(imp1, to: Selector1MethodType.self)
    let isDisabled = func1(window, selector1)

    guard isDisabled else {
        return
    }

    Logger.info("autorotation is disabled.")

    // The remainder of this method calls:
    //   [[UIScrollToDismissSupport supportForScreen:window.screen] finishScrollViewTransition]
    // after verifying the methods/classes exist.

    // let encodedKlassString = "UIScrollToDismissSupport".encodedForSelector
    let encodedKlassString = "ZlpkdAQBfX1lAVV6BX56BQVkBwICAQQG"
    guard let klassString = encodedKlassString.decodedForSelector else {
        owsFailDebug("klassString was unexpectedly nil")
        return
    }
    guard let klass = NSClassFromString(klassString) else {
        owsFailDebug("klass was unexpectedly nil")
        return
    }

    // let encodedSelector2String = "supportForScreen:".encodedForSelector
    let encodedSelector2String = "BQcCAgEEBlcBBGR0BHZ2AEs="
    guard let selector2String = encodedSelector2String.decodedForSelector else {
        owsFailDebug("selector2String was unexpectedly nil")
        return
    }
    let selector2 = NSSelectorFromString(selector2String)
    guard klass.responds(to: selector2) else {
        owsFailDebug("klass didn't respond to selector")
        return
    }
    let imp2 = klass.method(for: selector2)
    typealias Selector2MethodType = @convention(c) (AnyClass, Selector, UIScreen) -> AnyObject?
    let func2: Selector2MethodType = unsafeBitCast(imp2, to: Selector2MethodType.self)
    guard let dismissSupport = func2(klass, selector2, window.screen) else {
        owsFailDebug("selector2String call unexpectedly returned nil")
        return
    }

    // let encodedSelector3String = "finishScrollViewTransition".encodedForSelector
    let encodedSelector3String = "d3oAegV5ZHQEAX19Z3p2CWUEcgAFegZ6AQA="
    guard let selector3String = encodedSelector3String.decodedForSelector else {
        owsFailDebug("selector3String was unexpectedly nil")
        return
    }
    let selector3 = NSSelectorFromString(selector3String)
    guard dismissSupport.responds(to: selector3) else {
        owsFailDebug("dismissSupport didn't respond to selector")
        return
    }
    let imp3 = dismissSupport.method(for: selector3)
    typealias Selector3MethodType = @convention(c) (AnyObject, Selector) -> Void
    let func3: Selector3MethodType = unsafeBitCast(imp3, to: Selector3MethodType.self)
    func3(dismissSupport, selector3)

    Logger.info("finished scrollView transition")
}
