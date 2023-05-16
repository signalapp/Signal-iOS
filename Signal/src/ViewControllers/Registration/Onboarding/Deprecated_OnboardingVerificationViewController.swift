//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalCoreKit

// Most of the logic for the verification views resides in RegistrationVerificationViewController.
public class Deprecated_OnboardingVerificationViewController: Deprecated_OnboardingBaseViewController {

    let viewModel = Deprecated_RegistrationVerificationViewModel()

    override public func loadView() {
        viewModel.viewController = self

        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()
        view.backgroundColor = Theme.backgroundColor

        viewModel.createViews(vc: self)
    }

    // MARK: - View Lifecycle

    public override init(onboardingController: Deprecated_OnboardingController) {
        super.init(onboardingController: onboardingController)

        keyboardObservationBehavior = .whileLifecycleVisible
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        verificationCodeView.becomeFirstResponder()
    }

    public override func keyboardFrameDidChange(_ newFrame: CGRect, animationDuration: TimeInterval, animationOptions: UIView.AnimationOptions) {
        super.keyboardFrameDidChange(newFrame, animationDuration: animationDuration, animationOptions: animationOptions)
        let isDismissing = newFrame.height == 0

        if isDismissing, equalSpacerHeightConstraint?.isActive == true {
            pinnedSpacerHeightConstraint?.constant = backButtonSpacer?.height ?? 0
            equalSpacerHeightConstraint?.isActive = false
            pinnedSpacerHeightConstraint?.isActive = true
        }

        if !isDismissing {
            pinnedSpacerHeightConstraint?.isActive = false
            equalSpacerHeightConstraint?.isActive = true
        }
    }

    // MARK: - Methods

    @objc
    public func hideBackLink() {
        backLink?.isHidden = true
    }
}

// MARK: -

extension Deprecated_OnboardingVerificationViewController: Deprecated_RegistrationVerificationViewController {
    var phoneNumberE164: String? {
        onboardingController.phoneNumber?.e164
    }

    func tryToVerify(verificationCode: String) {
        AssertIsOnMainThread()

        let viewModel = self.viewModel
        onboardingController.update(verificationCode: verificationCode)

        onboardingController.submitVerification(fromViewController: self, showModal: false, completion: { (outcome) in
            viewModel.setProgressView(animating: false)
            if outcome != .success {
                viewModel.verificationCodeView.becomeFirstResponder()
            }
            if outcome == .invalidVerificationCode {
                viewModel.setHasInvalidCode(true)
            }
        })
    }

    func resendCode(asPhoneCall: Bool) {
        AssertIsOnMainThread()

        let viewModel = self.viewModel
        let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumberE164 ?? "")
        self.onboardingController.presentPhoneNumberConfirmationSheet(from: self, number: formattedPhoneNumber) { [weak self] shouldContinue in
            guard let self = self else { return }
            guard shouldContinue else {
                self.navigationController?.popViewController(animated: true)
                return
            }

            viewModel.setProgressView(animating: true, text: "")
            self.onboardingController.requestVerification(fromViewController: self, isSMS: !asPhoneCall) { willDismiss, _ in
                viewModel.setProgressView(animating: false)
                if !willDismiss {
                    viewModel.verificationCodeView.becomeFirstResponder()
                }
            }
        }
    }

    func registrationNavigateBack() {
        AssertIsOnMainThread()

        Logger.info("")
        let phoneNumberVC = navigationController?.viewControllers
            .filter { $0 is Deprecated_RegistrationPhoneNumberViewController }.last

        if let phoneNumberVC = phoneNumberVC {
            self.navigationController?.popToViewController(phoneNumberVC, animated: true)
        } else {
            self.navigationController?.popViewController(animated: true)
        }
    }

}
