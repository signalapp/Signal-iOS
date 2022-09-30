// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

class ScreenLockUI {
    public static let shared: ScreenLockUI = ScreenLockUI()
    
    public lazy var screenBlockingWindow: UIWindow = {
        let result: UIWindow = UIWindow()
        result.isHidden = false
        result.windowLevel = ._Background
        result.isOpaque = true
        result.themeBackgroundColor = .backgroundPrimary
        result.rootViewController = self.screenBlockingViewController
        
        return result
    }()
    
    private lazy var screenBlockingViewController: ScreenLockViewController = {
        let result: ScreenLockViewController = ScreenLockViewController { [weak self] in
            guard self?.appIsInactiveOrBackground == false else {
                // This button can be pressed while the app is inactive
                // for a brief window while the iOS auth UI is dismissing.
                return
            }

            Logger.info("unlockButtonWasTapped")

            self?.didLastUnlockAttemptFail = false
            self?.ensureUI()
        }
        
        return result
    }()
    
    /// Unlike UIApplication.applicationState, this state reflects the notifications, i.e. "did become active", "will resign active",
    /// "will enter foreground", "did enter background".
    ///
    ///We want to update our state to reflect these transitions and have the "update" logic be consistent with "last reported"
    ///state. i.e. when you're responding to "will resign active", we need to behave as though we're already inactive.
    ///
    ///Secondly, we need to show the screen protection _before_ we become inactive in order for it to be reflected in the
    ///app switcher.
    private var appIsInactiveOrBackground: Bool = false {
        didSet {
            if self.appIsInactiveOrBackground {
                if !self.isShowingScreenLockUI {
                    self.didLastUnlockAttemptFail = false
                    self.tryToActivateScreenLockBasedOnCountdown()
                }
            }
            else if !self.didUnlockJustSucceed {
                self.tryToActivateScreenLockBasedOnCountdown()
            }
            
            self.didUnlockJustSucceed = false
            self.ensureUI()
        }
    }
    private var appIsInBackground: Bool = false {
        didSet {
            self.didUnlockJustSucceed = false
            self.tryToActivateScreenLockBasedOnCountdown()
            self.ensureUI()
        }
    }

    private var isShowingScreenLockUI: Bool = false
    private var didUnlockJustSucceed: Bool = false
    private var didLastUnlockAttemptFail: Bool = false

    /// We want to remain in "screen lock" mode while "local auth" UI is dismissing. So we lazily clear isShowingScreenLockUI
    /// using this property.
    private var shouldClearAuthUIWhenActive: Bool = false

    /// Indicates whether or not the user is currently locked out of the app.  Should only be set if db[.isScreenLockEnabled].
    ///
    /// * The user is locked out by default on app launch.
    /// * The user is also locked out if the app is sent to the background
    private var isScreenLockLocked: Bool = false
    
    // Determines what the state of the app should be.
    private var desiredUIState: ScreenLockViewController.State {
        if isScreenLockLocked {
            if appIsInactiveOrBackground {
                Logger.verbose("desiredUIState: screen protection 1.")
                return .protection
            }
            
            Logger.verbose("desiredUIState: screen lock 2.")
            return (isShowingScreenLockUI ? .protection : .lock)
        }

        if !self.appIsInactiveOrBackground {
            // App is inactive or background.
            Logger.verbose("desiredUIState: none 3.");
            return .none;
        }
        
        if Environment.shared?.isRequestingPermission == true {
            return .none;
        }
        
        Logger.verbose("desiredUIState: screen protection 4.")
        return .protection;
    }
    
    // MARK: - Lifecycle
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: .OWSApplicationWillResignActive,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: .OWSApplicationWillEnterForeground,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clockDidChange),
            name: .NSSystemClockDidChange,
            object: nil
        )
    }
    
    public func setupWithRootWindow(rootWindow: UIWindow) {
        self.screenBlockingWindow.frame = rootWindow.bounds
    }

    public func startObserving() {
        self.appIsInactiveOrBackground = (UIApplication.shared.applicationState != .active)

        self.observeNotifications()

        // Hide the screen blocking window until "app is ready" to
        // avoid blocking the loading view.
        updateScreenBlockingWindow(state: .none, animated: false)

        // Initialize the screen lock state.
        //
        // It's not safe to access OWSScreenLock.isScreenLockEnabled
        // until the app is ready.
        AppReadiness.runNowOrWhenAppWillBecomeReady { [weak self] in
            self?.isScreenLockLocked = Storage.shared[.isScreenLockEnabled]
            self?.ensureUI()
        }
    }
    
    // MARK: - Functions

    private func tryToActivateScreenLockBasedOnCountdown() {
        guard AppReadiness.isAppReady() else {
            // It's not safe to access OWSScreenLock.isScreenLockEnabled
            // until the app is ready.
            //
            // We don't need to try to lock the screen lock;
            // It will be initialized by `setupWithRootWindow`.
            Logger.verbose("tryToActivateScreenLockUponBecomingActive NO 0")
            return
        }
        guard Storage.shared[.isScreenLockEnabled] else {
            // Screen lock is not enabled.
            Logger.verbose("tryToActivateScreenLockUponBecomingActive NO 1")
            return;
        }
        guard !isScreenLockLocked else {
            // Screen lock is already activated.
            Logger.verbose("tryToActivateScreenLockUponBecomingActive NO 2")
            return;
        }
        
        self.isScreenLockLocked = true
    }
    
    /// Ensure that:
    ///
    /// * The blocking window has the correct state.
    /// * That we show the "iOS auth UI to unlock" if necessary.
    private func ensureUI() {
        guard AppReadiness.isAppReady() else {
            AppReadiness.runNowOrWhenAppWillBecomeReady { [weak self] in
                self?.ensureUI()
            }
            return
        }
        
        let desiredUIState: ScreenLockViewController.State = self.desiredUIState
        Logger.verbose("ensureUI: \(desiredUIState)")
        
        // Show the "iOS auth UI to unlock" if necessary.
        if desiredUIState == .lock && !didLastUnlockAttemptFail {
            tryToPresentAuthUIToUnlockScreenLock()
        }
        
        // Note: We want to regenerate the 'desiredUIState' as if we are about to show the
        // 'unlock screen' UI then we shouldn't show the "unlock" button
        updateScreenBlockingWindow(state: self.desiredUIState, animated: true)
    }

    private func tryToPresentAuthUIToUnlockScreenLock() {
        guard !isShowingScreenLockUI else { return }        // We're already showing the auth UI; abort
        guard !appIsInactiveOrBackground else { return }    // Never show the auth UI unless active
        
        Logger.info("try to unlock screen lock")
        isShowingScreenLockUI = true
        
        ScreenLock.shared.tryToUnlockScreenLock(
            success: { [weak self] in
                Logger.info("unlock screen lock succeeded.")
                self?.isShowingScreenLockUI = false
                self?.isScreenLockLocked = false
                self?.didUnlockJustSucceed = true
                self?.ensureUI()
            },
            failure: { [weak self] error in
                Logger.info("unlock screen lock failed.")
                self?.clearAuthUIWhenActive()
                self?.didLastUnlockAttemptFail = true
                self?.showScreenLockFailureAlert(message: error.localizedDescription)
            },
            unexpectedFailure: { [weak self] error in
                Logger.info("unlock screen lock unexpectedly failed.")

                // Local Authentication isn't working properly.
                // This isn't covered by the docs or the forums but in practice
                // it appears to be effective to retry again after waiting a bit.
                DispatchQueue.main.async {
                    self?.clearAuthUIWhenActive()
                }
            },
            cancel: { [weak self] in
                Logger.info("unlock screen lock cancelled.")

                self?.clearAuthUIWhenActive()
                self?.didLastUnlockAttemptFail = true

                // Re-show the unlock UI
                self?.ensureUI()
            }
        )
        
        self.ensureUI()
    }

    private func showScreenLockFailureAlert(message: String) {
        let modal: ConfirmationModal = ConfirmationModal(
            targetView: screenBlockingWindow.rootViewController?.view,
            info: ConfirmationModal.Info(
                title: "SCREEN_LOCK_UNLOCK_FAILED".localized(),
                explanation: message,
                cancelTitle: "BUTTON_OK".localized(),
                cancelStyle: .alert_text,
                afterClosed: { [weak self] in self?.ensureUI() } // After the alert, update the UI
            )
        )
        screenBlockingWindow.rootViewController?.present(modal, animated: true)
    }

    /// 'Screen Blocking' window obscures the app screen:
    ///
    /// * In the app switcher.
    /// * During 'Screen Lock' unlock process.
    private func createScreenBlockingWindow(rootWindow: UIWindow) {
        let window: UIWindow = UIWindow(frame: rootWindow.bounds)
        window.isHidden = false
        window.windowLevel = ._Background
        window.isOpaque = true
        window.themeBackgroundColor = .backgroundPrimary

        let viewController: ScreenLockViewController = ScreenLockViewController { [weak self] in
            guard self?.appIsInactiveOrBackground == false else {
                // This button can be pressed while the app is inactive
                // for a brief window while the iOS auth UI is dismissing.
                return
            }

            Logger.info("unlockButtonWasTapped")

            self?.didLastUnlockAttemptFail = false
            self?.ensureUI()
        }
        window.rootViewController = viewController

        self.screenBlockingWindow = window
        self.screenBlockingViewController = viewController
    }

    /// The "screen blocking" window has three possible states:
    ///
    /// * "Just a logo".  Used when app is launching and in app switcher.  Must match the "Launch Screen" storyboard pixel-for-pixel.
    /// * "Screen Lock, local auth UI presented". Move the Signal logo so that it is visible.
    /// * "Screen Lock, local auth UI not presented". Move the Signal logo so that it is visible, show "unlock" button.
    private func updateScreenBlockingWindow(state: ScreenLockViewController.State, animated: Bool) {
        let shouldShowBlockWindow: Bool = (state != .none)
        
        OWSWindowManager.shared().isScreenBlockActive = shouldShowBlockWindow
        self.screenBlockingViewController.updateUI(state: state, animated: animated)
    }

    // MARK: - Events
    
    private func clearAuthUIWhenActive() {
        // For continuity, continue to present blocking screen in "screen lock" mode while
        // dismissing the "local auth UI".
        if self.appIsInactiveOrBackground {
            self.shouldClearAuthUIWhenActive = true
        }
        else {
            self.isShowingScreenLockUI = false
            self.ensureUI()
        }
    }

    @objc private func applicationDidBecomeActive() {
        if self.shouldClearAuthUIWhenActive {
            self.shouldClearAuthUIWhenActive = false
            self.isShowingScreenLockUI = false
        }

        self.appIsInactiveOrBackground = false
    }

    @objc private func applicationWillResignActive() {
        self.appIsInactiveOrBackground = true
    }

    @objc private func applicationWillEnterForeground() {
        self.appIsInBackground = false
    }

    @objc private func applicationDidEnterBackground() {
        self.appIsInBackground = true
    }

    /// Whenever the device date/time is edited by the user, trigger screen lock immediately if enabled.
    @objc private func clockDidChange() {
        Logger.info("clock did change")

        guard AppReadiness.isAppReady() else {
            // It's not safe to access OWSScreenLock.isScreenLockEnabled
            // until the app is ready.
            //
            // We don't need to try to lock the screen lock;
            // It will be initialized by `setupWithRootWindow`.
            Logger.verbose("clockDidChange 0")
            return;
        }
        
        self.isScreenLockLocked = Storage.shared[.isScreenLockEnabled]

        // NOTE: this notifications fires _before_ applicationDidBecomeActive,
        // which is desirable.  Don't assume that though; call ensureUI
        // just in case it's necessary.
        self.ensureUI()
    }
}
