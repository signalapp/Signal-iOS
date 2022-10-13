//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalCoreKit

// Most of the logic for the verification views resides in RegistrationVerificationViewController.
@objc
public class OnboardingVerificationViewController: OnboardingBaseViewController {

    let viewModel = RegistrationVerificationViewModel()

    override public func loadView() {
        viewModel.viewController = self

        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()
        view.backgroundColor = Theme.backgroundColor

        viewModel.createViews(vc: self)
    }

    // MARK: - View Lifecycle

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shouldIgnoreKeyboardChanges = false
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        verificationCodeView.becomeFirstResponder()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        shouldIgnoreKeyboardChanges = true
    }

    public override func updateBottomLayoutConstraint(fromInset before: CGFloat, toInset after: CGFloat) {
        let isDismissing = (after == 0)
        if isDismissing, equalSpacerHeightConstraint?.isActive == true {
            pinnedSpacerHeightConstraint?.constant = backButtonSpacer?.height ?? 0
            equalSpacerHeightConstraint?.isActive = false
            pinnedSpacerHeightConstraint?.isActive = true
        }

        // Ignore any minor decreases in height. We want to grow to accommodate the
        // QuickType bar, but shrinking in response to its dismissal is a bit much.
        let isKeyboardGrowing = after > (keyboardBottomConstraint?.constant ?? before)
        let isSignificantlyShrinking = ((before - after) / UIScreen.main.bounds.height) > 0.1
        if isKeyboardGrowing || isSignificantlyShrinking || isDismissing {
            super.updateBottomLayoutConstraint(fromInset: before, toInset: after)
            self.view.layoutIfNeeded()
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

    @objc
    public func setVerificationCodeAndTryToVerify(_ verificationCode: String) {
        AssertIsOnMainThread()

        let filteredCode = verificationCode.digitsOnly
        guard filteredCode.count > 0 else {
            owsFailDebug("Invalid code: \(verificationCode)")
            return
        }

        verificationCodeView.set(verificationCode: filteredCode)
    }
}

// MARK: -

extension OnboardingVerificationViewController: RegistrationVerificationViewController {
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
            .filter { $0 is RegistrationPhoneNumberViewController }.last

        if let phoneNumberVC = phoneNumberVC {
            self.navigationController?.popToViewController(phoneNumberVC, animated: true)
        } else {
            self.navigationController?.popViewController(animated: true)
        }
    }

}
