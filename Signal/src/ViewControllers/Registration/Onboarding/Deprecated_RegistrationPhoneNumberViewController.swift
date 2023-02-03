//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

@objc
public class Deprecated_RegistrationPhoneNumberViewController: Deprecated_OnboardingBaseViewController {

    // MARK: - Properties

    private lazy var retryAfterFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "m:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")!

        return formatter
    }()

    private enum InlineError {
        case invalidNumber
        case rateLimit(expiration: Date)
    }

    private enum State {
        case interactive
        case verifying_animationDeferred
        case verifying
    }

    private var phoneNumberError: InlineError? {
        didSet { view.setNeedsLayout() }
    }
    private var isReregistering: Bool = false {
        didSet { view.setNeedsLayout() }
    }
    private var state: State = .interactive {
        didSet { view.setNeedsLayout() }
    }

    private var countryName: String { onboardingController.countryState.countryName }
    private var callingCode: String { onboardingController.countryState.callingCode }
    private var countryCode: String { onboardingController.countryState.countryCode }

    private var phoneNumber: String? {
        get { phoneNumberTextField.text }
        set {
            phoneNumberTextField.text = newValue
            applyPhoneNumberFormatting()
        }
    }

    // MARK: - Views

    private var titleSpacer: UIView?

    private let countryNameLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.primaryTextColor
        label.font = UIFont.ows_dynamicTypeBodyClamped
        label.accessibilityIdentifier = "onboarding.phoneNumber." + "countryNameLabel"
        return label
    }()

    private let countryChevron: UIImageView = {
        let countryIconImage = CurrentAppContext().isRTL ? "small_chevron_left" : "small_chevron_right"
        let countryIcon = UIImage(named: countryIconImage)
        let imageView = UIImageView(image: countryIcon?.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = .ows_gray20
        imageView.accessibilityIdentifier = "onboarding.phoneNumber." + "countryImageView"
        return imageView
    }()

    private lazy var callingCodeLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.primaryTextColor
        label.font = UIFont.ows_dynamicTypeBodyClamped
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(countryCodeTapped)))
        label.accessibilityIdentifier = "onboarding.phoneNumber." + "callingCodeLabel"
        return label
    }()

    private let phoneNumberTextField: UITextField = {
        let field = UITextField()
        field.font = UIFont.ows_dynamicTypeBodyClamped
        field.textColor = Theme.primaryTextColor
        field.textAlignment = .left
        field.textContentType = .telephoneNumber

        // There's a bug in iOS 13 where predictions aren't provided for .numberPad
        // keyboard types. Leaving as number pad for now, but if we want to support
        // autofill at the expense of a less appropriate keyboard, here's where it'd
        // be done. See Wisors comment here:
        // https://developer.apple.com/forums/thread/120703
        if #available(iOS 14, *) {
            field.keyboardType = .numberPad
        } else if #available(iOS 13, *) {
            field.keyboardType = .numberPad // .numbersAndPunctuation
        } else {
            field.keyboardType = .numberPad
        }

        field.placeholder = NSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_PLACEHOLDER",
            comment: "Placeholder string for phone number field during registration")
        field.accessibilityIdentifier = "onboarding.phoneNumber." + "phoneNumberTextField"

        return field
    }()

    private var phoneStrokeNormal: UIView?
    private var phoneStrokeError: UIView?

    private let validationWarningLabel: UILabel = {
        let label = UILabel()
        label.textColor = .ows_accentRed
        label.numberOfLines = 0
        label.font = UIFont.ows_dynamicTypeSubheadlineClamped
        label.accessibilityIdentifier = "onboarding.phoneNumber." + "validationWarningLabel"
        return label
    }()

    lazy private var continueButton: OWSFlatButton = {
        let button = self.primaryButton(title: CommonStrings.continueButton, selector: #selector(continuePressed))
        button.accessibilityIdentifier = "onboarding.phoneNumber." + "continueButton"
        return button
    }()

    private var progressSpinner: AnimatedProgressView = {
        let spinner = AnimatedProgressView()
        // We'll handle hiding animations ourselves
        spinner.hidesWhenStopped = false
        return spinner
    }()

    private var viewsToHideDuringVerification: [UIView]?
    private var equalSpacerHeightConstraint: NSLayoutConstraint?
    private var pinnedSpacerHeightConstraint: NSLayoutConstraint?
    private var keyboardBottomConstraint: NSLayoutConstraint?

    // MARK: - View Lifecycle

    override public func loadView() {
        view = UIView()
        view.backgroundColor = Theme.backgroundColor
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        let proxyButton = ContextMenuButton(contextMenu: .init([
            .init(
                title: NSLocalizedString(
                    "USE_PROXY_BUTTON",
                    comment: "Button to activate the signal proxy"
                ),
                handler: { [weak self] _ in
                    guard let self = self else { return }
                    let vc = ProxySettingsViewController()
                    self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
                }
            )
        ]))
        proxyButton.showsContextMenuAsPrimaryAction = true
        proxyButton.setImage(Theme.iconImage(.more24), for: .normal)
        proxyButton.tintColor = Theme.primaryIconColor
        proxyButton.autoSetDimensions(to: .square(40))

        view.addSubview(proxyButton)
        proxyButton.autoPinEdge(toSuperviewMargin: .trailing)
        proxyButton.autoPinEdge(toSuperviewMargin: .top)

        // Setup subviews and stack views
        let titleString = (Self.tsAccountManager.isReregistering
                           ? NSLocalizedString(
                            "ONBOARDING_PHONE_NUMBER_TITLE_REREGISTERING",
                            comment: "Title of the 'onboarding phone number' view when the user is re-registering.")
                            : NSLocalizedString(
                                "ONBOARDING_PHONE_NUMBER_TITLE",
                                comment: "Title of the 'onboarding phone number' view."))

        let titleLabel = self.createTitleLabel(text: titleString)

        let countryRow = UIStackView(arrangedSubviews: [countryNameLabel, countryChevron])
        countryRow.axis = .horizontal
        countryRow.alignment = .center
        countryRow.spacing = 10
        countryRow.isUserInteractionEnabled = true
        countryRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(countryRowTapped)))
        _ = countryRow.addBottomStroke(color: .ows_gray20, strokeWidth: CGHairlineWidth())
        countryChevron.setContentHuggingHorizontalHigh()
        countryChevron.setCompressionResistanceHigh()

        let phoneNumberRow = UIStackView(arrangedSubviews: [callingCodeLabel, phoneNumberTextField])
        phoneNumberRow.axis = .horizontal
        phoneNumberRow.alignment = .center
        phoneNumberRow.spacing = 10
        phoneStrokeNormal = phoneNumberRow.addBottomStroke(color: .ows_gray20, strokeWidth: CGHairlineWidth())
        phoneStrokeError = phoneNumberRow.addBottomStroke(color: .ows_accentRed, strokeWidth: 1)
        callingCodeLabel.autoSetDimension(.width, toSize: 45, relation: .greaterThanOrEqual)
        callingCodeLabel.setCompressionResistanceHigh()
        callingCodeLabel.setContentHuggingHorizontalHigh()

        let titleSpacer = SpacerView(preferredHeight: 4)
        let phoneNumberSpacer = SpacerView(preferredHeight: 11)
        let warningLabelSpacer = SpacerView(preferredHeight: 4)
        let bottomSpacer = SpacerView(preferredHeight: 4)
        self.titleSpacer = titleSpacer

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel, titleSpacer,
            countryRow, phoneNumberRow, phoneNumberSpacer,
            validationWarningLabel, warningLabelSpacer,
            Deprecated_OnboardingBaseViewController.horizontallyWrap(primaryButton: continueButton), bottomSpacer
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill

        primaryView.addSubview(stackView)
        primaryView.addSubview(progressSpinner)
        viewsToHideDuringVerification = [countryRow, phoneNumberRow, validationWarningLabel]

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
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            stackView.autoPinEdge(toSuperviewMargin: .top)
        }
        stackView.autoPinWidthToSuperviewMargins()
        keyboardBottomConstraint = stackView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)
        progressSpinner.autoCenterInSuperview()

        // For when things get *really* cramped, here's what's required:
        [titleLabel,
         countryNameLabel,
         countryChevron,
         callingCodeLabel,
         phoneNumberTextField,
         continueButton].forEach { $0.setCompressionResistanceVerticalHigh() }
        equalSpacerHeightConstraint = titleSpacer.autoMatch(.height, to: .height, of: warningLabelSpacer)
        pinnedSpacerHeightConstraint = titleSpacer.autoSetDimension(.height, toSize: 0)
        pinnedSpacerHeightConstraint?.isActive = false

        // Views should ideally have a minimum amount of padding, but it's less required. In preferred order:
        bottomSpacer.setContentCompressionResistancePriority(.required - 10, for: .vertical)
        NSLayoutConstraint.autoSetPriority(.required - 20) {
            phoneNumberRow.autoSetDimension(.height, toSize: 50)
        }
        NSLayoutConstraint.autoSetPriority(.required - 30) {
            countryRow.autoSetDimension(.height, toSize: 50)
        }
        titleSpacer.setContentCompressionResistancePriority(.required - 40, for: .vertical)
        warningLabelSpacer.setContentCompressionResistancePriority(.required - 50, for: .vertical)

        // Ideally we'll try and satisfy these
        phoneNumberSpacer.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            bottomSpacer.autoSetDimension(.height, toSize: 16, relation: .greaterThanOrEqual)
        }

        // If we're flush with space, bump up the keyboard spacer to the bottom layout margins
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            bottomSpacer.autoSetDimension(.height, toSize: primaryLayoutMargins.bottom)
        }
        updateValidationWarningLabelCompressionResistance()

        // And if we have so much space we don't know what to do with it, grow the space between
        // the warning label and the continue button. Usually the top space will grow along with
        // it because of the equal spacing constraint
        warningLabelSpacer.setContentHuggingPriority(.init(100), for: .vertical)

        titleLabel.accessibilityIdentifier = "onboarding.phoneNumber." + "titleLabel"
        phoneNumberRow.accessibilityIdentifier = "onboarding.phoneNumber." + "phoneNumberRow"
        countryRow.accessibilityIdentifier = "onboarding.phoneNumber." + "countryRow"
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        super.keyboardObservationBehavior = .whileLifecycleVisible

        phoneNumberTextField.delegate = self
        phoneNumberTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        populateDefaults()
    }

    var isAppearing = false
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isAppearing = true

        updateViewState(animated: false)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        phoneNumberTextField.becomeFirstResponder()
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateViewState(animated: !isAppearing)
        isAppearing = false
    }

    public override func keyboardFrameDidChange(_ newFrame: CGRect, animationDuration: TimeInterval, animationOptions: UIView.AnimationOptions) {
        super.keyboardFrameDidChange(newFrame, animationDuration: animationDuration, animationOptions: animationOptions)
        var needsLayout = false

        let isDismissing = (newFrame.height == 0)
        if isDismissing, equalSpacerHeightConstraint?.isActive == true {
            pinnedSpacerHeightConstraint?.constant = titleSpacer?.height ?? 0
            equalSpacerHeightConstraint?.isActive = false
            pinnedSpacerHeightConstraint?.isActive = true
            needsLayout = true
        }

        if !isDismissing, equalSpacerHeightConstraint?.isActive == false {
            pinnedSpacerHeightConstraint?.isActive = false
            equalSpacerHeightConstraint?.isActive = true
            needsLayout = true
        }

        if needsLayout {
            view.layoutIfNeeded()
        }
    }

    // MARK: - View population

    private func populateDefaults() {
        if let reregistrationNumber = fetchReregistrationNumberIfAvailable() {
            phoneNumber = reregistrationNumber
            isReregistering = true

        } else if let lastRegisteredPhoneNumber = Deprecated_OnboardingController.lastRegisteredPhoneNumber(),
                  !lastRegisteredPhoneNumber.isEmpty {
            phoneNumber = lastRegisteredPhoneNumber

        } else if let existingNumber = onboardingController.phoneNumber {
            phoneNumber = existingNumber.userInput
        }
    }

    private func fetchReregistrationNumberIfAvailable() -> String? {
        // If re-registering, pre-populate the country (country code, calling code, country name)
        // and phone number state.
        guard tsAccountManager.isReregistering else {
            return nil
        }
        guard let phoneNumberE164 = tsAccountManager.reregistrationPhoneNumber() else {
            owsFailDebug("Could not resume re-registration; missing phone number.")
            return nil
        }
        if phoneNumberE164.isEmpty {
            owsFailDebug("Could not resume re-registration; invalid phoneNumberE164.")
            return nil
        }
        guard let parsedPhoneNumber = PhoneNumber(fromE164: phoneNumberE164) else {
            owsFailDebug("Could not resume re-registration; couldn't parse phoneNumberE164.")
            return nil
        }
        guard let callingCodeNumeric = parsedPhoneNumber.getCountryCode() else {
            owsFailDebug("Could not resume re-registration; missing callingCode.")
            return nil
        }
        let callingCode = "\(COUNTRY_CODE_PREFIX)\(callingCodeNumeric)"
        let countryCodes: [String] = phoneNumberUtil.countryCodes(fromCallingCode: callingCode)
        guard let countryCode = countryCodes.first else {
            owsFailDebug("Could not resume re-registration; unknown countryCode.")
            return nil
        }
        let countryName = PhoneNumberUtil.countryName(fromCountryCode: countryCode)
        if !phoneNumberE164.hasPrefix(callingCode) {
            owsFailDebug("Could not resume re-registration; non-matching calling code.")
            return nil
        }
        let phoneNumberWithoutCallingCode = phoneNumberE164.substring(from: callingCode.count)

        if countryCode.isEmpty {
            owsFailDebug("Invalid country code.")
            return nil
        }
        if countryName.isEmpty {
            owsFailDebug("Invalid country name.")
            return nil
        }
        if callingCode.isEmpty {
            owsFailDebug("Invalid calling code.")
            return nil
        }

        let countryState = RegistrationCountryState(countryName: countryName, callingCode: callingCode, countryCode: countryCode)
        onboardingController.update(countryState: countryState)
        return phoneNumberWithoutCallingCode
    }

    private func updateViewState(animated: Bool = true) {
        AssertIsOnMainThread()

        let showError = (phoneNumberError != nil)
        let showSpinner: Bool
        switch state {
        case .interactive:
            showSpinner = false
        case .verifying_animationDeferred:
            showSpinner = false
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
                guard self.state == .verifying_animationDeferred else { return }
                self.state = .verifying
            }
        case .verifying:
            showSpinner = true
        }

        // Update non-animated properties immediately
        countryNameLabel.text = countryName
        callingCodeLabel.text = callingCode
        updateValidationLabel()

        phoneNumberTextField.isEnabled = !isReregistering
        continueButton.setEnabled(state == .interactive)

        if showSpinner, !progressSpinner.isAnimating {
            progressSpinner.startAnimating()
        } else if !showSpinner, progressSpinner.isAnimating {
            progressSpinner.stopAnimatingImmediately()
        }

         let animationBlock = {
            if showSpinner {
                self.viewsToHideDuringVerification?.forEach { $0.alpha = 0 }
                self.progressSpinner.alpha = 1

            } else {
                // Do this first, since there's overlap with the views below
                self.viewsToHideDuringVerification?.forEach { $0.alpha = 1 }

                self.progressSpinner.alpha = 0
                self.phoneStrokeNormal?.alpha = showError ? 0 : 1
                self.phoneStrokeError?.alpha = showError ? 1 : 0
                self.validationWarningLabel.alpha = showError ? 1 : 0
                self.updateValidationWarningLabelCompressionResistance()

                self.primaryView.layoutIfNeeded()
            }
        }

        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: .beginFromCurrentState, animations: animationBlock)
        } else {
            animationBlock()
        }
    }

    private func updateValidationLabel() {
        switch phoneNumberError {
        case .invalidNumber:
            validationWarningLabel.text = NSLocalizedString(
                "ONBOARDING_PHONE_NUMBER_VALIDATION_WARNING",
                comment: "Label indicating that the phone number is invalid in the 'onboarding phone number' view.")

        case let .rateLimit(expiration: expirationDate) where expirationDate > Date():
            let rateLimitFormat = NSLocalizedString(
                "ONBOARDING_PHONE_NUMBER_RATE_LIMIT_WARNING_FORMAT",
                comment: "Label indicating that registration has been ratelimited. Embeds {{remaining time string}}.")

            let timeRemaining = expirationDate.timeIntervalSinceNow
            let durationString = retryAfterFormatter.string(from: Date(timeIntervalSinceReferenceDate: timeRemaining))
            validationWarningLabel.text = String(format: rateLimitFormat, durationString)

            // Repeatedly update the validation warning label. Eventually the where condition above
            // (expirationDate > Date()) will no longer hold and the error will be cleared
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
                self?.updateValidationLabel()
            }

        case let .rateLimit(expiration: expirationDate) where expirationDate <= Date():
            // Rate limit expiration is in the past, clear the error
            phoneNumberError = nil
        default:
            // Both of our text blobs are about the same size. Ideally we don't want to move views when the error appears
            // So we pre-populate with filler text to try and maintain an approximately consistent intrinsic content size
            // If there's no error, the view will be hidden and compression resistance reduced.
            validationWarningLabel.text = NSLocalizedString(
                "ONBOARDING_PHONE_NUMBER_VALIDATION_WARNING",
                comment: "Label indicating that the phone number is invalid in the 'onboarding phone number' view.")
        }
    }

    private func updateValidationWarningLabelCompressionResistance() {
        // validationWarningLabel's compression resistance will toggle between high priority and low priority
        // as it becomes visible. Ideally, we want to make space for it to avoid layout adjustments when
        // showing the error. But when space constrained, it's the first thing we'll give up.

        let desiredResistance: UILayoutPriority = phoneNumberError != nil ? .required - 1 : .defaultLow - 1
        self.validationWarningLabel.setContentCompressionResistancePriority(desiredResistance, for: .vertical)
    }

    private func applyPhoneNumberFormatting() {
        AssertIsOnMainThread()
        ViewControllerUtils.reformatPhoneNumber(phoneNumberTextField, callingCode: callingCode)
    }

     // MARK: - Events

    @objc
    func countryRowTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        showCountryPicker()
    }

    @objc
    func countryCodeTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        showCountryPicker()
    }

    @objc
    func continuePressed() {
        Logger.info("")

        parseAndTryToRegister()
    }

    // MARK: - Country Picker

    private func showCountryPicker() {
        guard !isReregistering else { return }

        let countryCodeController = CountryCodeViewController()
        countryCodeController.countryCodeDelegate = self
        countryCodeController.interfaceOrientationMask = UIDevice.current.isIPad ? .all : .portrait
        let navigationController = OWSNavigationController(rootViewController: countryCodeController)
        self.present(navigationController, animated: true, completion: nil)
    }

    // MARK: - Register

    private func parseAndTryToRegister() {
        guard let phoneNumberText = phoneNumber?.ows_stripped(), !phoneNumberText.isEmpty else {
            phoneNumberError = .invalidNumber
            OWSActionSheets.showActionSheet(
                title: NSLocalizedString(
                    "REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_TITLE",
                    comment: "Title of alert indicating that users needs to enter a phone number to register."),
                message: NSLocalizedString(
                    "REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_MESSAGE",
                    comment: "Message of alert indicating that users needs to enter a phone number to register."))
            return
        }

        guard
            let localNumber = PhoneNumber.tryParsePhoneNumber(
                fromUserSpecifiedText: phoneNumberText,
                callingCode: callingCode
            ),
            !localNumber.toE164().isEmpty,
            PhoneNumberValidator().isValidForRegistration(phoneNumber: localNumber)
        else {

            phoneNumberError = .invalidNumber
            OWSActionSheets.showActionSheet(
                title: NSLocalizedString(
                    "REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_TITLE",
                    comment: "Title of alert indicating that users needs to enter a valid phone number to register."),
                message: NSLocalizedString(
                    "REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_MESSAGE",
                    comment: "Message of alert indicating that users needs to enter a valid phone number to register."))
            return
        }

        if Self.tsAccountManager.isReregistering {
            self.requestVerification(with: RegistrationPhoneNumber(e164: localNumber.toE164(), userInput: phoneNumberText))
            return
        }

        let formattedNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: localNumber.toE164())
        let progressViewFormat = NSLocalizedString(
            "REGISTRATION_VIEW_PHONE_NUMBER_SPINNER_LABEL_FORMAT",
            comment: "Label for the progress spinner shown during phone number registration. Embeds {{phone number}}.")
        progressSpinner.loadingText = String(format: progressViewFormat, formattedNumber)

        // Preemptively resign so we don't reacquire first responder status between the alert
        // dismissal and the progress view animation
        self.phoneNumberTextField.resignFirstResponder()
        self.onboardingController.presentPhoneNumberConfirmationSheet(from: self, number: formattedNumber) { [weak self] shouldContinue in
            guard let self = self else { return }

            if shouldContinue {
                self.requestVerification(with: RegistrationPhoneNumber(e164: localNumber.toE164(), userInput: phoneNumberText))
            } else {
                // User wants to edit, retake first responder
                self.phoneNumberTextField.becomeFirstResponder()
            }
        }
    }

    private func requestVerification(with phoneNumber: RegistrationPhoneNumber) {
        self.onboardingController.update(phoneNumber: phoneNumber)

        self.verificationAnimation(shouldPlay: true)
        self.onboardingController.requestVerification(fromViewController: self, isSMS: true) { [weak self] willDismiss, error in
            guard let self = self else { return }
            self.verificationAnimation(shouldPlay: false)

            // If the onboarding controller is not transitioning away from us, retake first responder
            guard !willDismiss else { return }
            self.phoneNumberTextField.becomeFirstResponder()

            if let error = error, error.httpStatusCode == 413 || error.httpStatusCode == 429 {
                // If we're not handed a retry-after date directly from the server, either
                // use the existing date we already have or construct a new date 5 min from now
                let retryAfterDate = error.httpRetryAfterDate ?? {
                    if case let .rateLimit(existingRetryAfter) = self.phoneNumberError {
                        return existingRetryAfter
                    } else {
                        return Date(timeIntervalSinceNow: 300)
                    }
                }()
                self.phoneNumberError = .rateLimit(expiration: retryAfterDate)

                // TODO: Once notification work is complete, uncomment this.
                // self.notificationPresenter.notifyUserOfIncompleteRegistration(on: retryAfterDate)
            }
        }
    }

    private func verificationAnimation(shouldPlay: Bool) {
        if shouldPlay {
            if state == .interactive {
                state = .verifying_animationDeferred
            }
        } else {
            state = .interactive
        }
    }
}

// MARK: -

extension Deprecated_RegistrationPhoneNumberViewController: UITextFieldDelegate {
    public func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String) -> Bool {

        if case .invalidNumber = phoneNumberError {
            phoneNumberError = nil
        }

        // If ViewControllerUtils applied the edit on our behalf, inform UIKit
        // so the edit isn't applied twice.
        return ViewControllerUtils.phoneNumber(
            textField,
            shouldChangeCharactersIn: range,
            replacementString: string,
            callingCode: callingCode)
    }

    @objc
    private func textFieldDidChange(_ textField: UITextField) {
        applyPhoneNumberFormatting()
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        parseAndTryToRegister()
        return false
    }
}

// MARK: -

extension Deprecated_RegistrationPhoneNumberViewController: CountryCodeViewControllerDelegate {
    public func countryCodeViewController(_ vc: CountryCodeViewController,
                                          didSelectCountry countryState: RegistrationCountryState) {
        onboardingController.update(countryState: countryState)
        updateViewState(animated: false)
    }
}
