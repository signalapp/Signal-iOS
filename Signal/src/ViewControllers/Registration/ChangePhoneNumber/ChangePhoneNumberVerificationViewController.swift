//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalCoreKit

// Most of the logic for the verification views resides in RegistrationVerificationViewController.
@objc
public class ChangePhoneNumberVerificationViewController: RegistrationBaseViewController {

    private let changePhoneNumberController: ChangePhoneNumberController
    private let oldPhoneNumber: PhoneNumber
    private let newPhoneNumber: PhoneNumber

    let viewModel = RegistrationVerificationViewModel()

    init(changePhoneNumberController: ChangePhoneNumberController,
         oldPhoneNumber: PhoneNumber,
         newPhoneNumber: PhoneNumber) {
        self.changePhoneNumberController = changePhoneNumberController
        self.oldPhoneNumber = oldPhoneNumber
        self.newPhoneNumber = newPhoneNumber

        super.init()

        viewModel.viewController = self
        keyboardObservationBehavior = .whileLifecycleVisible
    }

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()
        view.backgroundColor = Theme.backgroundColor

        viewModel.createViews(vc: self)
    }

    // MARK: - View Lifecycle

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

    @objc
    public func setVerificationCodeAndTryToVerify(_ verificationCode: String) {
        AssertIsOnMainThread()

        let filteredCode = verificationCode.digitsOnly
        if filteredCode.isEmpty {
            owsFailDebug("Invalid code: \(verificationCode)")
            return
        }

        verificationCodeView.set(verificationCode: filteredCode)
    }
}

// MARK: -

extension ChangePhoneNumberVerificationViewController: RegistrationVerificationViewController {
    var phoneNumberE164: String? {
        newPhoneNumber.toE164()
    }

    func tryToVerify(verificationCode: String) {
        AssertIsOnMainThread()

        let viewModel = self.viewModel

        changePhoneNumberController.verificationCode = verificationCode
        changePhoneNumberController.submitVerification(fromViewController: self) { outcome in
            AssertIsOnMainThread()

            viewModel.setProgressView(animating: false)
            if outcome != .success {
                viewModel.verificationCodeView.becomeFirstResponder()
            }
            if outcome == .invalidVerificationCode {
                viewModel.setHasInvalidCode(true)
            }
        }
    }

    func resendCode(asPhoneCall: Bool) {
        AssertIsOnMainThread()

        let viewModel = self.viewModel
        let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumberE164 ?? "")
        RegistrationHelper.presentPhoneNumberConfirmationSheet(from: self,
                                                               number: formattedPhoneNumber) { [weak self] shouldContinue in
            guard let self = self else { return }
            guard shouldContinue else {
                self.navigationController?.popViewController(animated: true)
                return
            }

            viewModel.setProgressView(animating: true, text: "")
            self.changePhoneNumberController.requestVerification(fromViewController: self,
                                                                 isSMS: !asPhoneCall) { willDismiss, _ in
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

        RegistrationBaseViewController.restoreBackButton(self)

        let phoneNumberVC = navigationController?.viewControllers
            .filter { $0 is ChangePhoneNumberSplashViewController }.last

        if let phoneNumberVC = phoneNumberVC {
            self.navigationController?.popToViewController(phoneNumberVC, animated: true)
        } else {
            self.navigationController?.popViewController(animated: true)
        }
    }
}
