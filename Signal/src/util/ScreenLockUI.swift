//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

class ScreenLockUI {

    static let shared = ScreenLockUI()

    // Unlike UIApplication.applicationState, this state reflects the
    // notifications, i.e. "did become active", "will resign active",
    // "will enter foreground", "did enter background".
    //
    // We want to update our state to reflect these transitions and have
    // the "update" logic be consistent with "last reported" state. i.e.
    // when you're responding to "will resign active", we need to behave
    // as though we're already inactive.
    //
    // Secondly, we need to show the screen protection _before_ we become
    // inactive in order for it to be reflected in the app switcher.
    private var appIsInactiveOrBackground: Bool = false {
        didSet {
            AssertIsOnMainThread()

            if appIsInactiveOrBackground {
                if !isShowingScreenLockUI {
                    startScreenLockCountdownIfNecessary()
                }
            } else {
                tryToActivateScreenLockBasedOnCountdown()

                Logger.info("setAppIsInactiveOrBackground clear screenLockCountdownTimestamp.")
                screenLockCountdownTimestamp = nil
            }

            ensureUI()
        }
    }
    private var appIsInBackground: Bool = false {
        didSet {
            AssertIsOnMainThread()

            if appIsInBackground {
                startScreenLockCountdownIfNecessary()
            } else {
                tryToActivateScreenLockBasedOnCountdown()
            }

            ensureUI()
        }
    }

    private var isShowingScreenLockUI: Bool = false
    private var didLastUnlockAttemptFail: Bool = false

    // We want to remain in "screen lock" mode while "local auth"
    // UI is dismissing. So we lazily clear isShowingScreenLockUI
    // using this property.
    private var shouldClearAuthUIWhenActive: Bool = false

    // Indicates whether or not the user is currently locked out of
    // the app.  Should only be set if OWSScreenLock.isScreenLockEnabled.
    //
    // * The user is locked out by default on app launch.
    // * The user is also locked out if they spend more than
    //   "timeout" seconds outside the app.  When the user leaves
    //   the app, a "countdown" begins.
    private var isScreenLockLocked: Bool = false

    // The "countdown" until screen lock takes effect.
    private var screenLockCountdownTimestamp: UInt64?

    lazy var screenBlockingWindow: UIWindow = {
        let window = OWSWindow(frame: .zero)
        window.isHidden = false
        window.windowLevel = ._Background
        window.isOpaque = true
        window.backgroundColor = Theme.launchScreenBackground
        return window
    }()
    private lazy var screenBlockingViewController: ScreenLockViewController = {
        let viewController = ScreenLockViewController()
        viewController.delegate = self
        return viewController
    }()

    private init() {
        AssertIsOnMainThread()
    }

    // MARK: - Public

    func setupWithRootWindow(_ rootWindow: UIWindow) {
        AssertIsOnMainThread()

        createScreenBlockingWindowWithRootWindow(rootWindow)
    }

    func startObserving() {
        appIsInactiveOrBackground = UIApplication.shared.applicationState != .active

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSNotification.Name.OWSApplicationDidBecomeActive,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: NSNotification.Name.OWSApplicationWillResignActive,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: NSNotification.Name.OWSApplicationWillEnterForeground,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: NSNotification.Name.OWSApplicationDidEnterBackground,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenLockDidChange),
            name: ScreenLock.ScreenLockDidChange,
            object: nil)

        // Hide the screen blocking window until "app is ready" to
        // avoid blocking the loading view.
        updateScreenBlockingWindowWithUIState(.none, animated: false)

        // Initialize the screen lock state.
        //
        // It's not safe to access OWSScreenLock.isScreenLockEnabled
        // until the app is ready.
        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.isScreenLockLocked = ScreenLock.shared.isScreenLockEnabled()
            self.ensureUI()
        }
    }

    // MARK: - UI

    // The "screen blocking" window has three possible states:
    //
    // * "Just a logo".  Used when app is launching and in app switcher.  Must match the "Launch Screen"
    //    storyboard pixel-for-pixel.
    // * "Screen Lock, local auth UI presented". Move the Signal logo so that it is visible.
    // * "Screen Lock, local auth UI not presented". Move the Signal logo so that it is visible,
    //    show "unlock" button.
    private func updateScreenBlockingWindowWithUIState(_ uiState: ScreenLockViewController.UIState, animated: Bool) {
        AssertIsOnMainThread()

        let shouldShowBlockWindow = uiState != .none

        OWSWindowManager.shared.isScreenBlockActive = shouldShowBlockWindow

        screenBlockingViewController.updateUIWithState(
            uiState,
            isLogoAtTop: isShowingScreenLockUI,
            animated: animated
        )
    }

    // 'Screen Blocking' window obscures the app screen:
    //
    // * In the app switcher.
    // * During 'Screen Lock' unlock process.
    private func createScreenBlockingWindowWithRootWindow(_ rootWindow: UIWindow) {
        AssertIsOnMainThread()

        screenBlockingWindow.frame = rootWindow.bounds
        screenBlockingWindow.rootViewController = screenBlockingViewController
    }

    // Ensure that:
    //
    // * The blocking window has the correct state.
    // * That we show the "iOS auth UI to unlock" if necessary.
    private func ensureUI() {
        AssertIsOnMainThread()

        guard AppReadiness.isAppReady else {
            AppReadiness.runNowOrWhenAppWillBecomeReady {
                self.ensureUI()
            }
            return
        }

        let desiredUIState = desiredUIState()
        Logger.verbose("Ensure UI: \(desiredUIState)")

        updateScreenBlockingWindowWithUIState(desiredUIState, animated: true)

        // Show the "iOS auth UI to unlock" if necessary.
        if desiredUIState == .screenLock && !didLastUnlockAttemptFail {
            tryToPresentAuthUIToUnlockScreenLock()
        }
    }

    private func clearAuthUIWhenActive() {
        // For continuity, continue to present blocking screen in "screen lock" mode while
        // dismissing the "local auth UI".
        if appIsInactiveOrBackground {
            shouldClearAuthUIWhenActive = true
        } else {
            isShowingScreenLockUI = false
            ensureUI()
        }
    }

    private func desiredUIState() -> ScreenLockViewController.UIState {
        if isScreenLockLocked {
            if appIsInactiveOrBackground {
                Logger.verbose("desiredUIState: screen protection 1.")
                return .screenProtection
            } else {
                Logger.verbose("desiredUIState: screen lock 2.")
                return .screenLock
            }
        }

        guard appIsInactiveOrBackground else {
            Logger.verbose("desiredUIState: none 3.")
            return .none
        }

        guard Environment.shared.preferences.screenSecurityIsEnabled() else {
            Logger.verbose("desiredUIState: none 5.")
            return .none
        }

        Logger.verbose("desiredUIState: screen protection 4.")
        return .screenProtection
    }

    private func tryToPresentAuthUIToUnlockScreenLock() {
        AssertIsOnMainThread()

        guard !isShowingScreenLockUI else {
            // We're already showing the auth UI; abort.
            return
        }

        guard !appIsInactiveOrBackground else {
            // Never show the auth UI unless active.
            return
        }

        Logger.info("try to unlock screen lock")

        isShowingScreenLockUI = true

        ScreenLock.shared.tryToUnlockScreenLock(
            success: {
                Logger.info("unlock screen lock succeeded.")

                self.isShowingScreenLockUI = false
                self.isScreenLockLocked = false
                self.ensureUI()
            },
            failure: { error in
                Logger.info("unlock screen lock failed.")

                self.clearAuthUIWhenActive()
                self.didLastUnlockAttemptFail = true
                self.showScreenLockFailureAlertWithMessage(error.userErrorDescription)
            },
            unexpectedFailure: { error in
                Logger.info("unlock screen lock unexpectedly failed.")

                // Local Authentication isn't working properly.
                // This isn't covered by the docs or the forums but in practice
                // it appears to be effective to retry again after waiting a bit.
                DispatchQueue.main.async {
                    self.clearAuthUIWhenActive()
                }
            },
            cancel: {
                Logger.info("unlock screen lock cancelled.")

                self.clearAuthUIWhenActive()
                self.didLastUnlockAttemptFail = true
                // Re-show the unlock UI.
                self.ensureUI()
            }
        )

        ensureUI()
    }

    private func showScreenLockFailureAlertWithMessage(_ message: String) {
        AssertIsOnMainThread()

        OWSActionSheets.showActionSheet(
            title: OWSLocalizedString(
                "SCREEN_LOCK_UNLOCK_FAILED",
                comment: "Title for alert indicating that screen lock could not be unlocked."
            ),
            message: message,
            buttonAction: { _ in
                // After the alert, update the UI.
                self.ensureUI()
            },
            fromViewController: screenBlockingWindow.rootViewController
        )
    }

    // MARK: -

    private func tryToActivateScreenLockBasedOnCountdown() {
        owsAssertBeta(!appIsInBackground)
        AssertIsOnMainThread()

        guard AppReadiness.isAppReady else {
            // It's not safe to access OWSScreenLock.isScreenLockEnabled
            // until the app is ready.
            //
            // We don't need to try to lock the screen lock;
            // It will be initialized by `setupWithRootWindow`.
            Logger.verbose("tryToActivateScreenLockUponBecomingActive NO 0")
            return
        }

        guard ScreenLock.shared.isScreenLockEnabled() else {
            // Screen lock is not enabled.
            Logger.verbose("tryToActivateScreenLockUponBecomingActive NO 1")
            return
        }

        guard !isScreenLockLocked else {
            // Screen lock is already activated.
            Logger.verbose("tryToActivateScreenLockUponBecomingActive NO 2")
            return
        }

        guard let screenLockCountdownTimestamp else {
            // We became inactive, but never started a countdown.
            Logger.verbose("tryToActivateScreenLockUponBecomingActive NO 3")
            return
        }

        let countdownTimestamp = screenLockCountdownTimestamp
        let currentTimestamp = monotonicTimestamp()
        guard currentTimestamp >= countdownTimestamp && currentTimestamp != 0 && countdownTimestamp != 0 else {
            // If the clock is going backwards (shouldn't happen) or the
            // initial/current time couldn't be fetched (shouldn't happen), err on the
            // side of caution and lock the screen.
            owsFailDebug("monotonic time isn't behaving properly")
            Logger.verbose("tryToActivateScreenLockUponBecomingActive YES 4 (\(countdownTimestamp), \(currentTimestamp))")
            isScreenLockLocked = true
            return
        }

        let countdownInterval = TimeInterval(currentTimestamp - countdownTimestamp) / TimeInterval(NSEC_PER_SEC)
        let screenLockTimeout = ScreenLock.shared.screenLockTimeout()
        owsAssertDebug(screenLockTimeout >= 0)
        if countdownInterval >= screenLockTimeout {
            isScreenLockLocked = true

            Logger.verbose("tryToActivateScreenLockUponBecomingActive YES 5 (\(countdownInterval) >= \(screenLockTimeout))")
        } else {
            Logger.verbose("tryToActivateScreenLockUponBecomingActive NO 6 (\(countdownInterval) < \(screenLockTimeout))")
        }
    }

    private func monotonicTimestamp() -> UInt64 {
        let result = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        if result == 0 {
            Logger.warn("couldn't get monotonic time \(errno)")
        }
        return result
    }

    private func startScreenLockCountdownIfNecessary() {
        Logger.verbose("startScreenLockCountdownIfNecessary: \(screenLockCountdownTimestamp != nil)")

        if screenLockCountdownTimestamp == nil {
            Logger.info("startScreenLockCountdown.")
            screenLockCountdownTimestamp = monotonicTimestamp()
        }

        didLastUnlockAttemptFail = false
    }

    // MARK: - Notification Observers

    @objc
    private func screenLockDidChange(_ notification: Notification) {
        ensureUI()
    }

    @objc
    private func applicationDidBecomeActive(_ notification: Notification) {
        if shouldClearAuthUIWhenActive {
            shouldClearAuthUIWhenActive = false
            isShowingScreenLockUI = false
        }
        appIsInactiveOrBackground = false
    }

    @objc
    private func applicationWillResignActive(_ notification: Notification) {
        appIsInactiveOrBackground = true
    }

    @objc
    private func applicationWillEnterForeground(_ notification: Notification) {
        appIsInBackground = false
    }

    @objc
    private func applicationDidEnterBackground(_ notification: Notification) {
        appIsInBackground = true
    }
}

extension ScreenLockUI: ScreenLockViewDelegate {

    func unlockButtonWasTapped() {
        AssertIsOnMainThread()

        guard !appIsInactiveOrBackground else {
            // This button can be pressed while the app is inactive
            // for a brief window while the iOS auth UI is dismissing.
            return
        }

        Logger.info("unlockButtonWasTapped")

        didLastUnlockAttemptFail = false
        ensureUI()
    }
}
