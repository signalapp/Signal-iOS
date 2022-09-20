// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import PromiseKit
import SignalCoreKit
import SignalUtilitiesKit
import SessionUIKit
import SessionUtilitiesKit

final class SAEScreenLockViewController: ScreenLockViewController {
    private var hasShownAuthUIOnce: Bool = false
    private var isShowingAuthUI: Bool = false
    
    private weak var shareViewDelegate: ShareViewDelegate?
    
    // MARK: - Initialization
    
    init(shareViewDelegate: ShareViewDelegate) {
        super.init()
        
        self.onUnlockPressed = { [weak self] in self?.unlockButtonWasTapped() }
        self.shareViewDelegate = shareViewDelegate
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        OWSLogger.verbose("Dealloc: \(type(of: self))")
    }
    
    // MARK: - UI
    
    private lazy var titleLabel: UILabel = {
        let titleLabel: UILabel = UILabel()
        titleLabel.font = UIFont.boldSystemFont(ofSize: Values.veryLargeFontSize)
        titleLabel.text = "vc_share_title".localized()
        titleLabel.themeTextColor = .textPrimary
        
        return titleLabel
    }()
    
    private lazy var closeButton: UIBarButtonItem = {
        let closeButton: UIBarButtonItem = UIBarButtonItem(image: UIImage(named: "X"), style: .plain, target: self, action: #selector(dismissPressed))
        closeButton.themeTintColor = .textPrimary
        
        return closeButton
    }()
    
    // MARK: - Lifecycle
    
    public override func loadView() {
        super.loadView()
        
        UIView.appearance().themeTintColor = .textPrimary
        
        self.view.themeBackgroundColor = .backgroundPrimary
        self.navigationItem.titleView = titleLabel
        self.navigationItem.leftBarButtonItem = closeButton
        
        ThemeManager.onThemeChange(observer: self.unlockButton) { [weak self] theme, _ in
            switch theme.interfaceStyle {
                case .light:
                    self?.unlockButton.setThemeTitleColorForced(.theme(theme, color: .textPrimary), for: .normal)
                    self?.unlockButton.setThemeBackgroundColorForced(
                        .theme(theme, color: .textPrimary),
                        for: .highlighted
                    )
                    self?.unlockButton.themeBorderColorForced = .theme(theme, color: .textPrimary)
                    
                default:
                    self?.unlockButton.setThemeTitleColorForced(.primary(.green), for: .normal)
                    self?.unlockButton.setThemeBackgroundColorForced(
                        .primary(.green, alpha: 0.3),
                        for: .highlighted
                    )
                    self?.unlockButton.themeBorderColorForced = .primary(.green)
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.ensureUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.ensureUI()
        
        // Auto-show the auth UI f
        if !hasShownAuthUIOnce {
            hasShownAuthUIOnce = true
            
            self.tryToPresentAuthUIToUnlockScreenLock()
        }
    }
    
    // MARK: - Functions
    
    private func tryToPresentAuthUIToUnlockScreenLock() {
        AssertIsOnMainThread()

        // If we're already showing the auth UI; abort.
        if self.isShowingAuthUI { return }
        
        OWSLogger.info("try to unlock screen lock")

        isShowingAuthUI = true
        
        ScreenLock.shared.tryToUnlockScreenLock(
            success: { [weak self] in
                AssertIsOnMainThread()
                OWSLogger.info("unlock screen lock succeeded.")
                
                self?.isShowingAuthUI = false
                self?.shareViewDelegate?.shareViewWasUnlocked()
            },
            failure: { [weak self] error in
                AssertIsOnMainThread()
                OWSLogger.info("unlock screen lock failed.")
                
                self?.isShowingAuthUI = false
                self?.ensureUI()
                self?.showScreenLockFailureAlert(message: error.localizedDescription)
            },
            unexpectedFailure: { [weak self] error in
                AssertIsOnMainThread()
                OWSLogger.info("unlock screen lock unexpectedly failed.")
                
                self?.isShowingAuthUI = false
                
                // Local Authentication isn't working properly.
                // This isn't covered by the docs or the forums but in practice
                // it appears to be effective to retry again after waiting a bit.
                DispatchQueue.main.async {
                    self?.ensureUI()
                }
            },
            cancel: { [weak self] in
                AssertIsOnMainThread()
                OWSLogger.info("unlock screen lock cancelled.")
                
                self?.isShowingAuthUI = false
                self?.ensureUI()
            }
        )
        
        self.ensureUI()
    }
    
    private func ensureUI() {
        self.updateUI(state: .lock, animated: false)
    }
    
    private func showScreenLockFailureAlert(message: String) {
        AssertIsOnMainThread()
        
        OWSAlerts.showAlert(
            // Title for alert indicating that screen lock could not be unlocked.
            title: "SCREEN_LOCK_UNLOCK_FAILED".localized(),
            message: message,
            buttonTitle: nil,
            buttonAction: { [weak self] action in
                // After the alert, update the UI
                self?.ensureUI()
            },
            fromViewController: self
        )
    }
    
    func unlockButtonWasTapped() {
        AssertIsOnMainThread()
        OWSLogger.info("unlockButtonWasTapped")
        
        self.tryToPresentAuthUIToUnlockScreenLock()
    }
    
    // MARK: - Transitions
    
    @objc private func dismissPressed() {
        OWSLogger.debug("unlock screen lock cancelled.")
        
        self.cancelShareExperience()
    }

    private func cancelShareExperience() {
        self.shareViewDelegate?.shareViewWasCancelled()
    }
}
