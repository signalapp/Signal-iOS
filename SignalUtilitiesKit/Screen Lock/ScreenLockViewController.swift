// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

open class ScreenLockViewController: UIViewController {
    public enum State {
        case none
        
        /// Shown while app is inactive or background, if enabled.
        case protection
        
        /// Shown while app is active, if enabled.
        case lock
    }
    
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return ThemeManager.currentTheme.statusBarStyle
    }
    
    public override var canBecomeFirstResponder: Bool { true }
    
    public var onUnlockPressed: (() -> ())?
    private var screenBlockingSignature: String?
    
    // MARK: - UI
    
    private let logoView: UIImageView = {
        let result: UIImageView = UIImageView(image: #imageLiteral(resourceName: "SessionGreen64"))
        result.contentMode = .scaleAspectFit
        result.isHidden = true
        
        return result
    }()
    
    public lazy var unlockButton: OutlineButton = {
        let result: OutlineButton = OutlineButton(style: .regular, size: .medium)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.setTitle("Unlock Session", for: .normal)
        result.addTarget(self, action: #selector(showUnlockUI), for: .touchUpInside)
        result.isHidden = true
        
        // Need to match the launch screen so force the styling to be the primary green
        result.setThemeTitleColorForced(.primary(.green), for: .normal)
        result.setThemeBackgroundColorForced(.primary(.green), for: .highlighted)
        result.themeBorderColorForced = .primary(.green)

        return result
    }()
    
    // MARK: - Lifecycle
                                  
    public init(onUnlockPressed: (() -> ())? = nil) {
        self.onUnlockPressed = onUnlockPressed
        
        super.init(nibName: nil, bundle: nil)
    }
                                  
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
                                  
    open override func loadView() {
        super.loadView()
        
        view.themeBackgroundColor = .black  // Need to match the Launch screen

        let edgesView: UIView = UIView.container()
        self.view.addSubview(edgesView)
        edgesView.pin(to: view)
        
        edgesView.addSubview(logoView)
        logoView.center(in: edgesView)
        logoView.set(.width, to: 64)
        logoView.set(.height, to: 64)

        edgesView.addSubview(unlockButton)
        unlockButton.pin(.top, to: .bottom, of: logoView, withInset: Values.mediumSpacing)
        unlockButton.center(.horizontal, in: view)
        
        updateUI(state: .protection, animated: false)
    }
    
    /// The "screen blocking" window has three possible states:
    ///
    /// * "Just a logo".  Used when app is launching and in app switcher.  Must match the "Launch Screen" storyboard pixel-for-pixel.
    /// * "Screen Lock, local auth UI presented". Must match the "Launch Screen" storyboard pixel-for-pixel.
    /// * "Screen Lock, local auth UI not presented". Show "unlock" button.
    public func updateUI(state: State, animated: Bool) {
        guard isViewLoaded else { return }

        let shouldShowBlockWindow: Bool = (state != .none)
        let shouldHaveScreenLock: Bool = (state == .lock)

        self.logoView.isHidden = !shouldShowBlockWindow

        let signature: String = String(format: "%d", shouldHaveScreenLock)
        
        // Skip redundant work to avoid interfering with ongoing animations
        guard signature != self.screenBlockingSignature else { return }
        
        self.unlockButton.isHidden = !shouldHaveScreenLock
        self.screenBlockingSignature = signature

        guard animated else {
            self.view.setNeedsLayout()
            return
        }
        
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.view.layoutIfNeeded()
        }
    }
    
    @objc private func showUnlockUI() {
        self.onUnlockPressed?()
    }
}
