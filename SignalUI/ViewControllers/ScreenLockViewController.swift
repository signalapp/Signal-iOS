//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

@MainActor
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

    private lazy var imageViewLogo = UIImageView(image: UIImage(named: "signal-logo-128-launch-screen"))
    private static var buttonHeight: CGFloat { 40 }
    private lazy var buttonUnlockUI = UIButton(
        configuration: .largePrimary(title: OWSLocalizedString(
            "SCREEN_LOCK_UNLOCK_SIGNAL",
            comment: "Label for button on lock screen that lets users unlock Signal.",
        )),
        primaryAction: UIAction { [weak self] _ in
            self?.unlockUIButtonTapped()
        },
    )

    override open func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.Signal.background

        view.addSubview(imageViewLogo)
        imageViewLogo.autoHCenterInSuperview()
        imageViewLogo.autoVCenterInSuperview()
        imageViewLogo.autoSetDimensions(to: .square(128))

        buttonUnlockUI.configuration?.baseForegroundColor = .Signal.label
        buttonUnlockUI.configuration?.baseBackgroundColor = .Signal.tertiaryFill
        view.addSubview(buttonUnlockUI)
        buttonUnlockUI.autoPinWidthToSuperview(withMargin: 50)
        buttonUnlockUI.autoPinBottomToSuperviewMargin(withInset: 65)

        updateUIWithState(.screenProtection)
    }

    // The "screen blocking" window has three possible states:
    //
    // * "Just a logo". Used when app is launching and in app switcher. Must
    // match the "Launch Screen" storyboard pixel-for-pixel.
    //
    // * "Screen Lock, local auth UI presented".
    //
    // * "Screen Lock, local auth UI not presented". Show "unlock" button.
    public func updateUIWithState(_ uiState: UIState) {
        AssertIsOnMainThread()

        guard isViewLoaded else { return }

        let shouldShowBlockWindow = uiState != .none
        let shouldHaveScreenLock = uiState == .screenLock

        imageViewLogo.isHidden = !shouldShowBlockWindow
        buttonUnlockUI.isHidden = !shouldHaveScreenLock
    }

    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.defaultSupportedOrientations
    }

    private func unlockUIButtonTapped() {
        delegate?.unlockButtonWasTapped()
    }
}

#if DEBUG

@available(iOS 17, *)
#Preview("State: none") {
    let vc = ScreenLockViewController()
    vc.view.isHidden = false // force view to load
    vc.updateUIWithState(.none)
    return vc
}

@available(iOS 17, *)
#Preview("State: screenProtection") {
    let vc = ScreenLockViewController()
    vc.view.isHidden = false // force view to load
    vc.updateUIWithState(.screenLock)
    return vc
}

@available(iOS 17, *)
#Preview("State: screenLock") {
    let vc = ScreenLockViewController()
    vc.view.isHidden = false // force view to load
    vc.updateUIWithState(.screenProtection)
    return vc
}

#endif
