//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import UIKit

public protocol ScreenLockViewDelegate: AnyObject {
    func unlockButtonWasTapped()
}

open class ScreenLockViewController: UIViewController {

    public enum UIState: CustomStringConvertible {
        case none
        case screenProtection // Shown while app is inactive or background, if enabled.
        case screenLock // Shown while app is active, if enabled.

        public var description: String {
            switch self {
            case .none:
                return "ScreenLockUIStateNone"
            case .screenProtection:
                return "ScreenLockUIStateScreenProtection"
            case .screenLock:
                return "ScreenLockUIStateScreenLock"
            }
        }
    }

    public weak var delegate: ScreenLockViewDelegate?

    // MARK: - UI

    private var screenBlockingSignature: String?
    private var layoutConstraints: [NSLayoutConstraint]?
    private lazy var imageViewLogo = UIImageView(image: UIImage(named: "signal-logo-128-launch-screen"))
    private static var buttonHeight: CGFloat { 40 }
    private lazy var buttonUnlockUI = OWSFlatButton.button(
        title: OWSLocalizedString(
            "SCREEN_LOCK_UNLOCK_SIGNAL",
            comment: "Label for button on lock screen that lets users unlock Signal."
        ),
        font: OWSFlatButton.fontForHeight(ScreenLockViewController.buttonHeight),
        titleColor: Theme.accentBlueColor,
        backgroundColor: .white,
        target: self,
        selector: #selector(unlockUIButtonTapped)
    )

    open override func loadView() {
        super.loadView()

        view.backgroundColor = Theme.launchScreenBackgroundColor

        view.addSubview(imageViewLogo)
        imageViewLogo.autoHCenterInSuperview()
        imageViewLogo.autoSetDimensions(to: .square(128))

        view.addSubview(buttonUnlockUI)
        buttonUnlockUI.autoSetDimension(.height, toSize: ScreenLockViewController.buttonHeight)
        buttonUnlockUI.autoPinWidthToSuperview(withMargin: 50)
        buttonUnlockUI.autoPinBottomToSuperviewMargin(withInset: 65)

        updateUIWithState(.screenProtection, isLogoAtTop: false, animated: false)

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .themeDidChange, object: nil)
    }

    // The "screen blocking" window has three possible states:
    //
    // * "Just a logo".  Used when app is launching and in app switcher.  Must match the "Launch Screen"
    //    storyboard pixel-for-pixel.
    // * "Screen Lock, local auth UI presented". Move the Signal logo so that it is visible.
    // * "Screen Lock, local auth UI not presented". Move the Signal logo so that it is visible,
    //    show "unlock" button.
    public func updateUIWithState(_ uiState: UIState, isLogoAtTop: Bool, animated: Bool) {
        AssertIsOnMainThread()

        guard isViewLoaded else { return }

        let shouldShowBlockWindow = uiState != .none
        let shouldHaveScreenLock = uiState == .screenLock

        imageViewLogo.isHidden = !shouldShowBlockWindow
        buttonUnlockUI.isHidden = !shouldHaveScreenLock

        // Skip redundant work to avoid interfering with ongoing animations.
        let screenBlockingSignature = "\(shouldHaveScreenLock) \(isLogoAtTop)"
        guard self.screenBlockingSignature != screenBlockingSignature else { return }

        if let layoutConstraints {
            NSLayoutConstraint.deactivate(layoutConstraints)
        }

        let layoutConstraints: [NSLayoutConstraint]
        if isLogoAtTop {
            layoutConstraints = [
                imageViewLogo.autoPinEdge(toSuperviewEdge: .top, withInset: 60)
            ]
        } else {
            layoutConstraints = [
                imageViewLogo.autoVCenterInSuperview()
            ]
        }

        self.layoutConstraints = layoutConstraints
        self.screenBlockingSignature = screenBlockingSignature

        if animated {
            UIView.animate(withDuration: 0.35) {
                self.view.layoutIfNeeded()
            }
        } else {
            view.layoutIfNeeded()
        }
    }

    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.defaultSupportedOrientations
    }

    @objc
    private func themeDidChange() {
        view.backgroundColor = Theme.launchScreenBackgroundColor
    }

    @objc
    private func unlockUIButtonTapped(_ sender: Any) {
        delegate?.unlockButtonWasTapped()
    }
}
