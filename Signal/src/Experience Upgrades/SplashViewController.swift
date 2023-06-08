//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

public class SplashViewController: OWSViewController, ExperienceUpgradeView {

    // MARK: -

    let experienceUpgrade: ExperienceUpgrade
    var canDismissWithGesture: Bool { return true }
    var isPresented: Bool { presentingViewController != nil }
    var isReadyToComplete: Bool { true }

    init(experienceUpgrade: ExperienceUpgrade) {
        self.experienceUpgrade = experienceUpgrade
        super.init()
    }

    // MARK: - View lifecycle

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Don't allow interactive dismissal.
        presentationController?.delegate = self
        isModalInPresentation = !canDismissWithGesture
    }

    // MARK: -

    var isDismissWithoutCompleting = false
    public func dismissWithoutCompleting(animated flag: Bool, completion: (() -> Void)? = nil) {
        isDismissWithoutCompleting = true
        dismiss(animated: flag, completion: completion)
    }

    public override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) {
            self.didDismiss()
            completion?()
        }
    }

    private func didDismiss() {
        Logger.debug("")

        // Only complete on dismissal if we're ready to do so. This is by
        // default always true, but can be overridden on an individual basis.
        guard isReadyToComplete, !isDismissWithoutCompleting else { return }

        markAsCompleteWithSneakyTransaction()
    }

    @objc
    private func didTapDismissButton(sender: UIButton) {
        self.dismiss(animated: true)
    }

    @objc
    private func handleDismissGesture(sender: AnyObject) {
        guard canDismissWithGesture else { return }

        Logger.debug("")
        self.dismiss(animated: true)
    }

    // MARK: Orientation

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }
}

extension SplashViewController: UIAdaptivePresentationControllerDelegate {
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        didDismiss()
    }
}
