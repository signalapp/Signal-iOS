//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

private protocol OnboardingCodeViewTextFieldDelegate: AnyObject {
    func textFieldDidDeletePrevious()
}

// MARK: -

// Editing a code should feel seamless, as even though
// the UITextField only lets you edit a single digit at
// a time.  For deletes to work properly, we need to
// detect delete events that would affect the _previous_
// digit.
private class OnboardingCodeViewTextField: UITextField {

    fileprivate weak var codeDelegate: OnboardingCodeViewTextFieldDelegate?

    override func deleteBackward() {
        var isDeletePrevious = false
        if let selectedTextRange = selectedTextRange {
            let cursorPosition = offset(from: beginningOfDocument, to: selectedTextRange.start)
            if cursorPosition == 0 {
                isDeletePrevious = true
            }
        }

        super.deleteBackward()

        if isDeletePrevious {
            codeDelegate?.textFieldDidDeletePrevious()
        }
    }

}

// MARK: -

protocol OnboardingCodeViewDelegate: AnyObject {
    func codeViewDidChange()
}

// MARK: -

// The OnboardingCodeView is a special "verification code"
// editor that should feel like editing a single piece
// of text (ala UITextField) even though the individual
// digits of the code are visually separated.
//
// We use a separate UILabel for each digit, and move
// around a single UITextfield to let the user edit the
// last/next digit.
private class OnboardingCodeView: UIView {

    weak var delegate: OnboardingCodeViewDelegate?

    public init() {
        super.init(frame: .zero)

        createSubviews()

        updateViewState()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let digitCount = 6
    private var digitLabels = [UILabel]()
    private var digitStrokes = [UIView]()

    // We use a single text field to edit the "current" digit.
    // The "current" digit is usually the "last"
    fileprivate let textfield = OnboardingCodeViewTextField()
    private var currentDigitIndex = 0
    private var textfieldConstraints = [NSLayoutConstraint]()

    // The current complete text - the "model" for this view.
    private var digitText = ""

    var isComplete: Bool {
        return digitText.count == digitCount
    }
    var verificationCode: String {
        return digitText
    }

    private func createSubviews() {
        textfield.textAlignment = .left
        textfield.delegate = self
        textfield.codeDelegate = self

        textfield.textColor = Theme.primaryTextColor
        textfield.font = UIFont.ows_dynamicTypeLargeTitle1Clamped
        textfield.keyboardType = .numberPad
        if #available(iOS 12, *) {
            textfield.textContentType = .oneTimeCode
        }

        var digitViews = [UIView]()
        (0..<digitCount).forEach { (_) in
            let (digitView, digitLabel, digitStroke) = makeCellView(text: "", hasStroke: true)

            digitLabels.append(digitLabel)
            digitStrokes.append(digitStroke)
            digitViews.append(digitView)
        }

        digitViews.insert(UIView.spacer(withWidth: 24), at: 3)

        let stackView = UIStackView(arrangedSubviews: digitViews)
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        addSubview(stackView)
        stackView.autoPinHeightToSuperview()
        stackView.autoHCenterInSuperview()

        self.addSubview(textfield)
    }

    private func makeCellView(text: String, hasStroke: Bool) -> (UIView, UILabel, UIView) {
        let digitView = UIView()

        let digitLabel = UILabel()
        digitLabel.text = text
        digitLabel.font = UIFont.ows_dynamicTypeLargeTitle1Clamped
        digitLabel.textColor = Theme.primaryTextColor
        digitLabel.textAlignment = .center
        digitView.addSubview(digitLabel)
        digitLabel.autoCenterInSuperview()

        let strokeColor = (hasStroke ? Theme.secondaryTextAndIconColor : UIColor.clear)
        let strokeView = digitView.addBottomStroke(color: strokeColor, strokeWidth: 3)
        strokeView.layer.cornerRadius = 1.5

        let vMargin: CGFloat = 4
        let cellHeight: CGFloat = digitLabel.font.lineHeight + vMargin * 2
        let cellWidth: CGFloat = cellHeight * 2 / 3
        digitView.autoSetDimensions(to: CGSize(width: cellWidth, height: cellHeight))

        return (digitView, digitLabel, strokeView)
    }

    private func digit(at index: Int) -> String {
        guard index < digitText.count else {
            return ""
        }
        return digitText.substring(from: index).substring(to: 1)
    }

    // Ensure that all labels are displaying the correct
    // digit (if any) and that the UITextField has replaced
    // the "current" digit.
    private func updateViewState() {
        currentDigitIndex = min(digitCount - 1,
                                digitText.count)

        (0..<digitCount).forEach { (index) in
            let digitLabel = digitLabels[index]
            digitLabel.text = digit(at: index)
            digitLabel.isHidden = index == currentDigitIndex
        }

        NSLayoutConstraint.deactivate(textfieldConstraints)
        textfieldConstraints.removeAll()

        let digitLabelToReplace = digitLabels[currentDigitIndex]
        textfield.text = digit(at: currentDigitIndex)
        textfieldConstraints.append(textfield.autoAlignAxis(.horizontal, toSameAxisOf: digitLabelToReplace))
        textfieldConstraints.append(textfield.autoAlignAxis(.vertical, toSameAxisOf: digitLabelToReplace))

        // Move cursor to end of text.
        let newPosition = textfield.endOfDocument
        textfield.selectedTextRange = textfield.textRange(from: newPosition, to: newPosition)
    }

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        return textfield.becomeFirstResponder()
    }

    @discardableResult
    public override func resignFirstResponder() -> Bool {
        return textfield.resignFirstResponder()
    }

    func setHasError(_ hasError: Bool) {
        let backgroundColor = (hasError ? UIColor.ows_accentRed : Theme.secondaryTextAndIconColor)
        for digitStroke in digitStrokes {
            digitStroke.backgroundColor = backgroundColor
        }
    }

    fileprivate func set(verificationCode: String) {
        digitText = verificationCode

        updateViewState()

        self.delegate?.codeViewDidChange()
    }
}

// MARK: -

extension OnboardingCodeView: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString newString: String) -> Bool {
        var oldText = ""
        if let textFieldText = textField.text {
            oldText = textFieldText
        }
        let left = oldText.substring(to: range.location)
        let right = oldText.substring(from: range.location + range.length)
        let unfiltered = left + newString + right
        let characterSet = CharacterSet(charactersIn: "0123456789")
        let filtered = unfiltered.components(separatedBy: characterSet.inverted).joined()
        let filteredAndTrimmed = filtered.substring(to: 1)
        textField.text = filteredAndTrimmed

        digitText = digitText.substring(to: currentDigitIndex) + filteredAndTrimmed

        updateViewState()

        self.delegate?.codeViewDidChange()

        // Inform our caller that we took care of performing the change.
        return false
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.delegate?.codeViewDidChange()

        return false
    }
}

// MARK: -

extension OnboardingCodeView: OnboardingCodeViewTextFieldDelegate {
    public func textFieldDidDeletePrevious() {
        guard digitText.count > 0 else {
            return
        }
        digitText = digitText.substring(to: currentDigitIndex - 1)

        updateViewState()
    }
}

// MARK: -

@objc
public class OnboardingVerificationViewController: OnboardingBaseViewController {
    private var canResend = false

    private let topSpacer = UIView.vStretchingSpacer()
    private var titleLabel: UILabel?
    private var subtitleLabel: UILabel?
    private var backLink: OWSFlatButton?
    private let onboardingCodeView = OnboardingCodeView()
    private var resendCodeButton: OWSFlatButton?
    private var callMeButton: OWSFlatButton?
    private let errorLabel = UILabel()
    private let progressView = AnimatedProgressView()

    private var equalSpacerHeightConstraint: NSLayoutConstraint?
    private var pinnedSpacerHeightConstraint: NSLayoutConstraint?

    @objc
    public func hideBackLink() {
        backLink?.isHidden = true
    }

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()
        view.backgroundColor = Theme.backgroundColor

        let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(
            withE164: onboardingController.phoneNumber?.e164 ?? "")
            .replacingOccurrences(of: " ", with: "\u{00a0}")

        let titleLabel = self.createTitleLabel(
            text: NSLocalizedString(
                "ONBOARDING_VERIFICATION_TITLE_LABEL",
                comment: "Title label for the onboarding verification page")
            )

        let subtitleLabel = self.createExplanationLabel(
            explanationText: String(
                format: NSLocalizedString(
                    "ONBOARDING_VERIFICATION_TITLE_DEFAULT_FORMAT",
                    comment: "Format for the title of the 'onboarding verification' view. Embeds {{the user's phone number}}."),
                formattedPhoneNumber)
            )


        self.titleLabel = titleLabel
        self.subtitleLabel = subtitleLabel
        titleLabel.accessibilityIdentifier = "onboarding.verification." + "titleLabel"
        subtitleLabel.accessibilityIdentifier = "onboarding.verification." + "subtitleLabel"

        let backLink = self.linkButton(title: NSLocalizedString("ONBOARDING_VERIFICATION_BACK_LINK",
                                                                comment: "Label for the link that lets users change their phone number in the onboarding views."),
                                       selector: #selector(backLinkTapped))
        self.backLink = backLink
        backLink.accessibilityIdentifier = "onboarding.verification." + "backLink"

        onboardingCodeView.delegate = self

        errorLabel.text = NSLocalizedString("ONBOARDING_VERIFICATION_INVALID_CODE",
                                            comment: "Label indicating that the verification code is incorrect in the 'onboarding verification' view.")
        errorLabel.textColor = .ows_accentRed
        errorLabel.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        errorLabel.textAlignment = .center
        errorLabel.autoSetDimension(.height, toSize: errorLabel.font.lineHeight)
        errorLabel.accessibilityIdentifier = "onboarding.verification." + "errorLabel"

        // Wrap the error label in a row so that we can show/hide it without affecting view layout.
        let errorRow = UIView()
        errorRow.addSubview(errorLabel)
        errorLabel.autoPinEdgesToSuperviewEdges()

        let resendCodeButton = self.linkButton(title: "", selector: #selector(resendCodeButtonTapped))
        resendCodeButton.enableMultilineLabel()
        resendCodeButton.accessibilityIdentifier = "onboarding.verification." + "resendCodeButton"
        self.resendCodeButton = resendCodeButton

        let callMeButton = self.linkButton(title: "", selector: #selector(callMeButtonTapped))
        callMeButton.enableMultilineLabel()
        callMeButton.accessibilityIdentifier = "onboarding.verification." + "callMeButton"
        self.callMeButton = callMeButton

        let buttonStack = UIStackView(arrangedSubviews: [
            resendCodeButton,
            UIView.hStretchingSpacer(),
            callMeButton
        ])
        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        resendCodeButton.autoPinWidth(toWidthOf: callMeButton)

        let bottomSpacer = UIView.vStretchingSpacer()
        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 12),
            subtitleLabel,
            UIView.spacer(withHeight: 4),
            backLink,
            topSpacer,
            onboardingCodeView,
            UIView.spacer(withHeight: 12),
            errorRow,
            bottomSpacer,
            buttonStack,
            UIView.vStretchingSpacer(minHeight: 16, maxHeight: primaryLayoutMargins.bottom)
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        primaryView.addSubview(stackView)
        primaryView.addSubview(progressView)

        // Because of the keyboard, vertical spacing can get pretty cramped,
        // so we have custom spacer logic.
        stackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)
        autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)
        progressView.autoCenterInSuperviewMargins()

        progressView.hidesWhenStopped = false
        progressView.alpha = 0

        // During initial layout, ensure whitespace is balanced, so inputs are vertically centered.
        // After initial layout, keep top spacer height constant so keyboard frame changes don't update its position
        equalSpacerHeightConstraint = topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
        pinnedSpacerHeightConstraint = topSpacer.autoSetDimension(.height, toSize: 0)
        pinnedSpacerHeightConstraint?.priority = .defaultHigh
        pinnedSpacerHeightConstraint?.isActive = false

        startCodeCountdown()
        updateResendButtons()

        UIView.performWithoutAnimation {
            setHasInvalidCode(false)
        }
    }

     // MARK: - Code State

    private let countdownDuration: TimeInterval = 60
    private var codeCountdownTimer: Timer?
    private var codeCountdownStart: NSDate?

    deinit {
        codeCountdownTimer?.invalidate()
    }

    private func startCodeCountdown() {
        codeCountdownStart = NSDate()
        codeCountdownTimer = Timer.weakScheduledTimer(withTimeInterval: 0.25, target: self, selector: #selector(codeCountdownTimerFired), userInfo: nil, repeats: true)
    }

    @objc
    public func codeCountdownTimerFired() {
        guard let codeCountdownStart = codeCountdownStart else {
            owsFailDebug("Missing codeCountdownStart.")
            return
        }
        guard let codeCountdownTimer = codeCountdownTimer else {
            owsFailDebug("Missing codeCountdownTimer.")
            return
        }

        let countdownInterval = abs(codeCountdownStart.timeIntervalSinceNow)

        if countdownInterval >= countdownDuration {
            // Countdown complete.
            codeCountdownTimer.invalidate()
            self.codeCountdownTimer = nil

            canResend = true
        }

        // Update the resend buttons UI to reflect the countdown.
        updateResendButtons()
    }

    private func updateResendButtons() {
        AssertIsOnMainThread()

        guard let codeCountdownStart = codeCountdownStart else {
            owsFailDebug("Missing codeCountdownStart.")
            return
        }

        resendCodeButton?.setEnabled(canResend)
        callMeButton?.setEnabled(canResend)

        if canResend {
            let resendCodeTitle = NSLocalizedString(
                "ONBOARDING_VERIFICATION_RESEND_CODE_BUTTON",
                comment: "Label for button to resend SMS verification code.")
            let callMeTitle = NSLocalizedString(
                "ONBOARDING_VERIFICATION_CALL_ME_BUTTON",
                comment: "Label for button to perform verification with a phone call.")

            resendCodeButton?.setTitle(
                title: resendCodeTitle,
                font: .ows_dynamicTypeSubheadlineClamped,
                titleColor: Theme.accentBlueColor)
            callMeButton?.setTitle(
                title: callMeTitle,
                font: .ows_dynamicTypeSubheadlineClamped,
                titleColor: Theme.accentBlueColor)

        } else {
            let countdownInterval = abs(codeCountdownStart.timeIntervalSinceNow)
            let countdownRemaining = max(0, countdownDuration - countdownInterval)
            let formattedCountdown = OWSFormat.formatDurationSeconds(Int(round(countdownRemaining)))

            let resendCodeCountdownFormat = NSLocalizedString(
                "ONBOARDING_VERIFICATION_RESEND_CODE_COUNTDOWN_FORMAT",
                comment: "Format string for button counting down time until SMS code can be resent. Embeds {{time remaining}}.")
            let callMeCountdownFormat = NSLocalizedString(
                "ONBOARDING_VERIFICATION_CALL_ME_COUNTDOWN_FORMAT",
                comment: "Format string for button counting down time until phone call verification can be performed. Embeds {{time remaining}}.")

            let resendCodeTitle = String(format: resendCodeCountdownFormat, formattedCountdown)
            let callMeTitle = String(format: callMeCountdownFormat, formattedCountdown)
            resendCodeButton?.setTitle(
                title: resendCodeTitle,
                font: .ows_dynamicTypeSubheadlineClamped,
                titleColor: Theme.secondaryTextAndIconColor)
            callMeButton?.setTitle(
                title: callMeTitle,
                font: .ows_dynamicTypeSubheadlineClamped,
                titleColor: Theme.secondaryTextAndIconColor)
        }
    }

    private func resendCode(asPhoneCall: Bool) {
        onboardingCodeView.resignFirstResponder()
        
        let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: onboardingController.phoneNumber?.e164 ?? "")
        self.onboardingController.presentPhoneNumberConfirmationSheet(from: self, number: formattedPhoneNumber) { [weak self] shouldContinue in
            guard let self = self else { return }
            guard shouldContinue else {
                self.navigationController?.popViewController(animated: true)
                return
            }

            self.setProgressView(animating: true, text: "")
            self.onboardingController.requestVerification(fromViewController: self, isSMS: !asPhoneCall) { [weak self] error in
                self?.setProgressView(animating: false)
                if error != nil {
                    self?.onboardingCodeView.becomeFirstResponder()
                }
            }
        }
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        shouldBottomViewReserveSpaceForKeyboard = false
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onboardingCodeView.becomeFirstResponder()
        shouldIgnoreKeyboardChanges = false
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        shouldIgnoreKeyboardChanges = true
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // After a layout pass performed under the equal spacing constraint, pin the
        // top spacer's height. We don't want to re-adjust everything whenever the keyboard
        // frame changes (e.g. showing and hiding the QuickType bar)
        if equalSpacerHeightConstraint?.isActive == true, topSpacer.height > 0 {
            pinnedSpacerHeightConstraint?.constant = topSpacer.height

            pinnedSpacerHeightConstraint?.isActive = true
            equalSpacerHeightConstraint?.isActive = false
        }
    }

    // MARK: - Events

    @objc func backLinkTapped() {
        Logger.info("")
        self.navigationController?.popViewController(animated: true)
    }

    @objc func resendCodeButtonTapped() {
        guard canResend else { return }
        Logger.info("")
        resendCode(asPhoneCall: false)
    }

    @objc func callMeButtonTapped() {
        guard canResend else { return }
        Logger.info("")
        resendCode(asPhoneCall: true)
    }

    private func tryToVerify() {
        Logger.info("")
        setHasInvalidCode(false)
        guard onboardingCodeView.isComplete else { return }

        let spinnerLabel = NSLocalizedString(
            "ONBOARDING_VERIFICATION_CODE_VALIDATION_PROGRESS_LABEL",
            comment: "Label for a progress spinner currently validating code")

        setProgressView(animating: true, text: spinnerLabel)
        onboardingCodeView.resignFirstResponder()
        onboardingController.update(verificationCode: onboardingCodeView.verificationCode)

        onboardingController.submitVerification(fromViewController: self, showModal: false, completion: { (outcome) in
            self.setProgressView(animating: false)
            if outcome != .success {
                self.onboardingCodeView.becomeFirstResponder()
            }
            if outcome == .invalidVerificationCode {
                self.setHasInvalidCode(true)
            }
        })
    }

    private func setProgressView(animating: Bool, text: String? = nil) {
        text.map { progressView.loadingText = $0 }

        if animating, !progressView.isAnimating {
            progressView.startAnimating()
            UIView.animate(withDuration: 0.25, delay: 0.25, options: .beginFromCurrentState) {
                self.backLink?.setEnabled(false)
                self.resendCodeButton?.setEnabled(false)
                self.resendCodeButton?.setEnabled(false)

                self.progressView.alpha = 1
                self.onboardingCodeView.alpha = 0
            }

        } else if !animating, progressView.isAnimating {
            UIView.animate(withDuration: 0.25, delay: 0, options: .beginFromCurrentState) {
                self.backLink?.setEnabled(true)
                self.resendCodeButton?.setEnabled(true)
                self.resendCodeButton?.setEnabled(true)

                self.progressView.alpha = 0
                self.onboardingCodeView.alpha = 1
            } completion: { _ in
                self.progressView.stopAnimatingImmediately()
            }
        }
    }

    private func setHasInvalidCode(_ isInvalid: Bool) {
        UIView.animate(withDuration: 0.25, delay: 0, options: .beginFromCurrentState) {
            self.onboardingCodeView.setHasError(isInvalid)
            self.errorLabel.alpha = isInvalid ? 1 : 0
        }
    }

    @objc
    public func setVerificationCodeAndTryToVerify(_ verificationCode: String) {
        AssertIsOnMainThread()

        let filteredCode = verificationCode.digitsOnly
        guard filteredCode.count > 0 else {
            owsFailDebug("Invalid code: \(verificationCode)")
            return
        }

        onboardingCodeView.set(verificationCode: filteredCode)
    }
}

// MARK: -

extension OnboardingVerificationViewController: OnboardingCodeViewDelegate {
    public func codeViewDidChange() {
        AssertIsOnMainThread()

        setHasInvalidCode(false)

        tryToVerify()
    }
}
