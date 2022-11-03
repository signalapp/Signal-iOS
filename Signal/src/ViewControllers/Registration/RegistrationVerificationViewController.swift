//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalCoreKit

@objc
protocol RegistrationVerificationViewController: AnyObject {

    var viewModel: RegistrationVerificationViewModel { get }
    var primaryView: UIView { get }
    var phoneNumberE164: String? { get }

    func tryToVerify(verificationCode: String)

    func resendCode(asPhoneCall: Bool)

    func registrationNavigateBack()
}

// MARK: -

@objc
class RegistrationVerificationViewModel: NSObject {
    weak var viewController: RegistrationVerificationViewController?

    var canResend = false
    var titleLabel: UILabel?
    var subtitleLabel: UILabel?
    var backLink: OWSFlatButton?
    var backButtonSpacer: UIView?
    let verificationCodeView = RegistrationVerificationCodeView()
    var resendCodeButton: OWSFlatButton?
    var callMeButton: OWSFlatButton?
    let errorLabel = UILabel()
    let progressView: AnimatedProgressView = {
        let view = AnimatedProgressView()
        view.hidesWhenStopped = false
        view.alpha = 0
        return view
    }()

    var equalSpacerHeightConstraint: NSLayoutConstraint?
    var pinnedSpacerHeightConstraint: NSLayoutConstraint?
    var buttonHeightConstraints: [NSLayoutConstraint] = []

    // MARK: - Methods

    func createViews(vc: RegistrationBaseViewController) {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        let primaryView = viewController.primaryView

        let formattedPhoneNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(
            withE164: viewController.phoneNumberE164 ?? "")
            .replacingOccurrences(of: " ", with: "\u{00a0}")

        let titleLabel = vc.createTitleLabel(
            text: NSLocalizedString(
                "ONBOARDING_VERIFICATION_TITLE_LABEL",
                comment: "Title label for the onboarding verification page")
        )

        let subtitleLabel = vc.createExplanationLabel(
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

        let backLink = vc.linkButton(title: NSLocalizedString("ONBOARDING_VERIFICATION_BACK_LINK",
                                                              comment: "Label for the link that lets users change their phone number in the onboarding views."),
                                     target: self,
                                     selector: #selector(backLinkTapped))
        self.backLink = backLink
        backLink.accessibilityIdentifier = "onboarding.verification." + "backLink"

        verificationCodeView.delegate = self

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

        let resendCodeButton = vc.linkButton(title: "", target: self, selector: #selector(resendCodeButtonTapped))
        resendCodeButton.enableMultilineLabel()
        resendCodeButton.accessibilityIdentifier = "onboarding.verification." + "resendCodeButton"
        self.resendCodeButton = resendCodeButton

        let callMeButton = vc.linkButton(title: "", target: self, selector: #selector(callMeButtonTapped))
        callMeButton.enableMultilineLabel()
        callMeButton.accessibilityIdentifier = "onboarding.verification." + "callMeButton"
        self.callMeButton = callMeButton

        let buttonStack = UIStackView(arrangedSubviews: [
            resendCodeButton,
            UIView.hStretchingSpacer(),
            callMeButton
        ])
        buttonStack.axis = .horizontal
        buttonStack.alignment = .fill
        resendCodeButton.autoPinWidth(toWidthOf: callMeButton)

        let titleSpacer = SpacerView(preferredHeight: 12)
        let subtitleSpacer = SpacerView(preferredHeight: 4)
        let backButtonSpacer = SpacerView(preferredHeight: 4)
        let onboardingCodeSpacer = SpacerView(preferredHeight: 12)
        let errorSpacer = SpacerView(preferredHeight: 4)
        let bottomSpacer = SpacerView(preferredHeight: 4)
        self.backButtonSpacer = backButtonSpacer

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel, titleSpacer,
            subtitleLabel, subtitleSpacer,
            backLink, backButtonSpacer,
            verificationCodeView, onboardingCodeSpacer,
            errorRow, errorSpacer,
            buttonStack, bottomSpacer
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        primaryView.addSubview(stackView)
        primaryView.addSubview(progressView)

        // Here comes a bunch of autolayout prioritization to make sure we can fit on an iPhone 5s/SE
        // It's complicated, but there are a few rules that help here:
        // - First, set required constraints on everything that's *critical* for usability
        // - Next, progressively add non-required constraints that are nice to have, but not critical.
        // - Finally, pick one and only one view in the stack and set its contentHugging explicitly low
        //
        // - Non-required constraints should each have a unique priority. This is important to resolve
        //   autolayout ambiguity e.g. I have 10pts of extra space, and two equally weighted constraints
        //   that both consume 8pts. What do I satisfy?
        // - Every view should have an intrinsicContentSize. Content Hugging and Content Compression
        //   don't mean much without a content size.
        stackView.autoPinEdge(toSuperviewSafeArea: .top, withInset: 0, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .top).priority = .defaultHigh
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoPinEdge(.bottom, to: .bottom, of: vc.keyboardLayoutGuideViewSafeArea)
        progressView.autoCenterInSuperview()

        // For when things get *really* cramped, here's what's required:
        self.equalSpacerHeightConstraint = backButtonSpacer.autoMatch(.height, to: .height, of: errorSpacer)
        self.pinnedSpacerHeightConstraint = backButtonSpacer.autoSetDimension(.height, toSize: 0)
        pinnedSpacerHeightConstraint?.isActive = false
        [subtitleLabel, verificationCodeView, errorRow].forEach { $0.setCompressionResistanceVerticalHigh() }

        // We need at least one line of text for the back link. We don't care about the insets
        let minimumHeight = backLink.sizeThatFitsMaxSize.height - backLink.contentEdgeInsets.totalHeight
        backLink.autoSetDimension(.height, toSize: minimumHeight, relation: .greaterThanOrEqual)

        // Once we satisfied the above constraints, start to add back in padding/insets. First the buttons and title
        callMeButton.setContentCompressionResistancePriority(.required - 10, for: .vertical)
        resendCodeButton.setContentCompressionResistancePriority(.required - 10, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.required - 20, for: .vertical)
        backLink.setContentCompressionResistancePriority(.required - 30, for: .vertical)

        // Then the preferred spacer size
        bottomSpacer.setContentCompressionResistancePriority(.defaultHigh - 10, for: .vertical)
        titleSpacer.setContentCompressionResistancePriority(.defaultHigh - 20, for: .vertical)
        subtitleSpacer.setContentCompressionResistancePriority(.defaultHigh - 30, for: .vertical)
        onboardingCodeSpacer.setContentCompressionResistancePriority(.defaultHigh - 40, for: .vertical)
        backButtonSpacer.setContentCompressionResistancePriority(.defaultHigh - 50, for: .vertical)

        // If we're flush with space, bump up the bottomSpacer spacer to 16, then the bottom layout margins
        bottomSpacer.autoSetDimension(.height, toSize: 16, relation: .greaterThanOrEqual).priority = .defaultHigh - 40
        bottomSpacer.autoSetDimension(.height, toSize: vc.primaryLayoutMargins.bottom).priority = .defaultLow

        // And if we have so much space we don't know what to do with it, grow the space between
        // the error label and the button stack button. Usually the top space will grow along with
        // it because of the equal spacing constraint
        errorSpacer.setContentHuggingPriority(.init(100), for: .vertical)

        startCodeCountdown()
        updateResendButtons()
        UIView.performWithoutAnimation {
            setHasInvalidCode(false)
        }
    }

    private func tryToVerify() {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }

        Logger.info("")
        setHasInvalidCode(false)
        guard verificationCodeView.isComplete else { return }

        let spinnerLabel = NSLocalizedString(
            "ONBOARDING_VERIFICATION_CODE_VALIDATION_PROGRESS_LABEL",
            comment: "Label for a progress spinner currently validating code")
        setProgressView(animating: true, text: spinnerLabel)
        verificationCodeView.resignFirstResponder()

        viewController.tryToVerify(verificationCode: verificationCodeView.verificationCode)
    }

    func setProgressView(animating: Bool, text: String? = nil) {
        text.map { progressView.loadingText = $0 }

        if animating, !progressView.isAnimating {
            progressView.startAnimating()
            UIView.animate(withDuration: 0.25, delay: 0.25, options: .beginFromCurrentState) {
                self.backLink?.setEnabled(false)
                self.resendCodeButton?.setEnabled(false)
                self.callMeButton?.setEnabled(false)

                self.progressView.alpha = 1
                self.verificationCodeView.alpha = 0
                self.errorLabel.alpha = 0
            }

        } else if !animating, progressView.isAnimating {
            UIView.animate(withDuration: 0.25, delay: 0, options: .beginFromCurrentState) {
                self.backLink?.setEnabled(true)
                self.resendCodeButton?.setEnabled(true)
                self.callMeButton?.setEnabled(true)

                self.progressView.alpha = 0
                self.verificationCodeView.alpha = 1
                self.errorLabel.alpha = 1
            } completion: { _ in
                self.progressView.stopAnimatingImmediately()
            }
        }
    }

    func setHasInvalidCode(_ isInvalid: Bool) {
        UIView.animate(withDuration: 0.25, delay: 0, options: .beginFromCurrentState) {
            self.verificationCodeView.setHasError(isInvalid)
            self.errorLabel.alpha = isInvalid ? 1 : 0
        }
    }

    // MARK: - Code State

    private static var countdownDuration: TimeInterval { 60 }
    var codeCountdownTimer: Timer?
    var codeCountdownStart: NSDate?

    deinit {
        codeCountdownTimer?.invalidate()
    }

    private func startCodeCountdown() {
        codeCountdownStart = NSDate()
        codeCountdownTimer = Timer.weakScheduledTimer(withTimeInterval: 0.25,
                                                      target: self,
                                                      selector: #selector(codeCountdownTimerFired),
                                                      userInfo: nil,
                                                      repeats: true)
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

        if countdownInterval >= Self.countdownDuration {
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
            let countdownRemaining = max(0, Self.countdownDuration - countdownInterval)
            let formattedCountdown = OWSFormat.localizedDurationString(from: round(countdownRemaining))

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
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }

        verificationCodeView.resignFirstResponder()
        viewController.resendCode(asPhoneCall: asPhoneCall)
    }

    // MARK: - Events

    @objc
    func backLinkTapped() {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        viewController.registrationNavigateBack()
    }

    @objc
    func resendCodeButtonTapped() {
        guard canResend else { return }
        Logger.info("")
        resendCode(asPhoneCall: false)
    }

    @objc
    func callMeButtonTapped() {
        guard canResend else { return }
        Logger.info("")
        resendCode(asPhoneCall: true)
    }
}

// MARK: -

extension RegistrationVerificationViewModel: RegistrationVerificationCodeViewDelegate {
    public func codeViewDidChange() {
        AssertIsOnMainThread()

        setHasInvalidCode(false)

        tryToVerify()
    }
}

// MARK: -

extension RegistrationVerificationViewController {
    var canResend: Bool { viewModel.canResend }
    var titleLabel: UILabel? { viewModel.titleLabel }
    var subtitleLabel: UILabel? { viewModel.subtitleLabel }
    var backLink: OWSFlatButton? { viewModel.backLink }
    var backButtonSpacer: UIView? { viewModel.backButtonSpacer }
    var verificationCodeView: RegistrationVerificationCodeView { viewModel.verificationCodeView }
    var resendCodeButton: OWSFlatButton? { viewModel.resendCodeButton }
    var callMeButton: OWSFlatButton? { viewModel.callMeButton }
    var errorLabel: UILabel { viewModel.errorLabel }
    var progressView: AnimatedProgressView { viewModel.progressView }
    var equalSpacerHeightConstraint: NSLayoutConstraint? { viewModel.equalSpacerHeightConstraint }
    var pinnedSpacerHeightConstraint: NSLayoutConstraint? { viewModel.pinnedSpacerHeightConstraint }
    var buttonHeightConstraints: [NSLayoutConstraint] { viewModel.buttonHeightConstraints }
}

// MARK: -

private protocol RegistrationVerificationCodeTextFieldDelegate: AnyObject {
    func textFieldDidDeletePrevious()
}

// MARK: -

// Editing a code should feel seamless, as even though
// the UITextField only lets you edit a single digit at
// a time.  For deletes to work properly, we need to
// detect delete events that would affect the _previous_
// digit.
private class RegistrationVerificationCodeTextField: UITextField {

    fileprivate weak var codeDelegate: RegistrationVerificationCodeTextFieldDelegate?

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

protocol RegistrationVerificationCodeViewDelegate: AnyObject {
    func codeViewDidChange()
}

// MARK: -

// The RegistrationVerificationCodeView is a special "verification code"
// editor that should feel like editing a single piece
// of text (ala UITextField) even though the individual
// digits of the code are visually separated.
//
// We use a separate UILabel for each digit, and move
// around a single UITextfield to let the user edit the
// last/next digit.
class RegistrationVerificationCodeView: UIView {

    weak var delegate: RegistrationVerificationCodeViewDelegate?

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

    private let cellFont: UIFont = UIFont.ows_dynamicTypeLargeTitle1Clamped
    private let interCellSpacing: CGFloat = 8
    private let segmentSpacing: CGFloat = 24
    private let strokeWidth: CGFloat = 3

    private var cellSize: CGSize {
        let vMargin: CGFloat = 4
        let cellHeight: CGFloat = cellFont.lineHeight + vMargin * 2
        let cellWidth: CGFloat = cellHeight * 2 / 3
        return CGSize(width: cellWidth, height: cellHeight)
    }

    override var intrinsicContentSize: CGSize {
        let totalWidth = (CGFloat(digitCount) * (cellSize.width + interCellSpacing)) + segmentSpacing
        let totalHeight = strokeWidth + cellSize.height
        return CGSize(width: totalWidth, height: totalHeight)
    }

    // We use a single text field to edit the "current" digit.
    // The "current" digit is usually the "last"
    fileprivate let textfield = RegistrationVerificationCodeTextField()
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
        textfield.textContentType = .oneTimeCode

        var digitViews = [UIView]()
        (0..<digitCount).forEach { (_) in
            let (digitView, digitLabel, digitStroke) = makeCellView(text: "", hasStroke: true)

            digitLabels.append(digitLabel)
            digitStrokes.append(digitStroke)
            digitViews.append(digitView)
        }

        digitViews.insert(UIView.spacer(withWidth: segmentSpacing), at: 3)

        let stackView = UIStackView(arrangedSubviews: digitViews)
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = interCellSpacing
        addSubview(stackView)
        stackView.autoPinHeightToSuperview()
        stackView.autoHCenterInSuperview()

        self.addSubview(textfield)
    }

    private func makeCellView(text: String, hasStroke: Bool) -> (UIView, UILabel, UIView) {
        let digitView = UIView()

        let digitLabel = UILabel()
        digitLabel.text = text
        digitLabel.font = cellFont
        digitLabel.textColor = Theme.primaryTextColor
        digitLabel.textAlignment = .center
        digitView.addSubview(digitLabel)
        digitLabel.autoCenterInSuperview()

        let strokeColor = (hasStroke ? Theme.secondaryTextAndIconColor : UIColor.clear)
        let strokeView = digitView.addBottomStroke(color: strokeColor, strokeWidth: strokeWidth)
        strokeView.layer.cornerRadius = strokeWidth / 2

        digitView.autoSetDimensions(to: cellSize)
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

    func set(verificationCode: String) {
        digitText = verificationCode

        updateViewState()

        self.delegate?.codeViewDidChange()
    }
}

// MARK: -

extension RegistrationVerificationCodeView: UITextFieldDelegate {
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

extension RegistrationVerificationCodeView: RegistrationVerificationCodeTextFieldDelegate {
    public func textFieldDidDeletePrevious() {
        if digitText.isEmpty { return }
        digitText = digitText.substring(to: currentDigitIndex - 1)

        updateViewState()
    }
}
