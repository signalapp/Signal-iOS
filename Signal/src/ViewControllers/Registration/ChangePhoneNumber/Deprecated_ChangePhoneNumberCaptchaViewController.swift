//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalServiceKit
import SignalUI

// Most of the logic for the verification views resides in RegistrationCaptchaViewController.
public class Deprecated_ChangePhoneNumberCaptchaViewController: Deprecated_RegistrationBaseViewController {

    private let changePhoneNumberController: Deprecated_ChangePhoneNumberController
    private let oldPhoneNumber: PhoneNumber
    private let newPhoneNumber: PhoneNumber

    let viewModel = Deprecated_RegistrationCaptchaViewModel()

    init(changePhoneNumberController: Deprecated_ChangePhoneNumberController,
         oldPhoneNumber: PhoneNumber,
         newPhoneNumber: PhoneNumber) {
        self.changePhoneNumberController = changePhoneNumberController
        self.oldPhoneNumber = oldPhoneNumber
        self.newPhoneNumber = newPhoneNumber

        super.init()

        viewModel.viewController = self
    }

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()
        view.backgroundColor = Theme.backgroundColor

        viewModel.createViews(vc: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.captchaView.loadCaptcha()
    }
}

// MARK: -

extension Deprecated_ChangePhoneNumberCaptchaViewController: Deprecated_RegistrationCaptchaViewController {

    func requestCaptchaVerification(captchaToken: String) {
        AssertIsOnMainThread()

        Logger.info("")

        changePhoneNumberController.captchaToken = captchaToken

        let viewModel = self.viewModel
        let progressView = viewModel.addProgressView()

        changePhoneNumberController.requestVerification(fromViewController: self, isSMS: true) { [weak self] willDismiss, _ in

            if let self = self, !willDismiss {
                // There's nothing left to do here. If onboardingController isn't taking us
                // anywhere, let's just pop back to the phone number confirm controller
                self.navigationController?.popViewController(animated: true)
            }
            viewModel.removeProgressView(progressView)
        }
    }
}
