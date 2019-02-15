//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class OnboardingProfileViewController: OnboardingBaseViewController {

//    private var titleLabel: UILabel?
//    private let phoneNumberTextField = UITextField()
//    private let onboardingCodeView = OnboardingCodeView()
//    private var codeStateLink: OWSFlatButton?
//    private let errorLabel = UILabel()
    private let avatarView = AvatarImageView()
    private let nameTextfield = UITextField()
    private var avatar: UIImage?
    private let cameraCircle = UIView.container()

    private let avatarViewHelper = AvatarViewHelper()

    override public func loadView() {
        super.loadView()

        avatarViewHelper.delegate = self

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero

        let titleLabel = self.titleLabel(text: NSLocalizedString("ONBOARDING_PROFILE_TITLE", comment: "Title of the 'onboarding profile' view."))

        let explanationLabel = self.explanationLabel(explanationText: NSLocalizedString("ONBOARDING_PROFILE_EXPLANATION",
                                                                                        comment: "Explanation in the 'onboarding profile' view."))

        let nextButton = self.button(title: NSLocalizedString("BUTTON_NEXT",
                                                              comment: "Label for the 'next' button."),
                                     selector: #selector(nextPressed))

        avatarView.autoSetDimensions(to: CGSize(width: CGFloat(avatarSize), height: CGFloat(avatarSize)))

        let cameraImageView = UIImageView()
        cameraImageView.image = UIImage(named: "settings-avatar-camera")
        cameraCircle.backgroundColor = Theme.backgroundColor
        cameraCircle.addSubview(cameraImageView)
        let cameraCircleDiameter: CGFloat = 40
        cameraCircle.autoSetDimensions(to: CGSize(width: cameraCircleDiameter, height: cameraCircleDiameter))
        cameraCircle.layer.shadowColor = UIColor(white: 0, alpha: 0.15).cgColor
        cameraCircle.layer.shadowRadius = 5
        cameraCircle.layer.shadowOffset = CGSize(width: 1, height: 1)
        cameraCircle.layer.shadowOpacity = 1
        cameraCircle.layer.cornerRadius = cameraCircleDiameter * 0.5
        cameraCircle.clipsToBounds = false
        cameraImageView.autoCenterInSuperview()

        let avatarWrapper = UIView.container()
        avatarWrapper.isUserInteractionEnabled = true
        avatarWrapper.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(avatarTapped)))
        avatarWrapper.addSubview(avatarView)
        avatarView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        avatarWrapper.addSubview(cameraCircle)
        cameraCircle.autoPinEdge(toSuperviewEdge: .trailing)
        cameraCircle.autoPinEdge(toSuperviewEdge: .bottom)

        nameTextfield.textAlignment = .left
        nameTextfield.delegate = self
        nameTextfield.returnKeyType = .done
        nameTextfield.textColor = Theme.primaryColor
//        nameTextfield.tintColor = UIColor.ows_materialBlue
        nameTextfield.font = UIFont.ows_dynamicTypeBodyClamped
        nameTextfield.placeholder = NSLocalizedString("ONBOARDING_PROFILE_NAME_PLACEHOLDER",
                                                      comment: "Placeholder text for the profile name in the 'onboarding profile' view.")
        nameTextfield.setContentHuggingHorizontalLow()
        nameTextfield.setCompressionResistanceHorizontalLow()

        let nameWrapper = UIView.container()
        nameWrapper.setCompressionResistanceHorizontalLow()
        nameWrapper.setContentHuggingHorizontalLow()
        nameWrapper.addSubview(nameTextfield)
        nameTextfield.autoPinWidthToSuperview()
        nameTextfield.autoPinEdge(toSuperviewEdge: .top, withInset: 8)
        nameTextfield.autoPinEdge(toSuperviewEdge: .bottom, withInset: 8)
        _ = nameWrapper.addBottomStroke()

        let profileRow = UIStackView(arrangedSubviews: [
            avatarWrapper,
            nameWrapper
            ])
        profileRow.axis = .horizontal
        profileRow.alignment = .center
        profileRow.spacing = 8

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            topSpacer,
            profileRow,
            UIView.spacer(withHeight: 25),
            explanationLabel,
            UIView.spacer(withHeight: 20),
            nextButton,
            bottomSpacer
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)

        // Ensure whitespace is balanced, so inputs are vertically centered.
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        updateAvatarView()
    }

    private let avatarSize: UInt = 80

    private func updateAvatarView() {
        if let avatar = avatar {
            avatarView.image = avatar
            cameraCircle.isHidden = true
            return
        }

        let defaultAvatar = OWSContactAvatarBuilder(forLocalUserWithDiameter: avatarSize).buildDefaultImage()
        avatarView.image = defaultAvatar
        cameraCircle.isHidden = false
    }

//     // MARK: - Code State
//
//    private let countdownDuration: TimeInterval = 60
//    private var codeCountdownTimer: Timer?
//    private var codeCountdownStart: NSDate?
//
//    deinit {
//        if let codeCountdownTimer = codeCountdownTimer {
//            codeCountdownTimer.invalidate()
//        }
//    }
//
//    private func startCodeCountdown() {
//        codeCountdownStart = NSDate()
//        codeCountdownTimer = Timer.weakScheduledTimer(withTimeInterval: 1, target: self, selector: #selector(codeCountdownTimerFired), userInfo: nil, repeats: true)
//    }
//
//    @objc
//    public func codeCountdownTimerFired() {
//        guard let codeCountdownStart = codeCountdownStart else {
//            owsFailDebug("Missing codeCountdownStart.")
//            return
//        }
//        guard let codeCountdownTimer = codeCountdownTimer else {
//            owsFailDebug("Missing codeCountdownTimer.")
//            return
//        }
//
//        let countdownInterval = abs(codeCountdownStart.timeIntervalSinceNow)
//
//        guard countdownInterval < countdownDuration else {
//            // Countdown complete.
//            codeCountdownTimer.invalidate()
//            self.codeCountdownTimer = nil
//
//            if codeState != .pending {
//                owsFailDebug("Unexpected codeState: \(codeState)")
//            }
//            codeState = .possiblyNotDelivered
//            updateCodeState()
//            return
//        }
//
//        // Update the "code state" UI to reflect the countdown.
//        updateCodeState()
//    }
//
//    private func updateCodeState() {
//        AssertIsOnMainThread()
//
//        guard let codeCountdownStart = codeCountdownStart else {
//            owsFailDebug("Missing codeCountdownStart.")
//            return
//        }
//        guard let titleLabel = titleLabel else {
//            owsFailDebug("Missing titleLabel.")
//            return
//        }
//        guard let codeStateLink = codeStateLink else {
//            owsFailDebug("Missing codeStateLink.")
//            return
//        }
//
//        var e164PhoneNumber = ""
//        if let phoneNumber = onboardingController.phoneNumber {
//            e164PhoneNumber = phoneNumber.e164
//        }
//        let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: e164PhoneNumber)
//
//        // Update titleLabel
//        switch codeState {
//        case .pending, .possiblyNotDelivered:
//            titleLabel.text = String(format: NSLocalizedString("ONBOARDING_VERIFICATION_TITLE_DEFAULT_FORMAT",
//                                                               comment: "Format for the title of the 'onboarding verification' view. Embeds {{the user's phone number}}."),
//                                     formattedPhoneNumber)
//        case .resent:
//            titleLabel.text = String(format: NSLocalizedString("ONBOARDING_VERIFICATION_TITLE_RESENT_FORMAT",
//                                                               comment: "Format for the title of the 'onboarding verification' view after the verification code has been resent. Embeds {{the user's phone number}}."),
//                                     formattedPhoneNumber)
//        }
//
//        // Update codeStateLink
//        switch codeState {
//        case .pending:
//            let countdownInterval = abs(codeCountdownStart.timeIntervalSinceNow)
//            let countdownRemaining = max(0, countdownDuration - countdownInterval)
//            let formattedCountdown = OWSFormat.formatDurationSeconds(Int(round(countdownRemaining)))
//            let text = String(format: NSLocalizedString("ONBOARDING_VERIFICATION_CODE_COUNTDOWN_FORMAT",
//                                                        comment: "Format for the label of the 'pending code' label of the 'onboarding verification' view. Embeds {{the time until the code can be resent}}."),
//                              formattedCountdown)
//            codeStateLink.setTitle(title: text, font: .ows_dynamicTypeBodyClamped, titleColor: Theme.secondaryColor)
////            codeStateLink.setBackgroundColors(upColor: Theme.backgroundColor)
//        case .possiblyNotDelivered:
//            codeStateLink.setTitle(title: NSLocalizedString("ONBOARDING_VERIFICATION_ORIGINAL_CODE_MISSING_LINK",
//                                                            comment: "Label for link that can be used when the original code did not arrive."),
//                                   font: .ows_dynamicTypeBodyClamped,
//                                   titleColor: .ows_materialBlue)
//        case .resent:
//            codeStateLink.setTitle(title: NSLocalizedString("ONBOARDING_VERIFICATION_RESENT_CODE_MISSING_LINK",
//                                                            comment: "Label for link that can be used when the resent code did not arrive."),
//                                   font: .ows_dynamicTypeBodyClamped,
//                                   titleColor: .ows_materialBlue)
//        }
//    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        _ = nameTextfield.becomeFirstResponder()
    }

    // MARK: - Events

    @objc func avatarTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        showAvatarActionSheet()
    }

    @objc func nextPressed() {
        Logger.info("")

        // TODO:
//        parseAndTryToRegister()
    }

    private func showAvatarActionSheet() {
        AssertIsOnMainThread()

        Logger.info("")

        avatarViewHelper.showChangeAvatarUI()

//        let alert = UIAlertController(title: NSLocalizedString("CHECK_FOR_BACKUP_FAILED_TITLE",
//                                                               comment: "Title for alert shown when the app failed to check for an existing backup."),
//                                      message: NSLocalizedString("CHECK_FOR_BACKUP_FAILED_MESSAGE",
//                                                                 comment: "Message for alert shown when the app failed to check for an existing backup."),
//                                      preferredStyle: .alert)
//        alert.addAction(UIAlertAction(title: NSLocalizedString("REGISTER_FAILED_TRY_AGAIN", comment: ""),
//                                      style: .default) { (_) in
//                                        self.checkCanImportBackup(fromView: view)
//        })
//        alert.addAction(UIAlertAction(title: NSLocalizedString("CHECK_FOR_BACKUP_DO_NOT_RESTORE", comment: "The label for the 'do not restore backup' button."),
//                                      style: .destructive) { (_) in
//                                        self.showProfileView(fromView: view)
//        })
//        view.present(alert, animated: true)
    }

    //    @objc func backLinkTapped() {
//        Logger.info("")
//
//        self.navigationController?.popViewController(animated: true)
//    }
//
//    @objc func resendCodeLinkTapped() {
//        Logger.info("")
//
//        switch codeState {
//        case .pending:
//            // Ignore taps until the countdown expires.
//            break
//        case .possiblyNotDelivered, .resent:
//            showResendActionSheet()
//        }
//    }
//
//    private func showResendActionSheet() {
//        Logger.info("")
//
//        let actionSheet = UIAlertController(title: NSLocalizedString("ONBOARDING_VERIFICATION_RESEND_CODE_ALERT_TITLE",
//                                                                     comment: "Title for the 'resend code' alert in the 'onboarding verification' view."),
//                                            message: NSLocalizedString("ONBOARDING_VERIFICATION_RESEND_CODE_ALERT_MESSAGE",
//                                                                       comment: "Message for the 'resend code' alert in the 'onboarding verification' view."),
//                                            preferredStyle: .actionSheet)
//
//        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("ONBOARDING_VERIFICATION_RESEND_CODE_BY_SMS_BUTTON",
//                                                                     comment: "Label for the 'resend code by SMS' button in the 'onboarding verification' view."),
//                                            style: .default) { _ in
//                                                self.onboardingController.tryToRegister(fromViewController: self, smsVerification: true)
//        })
//        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("ONBOARDING_VERIFICATION_RESEND_CODE_BY_VOICE_BUTTON",
//                                                                     comment: "Label for the 'resend code by voice' button in the 'onboarding verification' view."),
//                                            style: .default) { _ in
//                                                self.onboardingController.tryToRegister(fromViewController: self, smsVerification: false)
//        })
//        actionSheet.addAction(OWSAlerts.cancelAction)
//
//        self.present(actionSheet, animated: true)
//    }
//
//    private func tryToVerify() {
//        Logger.info("")
//
//        guard onboardingCodeView.isComplete else {
//            return
//        }
//
//        setHasInvalidCode(false)
//
//        onboardingController.tryToVerify(fromViewController: self, verificationCode: onboardingCodeView.verificationCode, pin: nil, isInvalidCodeCallback: {
//            self.setHasInvalidCode(true)
//        })
//    }
//
//    private func setHasInvalidCode(_ value: Bool) {
//        onboardingCodeView.setHasError(value)
//        errorLabel.isHidden = !value
//    }
//}
//
//// MARK: -
//
//extension OnboardingProfileViewController: OnboardingCodeViewDelegate {
//    public func codeViewDidChange() {
//        AssertIsOnMainThread()
//
//        setHasInvalidCode(false)
//
//        tryToVerify()
//    }
}

// MARK: -

extension OnboardingProfileViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        //        // TODO: Fix auto-format of phone numbers.
        //        ViewControllerUtils.phoneNumber(textField, shouldChangeCharactersIn: range, replacementString: string, countryCode: countryCode)
        //
        //        isPhoneNumberInvalid = false
        //        updateValidationWarnings()

        // Inform our caller that we took care of performing the change.
        return true
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        //        parseAndTryToRegister()
        return false
    }
}

// MARK: -

extension OnboardingProfileViewController: AvatarViewHelperDelegate {
    public func avatarActionSheetTitle() -> String? {
        return nil
    }

    public func avatarDidChange(_ image: UIImage) {
        AssertIsOnMainThread()

        let maxDiameter = CGFloat(kOWSProfileManager_MaxAvatarDiameter)
        avatar = image.resizedImage(toFillPixelSize: CGSize(width: maxDiameter,
                                                            height: maxDiameter))

        updateAvatarView()
    }

    public func fromViewController() -> UIViewController {
        return self
    }

    public func hasClearAvatarAction() -> Bool {
        return avatar != nil
    }

    public func clearAvatar() {
        avatar = nil

        updateAvatarView()
    }

    public func clearAvatarActionLabel() -> String {
        return NSLocalizedString("PROFILE_VIEW_CLEAR_AVATAR", comment: "Label for action that clear's the user's profile avatar")
    }
}
