//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

@objc
public class Deprecated_OnboardingCaptchaViewController: Deprecated_OnboardingBaseViewController {

    let viewModel = Deprecated_RegistrationCaptchaViewModel()

    override public func loadView() {
        viewModel.viewController = self

        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        viewModel.createViews(vc: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.captchaView.loadCaptcha()
    }
}

// MARK: -

extension Deprecated_OnboardingCaptchaViewController: Deprecated_RegistrationCaptchaViewController {

    func requestCaptchaVerification(captchaToken: String) {
        AssertIsOnMainThread()

        Logger.info("")

        onboardingController.update(captchaToken: captchaToken)

        let viewModel = self.viewModel
        let progressView = viewModel.addProgressView()

        onboardingController.requestVerification(fromViewController: self, isSMS: true) { [weak self] willDismiss, _ in
            if !willDismiss {
                // There's nothing left to do here. If onboardingController isn't taking us anywhere, let's
                // just pop back to the phone number verification controller
                self?.navigationController?.popViewController(animated: true)
            }
            viewModel.removeProgressView(progressView)
        }
    }
}
