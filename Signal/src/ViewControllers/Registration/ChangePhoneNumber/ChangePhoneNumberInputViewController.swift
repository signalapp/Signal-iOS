//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

class ChangePhoneNumberInputViewController: OWSTableViewController2 {

    private let changePhoneNumberController: ChangePhoneNumberController
    private let oldValueViews: ChangePhoneNumberValueViews
    private let newValueViews: ChangePhoneNumberValueViews

    public init(changePhoneNumberController: ChangePhoneNumberController) {
        self.changePhoneNumberController = changePhoneNumberController

        self.oldValueViews = ChangePhoneNumberValueViews(.oldValue,
                                                         changePhoneNumberController: changePhoneNumberController)
        self.newValueViews = ChangePhoneNumberValueViews(.newValue,
                                                         changePhoneNumberController: changePhoneNumberController)

        super.init()

        oldValueViews.delegate = self
        newValueViews.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_VIEW_TITLE",
                                  comment: "Title for the 'change phone number' views in settings.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didPressCancel)
        )

        updateTableContents()
    }

    fileprivate func updateNavigationBar() {
        let doneItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(didTapContinue)
        )
        doneItem.isEnabled = canContinue
        navigationItem.rightBarButtonItem = doneItem
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    public override func applyTheme() {
        super.applyTheme()

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        contents.addSection(buildTableSection(valueViews: oldValueViews))
        contents.addSection(buildTableSection(valueViews: newValueViews))

        self.contents = contents

        updateNavigationBar()
    }

    fileprivate func buildTableSection(valueViews: ChangePhoneNumberValueViews) -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = valueViews.sectionHeaderTitle

        let countryCodeFormat = NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_COUNTRY_CODE_FORMAT",
                                                  comment: "Format for the 'country code' in the 'change phone number' settings. Embeds: {{ %1$@ the numeric country code prefix, %2$@ the country code abbreviation }}.")
        let countryCodeFormatted = String(format: countryCodeFormat, valueViews.callingCode, valueViews.countryCode)
        section.add(.item(name: NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_COUNTRY_CODE_FIELD",
                                                  comment: "Label for the 'country code' row in the 'change phone number' settings."),
                          textColor: Theme.primaryTextColor,
                          accessoryText: countryCodeFormatted,
                          accessoryType: .disclosureIndicator,
                          accessibilityIdentifier: valueViews.accessibilityIdentifier_PhoneNumber) { [weak self] in
            self?.showCountryCodePicker(valueViews: valueViews)
        })
        section.add(.item(name: NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_PHONE_NUMBER_FIELD",
                                                  comment: "Label for the 'country code' row in the 'change phone number' settings."),
                          textColor: Theme.primaryTextColor,
                          accessoryView: valueViews.phoneNumberTextField,
                          accessibilityIdentifier: valueViews.accessibilityIdentifier_CountryCode))

        return section
    }

    fileprivate func showCountryCodePicker(valueViews: ChangePhoneNumberValueViews) {
        let countryCodeController = CountryCodeViewController()
        countryCodeController.countryCodeDelegate = valueViews
        countryCodeController.interfaceOrientationMask = UIDevice.current.isIPad ? .all : .portrait
        let navigationController = OWSNavigationController(rootViewController: countryCodeController)
        self.present(navigationController, animated: true, completion: nil)
    }

    // MARK: -

    private var canContinue: Bool {
        tryToParse(showErrors: false) != nil
    }

    private struct PhoneNumbers {
        let oldPhoneNumber: PhoneNumber
        let newPhoneNumber: PhoneNumber
    }

    private func tryToParse(showErrors: Bool) -> PhoneNumbers? {
        // TODO: Show separate errors for old and new phone numbers.

        func tryToParse(_ valueViews: ChangePhoneNumberValueViews) -> PhoneNumber? {
            switch valueViews.tryToParse() {
            case .noNumber:
                if showErrors {
                    showNoPhoneNumberAlert()
                }
                return nil
            case .invalidNumber:
                if showErrors {
                    showInvalidPhoneNumberAlert()
                }
                return nil
                //        case .rateLimit:
                //            return
            case .validNumber(let phoneNumber):
                return phoneNumber
            }
        }

        guard let oldPhoneNumber = tryToParse(oldValueViews) else {
            return nil
        }
        guard let newPhoneNumber = tryToParse(newValueViews) else {
            return nil
        }

        Logger.verbose("oldPhoneNumber: \(oldPhoneNumber.toE164())")
        Logger.verbose("newPhoneNumber: \(newPhoneNumber.toE164())")

        return PhoneNumbers(oldPhoneNumber: oldPhoneNumber, newPhoneNumber: newPhoneNumber)
    }

    private func tryToContinue() {
        AssertIsOnMainThread()

        // TODO: Show separate errors for old and new phone numbers.

        guard let phoneNumbers = tryToParse(showErrors: true) else {
            return
        }

        oldValueViews.phoneNumberTextField.resignFirstResponder()
        newValueViews.phoneNumberTextField.resignFirstResponder()

        let vc = ChangePhoneNumberConfirmViewController(changePhoneNumberController: changePhoneNumberController,
                                                        oldPhoneNumber: phoneNumbers.oldPhoneNumber,
                                                        newPhoneNumber: phoneNumbers.newPhoneNumber)
        self.navigationController?.pushViewController(vc, animated: true)
    }

    private func showNoPhoneNumberAlert() {
        OWSActionSheets.showActionSheet(
            title: NSLocalizedString(
                "REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_TITLE",
                comment: "Title of alert indicating that users needs to enter a phone number to register."),
            message: NSLocalizedString(
                "REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_MESSAGE",
                comment: "Message of alert indicating that users needs to enter a phone number to register."))
    }

    private func showInvalidPhoneNumberAlert() {
        OWSActionSheets.showActionSheet(
            title: NSLocalizedString(
                "REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_TITLE",
                comment: "Title of alert indicating that users needs to enter a valid phone number to register."),
            message: NSLocalizedString(
                "REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_MESSAGE",
                comment: "Message of alert indicating that users needs to enter a valid phone number to register."))
    }

    // MARK: - Events

    @objc
    private func didPressCancel() {
        AssertIsOnMainThread()

        changePhoneNumberController.cancelFlow(viewController: self)
    }

    @objc
    private func didTapContinue() {
        AssertIsOnMainThread()

        tryToContinue()
    }
}

// MARK: -

// @objc
// public class RegistrationPhoneNumberViewController: OnboardingBaseViewController {
//
//    // MARK: - Properties
//
//    private lazy var retryAfterFormatter: DateFormatter = {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "m:ss"
//        formatter.timeZone = TimeZone(identifier: "UTC")!
//
//        return formatter
//    }()

//    private enum State {
//        case interactive
//        case verifying_animationDeferred
//        case verifying
//    }
//
//    private var isReregistering: Bool = false {
//        didSet { view.setNeedsLayout() }
//    }
//    private var state: State = .interactive {
//        didSet { view.setNeedsLayout() }
//    }
//
//
//    // MARK: - Views
//
//    private var titleSpacer: UIView?
//
//    private let countryNameLabel: UILabel = {
//        let label = UILabel()
//        label.textColor = Theme.primaryTextColor
//        label.font = UIFont.ows_dynamicTypeBodyClamped
//        label.accessibilityIdentifier = "onboarding.phoneNumber." + "countryNameLabel"
//        return label
//    }()
//
//    private let countryChevron: UIImageView = {
//        let countryIconImage = CurrentAppContext().isRTL ? "small_chevron_left" : "small_chevron_right"
//        let countryIcon = UIImage(named: countryIconImage)
//        let imageView = UIImageView(image: countryIcon?.withRenderingMode(.alwaysTemplate))
//        imageView.tintColor = .ows_gray20
//        imageView.accessibilityIdentifier = "onboarding.phoneNumber." + "countryImageView"
//        return imageView
//    }()
//
//    private let callingCodeLabel: UILabel = {
//        let label = UILabel()
//        label.textColor = Theme.primaryTextColor
//        label.font = UIFont.ows_dynamicTypeBodyClamped
//        label.isUserInteractionEnabled = true
//        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(countryCodeTapped)))
//        label.accessibilityIdentifier = "onboarding.phoneNumber." + "callingCodeLabel"
//        return label
//    }()
//
//    private var phoneStrokeNormal: UIView?
//    private var phoneStrokeError: UIView?
//
//    private let validationWarningLabel: UILabel = {
//        let label = UILabel()
//        label.textColor = .ows_accentRed
//        label.numberOfLines = 0
//        label.font = UIFont.ows_dynamicTypeSubheadlineClamped
//        label.accessibilityIdentifier = "onboarding.phoneNumber." + "validationWarningLabel"
//        return label
//    }()
//
//    lazy private var continueButton: OWSFlatButton = {
//        let button = self.primaryButton(title: CommonStrings.continueButton, selector: #selector(continuePressed))
//        button.accessibilityIdentifier = "onboarding.phoneNumber." + "continueButton"
//        return button
//    }()
//
//    private var progressSpinner: AnimatedProgressView = {
//        let spinner = AnimatedProgressView()
//        // We'll handle hiding animations ourselves
//        spinner.hidesWhenStopped = false
//        return spinner
//    }()
//
//    private var viewsToHideDuringVerification: [UIView]?
//    private var equalSpacerHeightConstraint: NSLayoutConstraint?
//    private var pinnedSpacerHeightConstraint: NSLayoutConstraint?
//    private var keyboardBottomConstraint: NSLayoutConstraint?
//
//    // MARK: - View Lifecycle
//
//    override public func loadView() {
//        view = UIView()
//        view.backgroundColor = Theme.backgroundColor
//        view.addSubview(primaryView)
//        primaryView.autoPinEdgesToSuperviewEdges()
//
//        // Setup subviews and stack views
//        let titleString = (Self.tsAccountManager.isReregistering
//                           ? NSLocalizedString(
//                            "ONBOARDING_PHONE_NUMBER_TITLE_REREGISTERING",
//                            comment: "Title of the 'onboarding phone number' view when the user is re-registering.")
//                           : NSLocalizedString(
//                            "ONBOARDING_PHONE_NUMBER_TITLE",
//                            comment: "Title of the 'onboarding phone number' view."))
//
//        let titleLabel = self.createTitleLabel(text: titleString)
//
//        let countryRow = UIStackView(arrangedSubviews: [countryNameLabel, countryChevron])
//        countryRow.axis = .horizontal
//        countryRow.alignment = .center
//        countryRow.spacing = 10
//        countryRow.isUserInteractionEnabled = true
//        countryRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(countryRowTapped)))
//        _ = countryRow.addBottomStroke(color: .ows_gray20, strokeWidth: CGHairlineWidth())
//        countryChevron.setContentHuggingHorizontalHigh()
//        countryChevron.setCompressionResistanceHigh()
//
//        let phoneNumberRow = UIStackView(arrangedSubviews: [callingCodeLabel, phoneNumberTextField])
//        phoneNumberRow.axis = .horizontal
//        phoneNumberRow.alignment = .center
//        phoneNumberRow.spacing = 10
//        phoneStrokeNormal = phoneNumberRow.addBottomStroke(color: .ows_gray20, strokeWidth: CGHairlineWidth())
//        phoneStrokeError = phoneNumberRow.addBottomStroke(color: .ows_accentRed, strokeWidth: 1)
//        callingCodeLabel.autoSetDimension(.width, toSize: 45, relation: .greaterThanOrEqual)
//        callingCodeLabel.setCompressionResistanceHigh()
//        callingCodeLabel.setContentHuggingHorizontalHigh()
//
//        let titleSpacer = SpacerView(preferredHeight: 4)
//        let phoneNumberSpacer = SpacerView(preferredHeight: 11)
//        let warningLabelSpacer = SpacerView(preferredHeight: 4)
//        let bottomSpacer = SpacerView(preferredHeight: 4)
//        self.titleSpacer = titleSpacer
//
//        let stackView = UIStackView(arrangedSubviews: [
//            titleLabel, titleSpacer,
//            countryRow, phoneNumberRow, phoneNumberSpacer,
//            validationWarningLabel, warningLabelSpacer,
//            OnboardingBaseViewController.horizontallyWrap(primaryButton: continueButton), bottomSpacer
//        ])
//        stackView.axis = .vertical
//        stackView.alignment = .fill
//
//        primaryView.addSubview(stackView)
//        primaryView.addSubview(progressSpinner)
//        viewsToHideDuringVerification = [countryRow, phoneNumberRow, validationWarningLabel]
//
//        // Here comes a bunch of autolayout prioritization to make sure we can fit on an iPhone 5s/SE
//        // It's complicated, but there are a few rules that help here:
//        // - First, set required constraints on everything that's *critical* for usability
//        // - Next, progressively add non-required constraints that are nice to have, but not critical.
//        // - Finally, pick one and only one view in the stack and set its contentHugging explicitly low
//        //
//        // - Non-required constraints should each have a unique priority. This is important to resolve
//        //   autolayout ambiguity e.g. I have 10pts of extra space, and two equally weighted constraints
//        //   that both consume 8pts. What do I satisfy?
//        // - Every view should have an intrinsicContentSize. Content Hugging and Content Compression
//        //   don't mean much without a content size.
//        stackView.autoPinEdge(toSuperviewSafeArea: .top, withInset: 0, relation: .greaterThanOrEqual)
//        stackView.autoPinEdge(toSuperviewMargin: .top).priority = .defaultHigh
//        stackView.autoPinWidthToSuperviewMargins()
//        keyboardBottomConstraint = autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)
//        progressSpinner.autoCenterInSuperview()
//
//        // For when things get *really* cramped, here's what's required:
//        [titleLabel,
//         countryNameLabel,
//         countryChevron,
//         callingCodeLabel,
//         phoneNumberTextField,
//         continueButton].forEach { $0.setCompressionResistanceVerticalHigh() }
//        equalSpacerHeightConstraint = titleSpacer.autoMatch(.height, to: .height, of: warningLabelSpacer)
//        pinnedSpacerHeightConstraint = titleSpacer.autoSetDimension(.height, toSize: 0)
//        pinnedSpacerHeightConstraint?.isActive = false
//
//        // Views should ideally have a minimum amount of padding, but it's less required. In preferred order:
//        bottomSpacer.setContentCompressionResistancePriority(.required - 10, for: .vertical)
//        phoneNumberRow.autoSetDimension(.height, toSize: 50).priority = .required - 20
//        countryRow.autoSetDimension(.height, toSize: 50).priority = .required - 30
//        titleSpacer.setContentCompressionResistancePriority(.required - 40, for: .vertical)
//        warningLabelSpacer.setContentCompressionResistancePriority(.required - 50, for: .vertical)
//
//        // Ideally we'll try and satisfy these
//        phoneNumberSpacer.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
//        bottomSpacer.autoSetDimension(.height, toSize: 16, relation: .greaterThanOrEqual).priority = .defaultHigh
//
//        // If we're flush with space, bump up the keyboard spacer to the bottom layout margins
//        bottomSpacer.autoSetDimension(.height, toSize: primaryLayoutMargins.bottom).priority = .defaultLow
//        updateValidationWarningLabelCompressionResistance()
//
//        // And if we have so much space we don't know what to do with it, grow the space between
//        // the warning label and the continue button. Usually the top space will grow along with
//        // it because of the equal spacing constraint
//        warningLabelSpacer.setContentHuggingPriority(.init(100), for: .vertical)
//
//        titleLabel.accessibilityIdentifier = "onboarding.phoneNumber." + "titleLabel"
//        phoneNumberRow.accessibilityIdentifier = "onboarding.phoneNumber." + "phoneNumberRow"
//        countryRow.accessibilityIdentifier = "onboarding.phoneNumber." + "countryRow"
//    }
//
//    public override func viewDidLoad() {
//        super.viewDidLoad()
//
//        phoneNumberTextField.delegate = self
//        phoneNumberTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
//        populateDefaults()
//    }
//
//    var isAppearing = false
//    public override func viewWillAppear(_ animated: Bool) {
//        super.viewWillAppear(animated)
//        shouldIgnoreKeyboardChanges = false
//        isAppearing = true
//
//        updateViewState(animated: false)
//    }
//
//    public override func viewDidAppear(_ animated: Bool) {
//        super.viewDidAppear(animated)
//        phoneNumberTextField.becomeFirstResponder()
//    }
//
//    public override func viewWillDisappear(_ animated: Bool) {
//        super.viewWillDisappear(animated)
//        shouldIgnoreKeyboardChanges = true
//    }
//
//    public override func viewWillLayoutSubviews() {
//        super.viewWillLayoutSubviews()
//        updateViewState(animated: !isAppearing)
//        isAppearing = false
//    }
//
//    public override func updateBottomLayoutConstraint(fromInset before: CGFloat, toInset after: CGFloat) {
//        var needsLayout = false
//
//        let isDismissing = (after == 0)
//        if isDismissing, equalSpacerHeightConstraint?.isActive == true {
//            pinnedSpacerHeightConstraint?.constant = titleSpacer?.height ?? 0
//            equalSpacerHeightConstraint?.isActive = false
//            pinnedSpacerHeightConstraint?.isActive = true
//            needsLayout = true
//        }
//
//        // Ignore any minor decreases in height. We want to grow to accomodate the
//        // QuickType bar, but shrinking in response to its dismissal is a bit much.
//        let isKeyboardGrowing = after > -(keyboardBottomConstraint?.constant ?? 0.0)
//        let isSignificantlyShrinking = ((before - after) / UIScreen.main.bounds.height) > 0.1
//        if isKeyboardGrowing || isSignificantlyShrinking || isDismissing {
//            super.updateBottomLayoutConstraint(fromInset: before, toInset: after)
//            needsLayout = true
//        }
//
//        if !isDismissing, equalSpacerHeightConstraint?.isActive == false {
//            pinnedSpacerHeightConstraint?.isActive = false
//            equalSpacerHeightConstraint?.isActive = true
//            needsLayout = true
//        }
//
//        if needsLayout {
//            view.layoutIfNeeded()
//        }
//    }
//
//    // MARK: - View population
//
//    private func populateDefaults() {
//        if let reregistrationNumber = fetchReregistrationNumberIfAvailable() {
//            phoneNumber = reregistrationNumber
//            isReregistering = true
//
//        } else if let lastRegisteredPhoneNumber = OnboardingController.lastRegisteredPhoneNumber(),
//                  lastRegisteredPhoneNumber.count > 0 {
//            phoneNumber = lastRegisteredPhoneNumber
//
//        } else if let existingNumber = onboardingController.phoneNumber {
//            phoneNumber = existingNumber.userInput
//        }
//    }
//
//    private func fetchReregistrationNumberIfAvailable() -> String? {
//        // If re-registering, pre-populate the country (country code, calling code, country name)
//        // and phone number state.
//        guard tsAccountManager.isReregistering else {
//            return nil
//        }
//        guard let phoneNumberE164 = tsAccountManager.reregistrationPhoneNumber() else {
//            owsFailDebug("Could not resume re-registration; missing phone number.")
//            return nil
//        }
//        guard phoneNumberE164.count > 0 else {
//            owsFailDebug("Could not resume re-registration; invalid phoneNumberE164.")
//            return nil
//        }
//        guard let parsedPhoneNumber = PhoneNumber(fromE164: phoneNumberE164) else {
//            owsFailDebug("Could not resume re-registration; couldn't parse phoneNumberE164.")
//            return nil
//        }
//        guard let callingCodeNumeric = parsedPhoneNumber.getCountryCode() else {
//            owsFailDebug("Could not resume re-registration; missing callingCode.")
//            return nil
//        }
//        let callingCode = "\(COUNTRY_CODE_PREFIX)\(callingCodeNumeric)"
//        let countryCodes: [String] =
//        PhoneNumberUtil.sharedThreadLocal().countryCodes(fromCallingCode: callingCode)
//        guard let countryCode = countryCodes.first else {
//            owsFailDebug("Could not resume re-registration; unknown countryCode.")
//            return nil
//        }
//        guard let countryName = PhoneNumberUtil.countryName(fromCountryCode: countryCode) else {
//            owsFailDebug("Could not resume re-registration; unknown countryName.")
//            return nil
//        }
//        if !phoneNumberE164.hasPrefix(callingCode) {
//            owsFailDebug("Could not resume re-registration; non-matching calling code.")
//            return nil
//        }
//        let phoneNumberWithoutCallingCode = phoneNumberE164.substring(from: callingCode.count)
//
//        guard countryCode.count > 0 else {
//            owsFailDebug("Invalid country code.")
//            return nil
//        }
//        guard countryName.count > 0 else {
//            owsFailDebug("Invalid country name.")
//            return nil
//        }
//        guard callingCode.count > 0 else {
//            owsFailDebug("Invalid calling code.")
//            return nil
//        }
//
//        let countryState = RegistrationCountryState(countryName: countryName, callingCode: callingCode, countryCode: countryCode)
//        onboardingController.update(countryState: countryState)
//        return phoneNumberWithoutCallingCode
//    }
//
//    private func updateViewState(animated: Bool = true) {
//        AssertIsOnMainThread()
//
//        let showError = (phoneNumberError != nil)
//        let showSpinner: Bool
//        switch state {
//        case .interactive:
//            showSpinner = false
//        case .verifying_animationDeferred:
//            showSpinner = false
//            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
//                guard self.state == .verifying_animationDeferred else { return }
//                self.state = .verifying
//            }
//        case .verifying:
//            showSpinner = true
//        }
//
//        // Update non-animated properties immediately
//        countryNameLabel.text = countryName
//        callingCodeLabel.text = callingCode
//        updateValidationLabel()
//
//        phoneNumberTextField.isEnabled = !isReregistering
//        continueButton.setEnabled(state == .interactive)
//
//        if showSpinner, !progressSpinner.isAnimating {
//            progressSpinner.startAnimating()
//        } else if !showSpinner, progressSpinner.isAnimating {
//            progressSpinner.stopAnimatingImmediately()
//        }
//
//        let animationBlock = {
//            if showSpinner {
//                self.viewsToHideDuringVerification?.forEach { $0.alpha = 0 }
//                self.progressSpinner.alpha = 1
//
//            } else {
//                // Do this first, since there's overlap with the views below
//                self.viewsToHideDuringVerification?.forEach { $0.alpha = 1 }
//
//                self.progressSpinner.alpha = 0
//                self.phoneStrokeNormal?.alpha = showError ? 0 : 1
//                self.phoneStrokeError?.alpha = showError ? 1 : 0
//                self.validationWarningLabel.alpha = showError ? 1 : 0
//                self.updateValidationWarningLabelCompressionResistance()
//
//                self.primaryView.layoutIfNeeded()
//            }
//        }
//
//        if animated {
//            UIView.animate(withDuration: 0.25, delay: 0, options: .beginFromCurrentState, animations: animationBlock)
//        } else {
//            animationBlock()
//        }
//    }
//
//    private func updateValidationLabel() {
//        switch phoneNumberError {
//        case .invalidNumber:
//            validationWarningLabel.text = NSLocalizedString(
//                "ONBOARDING_PHONE_NUMBER_VALIDATION_WARNING",
//                comment: "Label indicating that the phone number is invalid in the 'onboarding phone number' view.")
//
//        case let .rateLimit(expiration: expirationDate) where expirationDate > Date():
//            let rateLimitFormat = NSLocalizedString(
//                "ONBOARDING_PHONE_NUMBER_RATE_LIMIT_WARNING_FORMAT",
//                comment: "Label indicating that registration has been ratelimited. Embeds {{remaining time string}}.")
//
//            let timeRemaining = expirationDate.timeIntervalSinceNow
//            let durationString = retryAfterFormatter.string(from: Date(timeIntervalSinceReferenceDate: timeRemaining))
//            validationWarningLabel.text = String(format: rateLimitFormat, durationString)
//
//            // Repeatedly update the validation warning label. Eventually the where condition above
//            // (expirationDate > Date()) will no longer hold and the error will be cleared
//            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
//                self?.updateValidationLabel()
//            }
//
//        case let .rateLimit(expiration: expirationDate) where expirationDate <= Date():
//            // Rate limit expiration is in the past, clear the error
//            phoneNumberError = nil
//        default:
//            // Both of our text blobs are about the same size. Ideally we don't want to move views when the error appears
//            // So we pre-populate with filler text to try and maintain an approximately consistent intrinsic content size
//            // If there's no error, the view will be hidden and compression resistance reduced.
//            validationWarningLabel.text = NSLocalizedString(
//                "ONBOARDING_PHONE_NUMBER_VALIDATION_WARNING",
//                comment: "Label indicating that the phone number is invalid in the 'onboarding phone number' view.")
//        }
//    }
//
//    private func updateValidationWarningLabelCompressionResistance() {
//        // validationWarningLabel's compression resistance will toggle between high priority and low priority
//        // as it becomes visible. Ideally, we want to make space for it to avoid layout adjustments when
//        // showing the error. But when space constrained, it's the first thing we'll give up.
//
//        let desiredResistance: UILayoutPriority = phoneNumberError != nil ? .required - 1 : .defaultLow - 1
//        self.validationWarningLabel.setContentCompressionResistancePriority(desiredResistance, for: .vertical)
//    }
//
//    // MARK: - Events
//
//    @objc func countryRowTapped(sender: UIGestureRecognizer) {
//        guard sender.state == .recognized else {
//            return
//        }
//        showCountryPicker()
//    }
//
//    @objc func countryCodeTapped(sender: UIGestureRecognizer) {
//        guard sender.state == .recognized else {
//            return
//        }
//        showCountryPicker()
//    }
//
//    @objc func continuePressed() {
//        Logger.info("")
//
//        parseAndTryToRegister()
//    }
//
//    // MARK: - Register
//
//    private func parseAndTryToRegister() {
//        guard let phoneNumberText = phoneNumber?.ows_stripped(),
//              phoneNumberText.count > 0 else {
//
//                  phoneNumberError = .invalidNumber
//                  OWSActionSheets.showActionSheet(
//                    title: NSLocalizedString(
//                        "REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_TITLE",
//                        comment: "Title of alert indicating that users needs to enter a phone number to register."),
//                    message: NSLocalizedString(
//                        "REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_MESSAGE",
//                        comment: "Message of alert indicating that users needs to enter a phone number to register."))
//                  return
//              }
//
//        let phoneNumber = "\(callingCode)\(phoneNumberText)"
//        guard let localNumber = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: phoneNumber),
//              localNumber.toE164().count > 0,
//              PhoneNumberValidator().isValidForRegistration(phoneNumber: localNumber) else {
//
//                  phoneNumberError = .invalidNumber
//                  OWSActionSheets.showActionSheet(
//                    title: NSLocalizedString(
//                        "REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_TITLE",
//                        comment: "Title of alert indicating that users needs to enter a valid phone number to register."),
//                    message: NSLocalizedString(
//                        "REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_MESSAGE",
//                        comment: "Message of alert indicating that users needs to enter a valid phone number to register."))
//                  return
//              }
//
//        if Self.tsAccountManager.isReregistering {
//            self.requestVerification(with: RegistrationPhoneNumber(e164: localNumber.toE164(), userInput: phoneNumberText))
//            return
//        }
//
//        let formattedNumber = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: localNumber.toE164())
//        let progressViewFormat = NSLocalizedString(
//            "REGISTRATION_VIEW_PHONE_NUMBER_SPINNER_LABEL_FORMAT",
//            comment: "Label for the progress spinner shown during phone number registration. Embeds {{phone number}}.")
//        progressSpinner.loadingText = String(format: progressViewFormat, formattedNumber)
//
//        // Preemptively resign so we don't reacquire first responder status between the alert
//        // dismissal and the progress view animation
//        self.phoneNumberTextField.resignFirstResponder()
//        self.onboardingController.presentPhoneNumberConfirmationSheet(from: self, number: formattedNumber) { [weak self] shouldContinue in
//            guard let self = self else { return }
//
//            if shouldContinue {
//                self.requestVerification(with: RegistrationPhoneNumber(e164: localNumber.toE164(), userInput: phoneNumberText))
//            } else {
//                // User wants to edit, retake first responder
//                self.phoneNumberTextField.becomeFirstResponder()
//            }
//        }
//    }
//
//    private func requestVerification(with phoneNumber: RegistrationPhoneNumber) {
//        self.onboardingController.update(phoneNumber: phoneNumber)
//
//        self.verificationAnimation(shouldPlay: true)
//        self.onboardingController.requestVerification(fromViewController: self, isSMS: true) { [weak self] willDismiss, error in
//            guard let self = self else { return }
//            self.verificationAnimation(shouldPlay: false)
//
//            // If the onboarding controller is not transitioning away from us, retake first responder
//            guard !willDismiss else { return }
//            self.phoneNumberTextField.becomeFirstResponder()
//
//            if let error = error, error.httpStatusCode == 413 {
//                // If we're not handed a retry-after date directly from the server, either
//                // use the existing date we already have or construct a new date 5 min from now
//                let retryAfterDate = error.httpRetryAfterDate ?? {
//                    if case let .rateLimit(existingRetryAfter) = self.phoneNumberError {
//                        return existingRetryAfter
//                    } else {
//                        return Date(timeIntervalSinceNow: 300)
//                    }
//                }()
//                self.phoneNumberError = .rateLimit(expiration: retryAfterDate)
//
//                // TODO: Once notification work is complete, uncomment this.
//                // self.notificationPresenter.notifyUserOfIncompleteRegistration(on: retryAfterDate)
//            }
//        }
//    }
//
//    private func verificationAnimation(shouldPlay: Bool) {
//        if shouldPlay {
//            if state == .interactive {
//                state = .verifying_animationDeferred
//            }
//        } else {
//            state = .interactive
//        }
//    }
// }

// MARK: -

extension ChangePhoneNumberInputViewController: ChangePhoneNumberValueViewsDelegate {
    fileprivate func valueDidChange(valueViews: ChangePhoneNumberValueViews) {
        AssertIsOnMainThread()

        updateNavigationBar()
    }

    fileprivate func valueDidPressEnter(valueViews: ChangePhoneNumberValueViews) {
        // TODO:
        //        parseAndTryToRegister()
    }

    fileprivate func valueDidUpdateCountryState(valueViews: ChangePhoneNumberValueViews) {
        // TODO:
        // updateViewState(animated: false)
        updateTableContents()
    }
}

// MARK: -

private protocol ChangePhoneNumberValueViewsDelegate: AnyObject {
    func valueDidChange(valueViews: ChangePhoneNumberValueViews)
    func valueDidPressEnter(valueViews: ChangePhoneNumberValueViews)
    func valueDidUpdateCountryState(valueViews: ChangePhoneNumberValueViews)
}

// MARK: -

private class ChangePhoneNumberValueViews: NSObject {

    weak var delegate: ChangePhoneNumberValueViewsDelegate?

    enum Value {
        case oldValue
        case newValue
    }
    let value: Value

    private let changePhoneNumberController: ChangePhoneNumberController

    public init(_ value: Value, changePhoneNumberController: ChangePhoneNumberController) {
        self.value = value
        self.changePhoneNumberController = changePhoneNumberController

        super.init()

        phoneNumberTextField.accessibilityIdentifier = self.accessibilityIdentifier_PhoneNumberTextfield
        phoneNumberTextField.delegate = self
        phoneNumberTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        phoneNumberTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingDidBegin)
        phoneNumberTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingDidEnd)

        phoneNumberString = phoneNumber?.withoutCountryCallingCode
    }

    var countryState: RegistrationCountryState {
        get {
            switch value {
            case .oldValue:
                return changePhoneNumberController.oldCountryState
            case .newValue:
                return changePhoneNumberController.newCountryState
            }
        }
        set {
            switch value {
            case .oldValue:
                changePhoneNumberController.oldCountryState = newValue
            case .newValue:
                changePhoneNumberController.newCountryState = newValue
            }
        }
    }

    var phoneNumber: RegistrationPhoneNumber? {
        get {
            switch value {
            case .oldValue:
                return changePhoneNumberController.oldPhoneNumber
            case .newValue:
                return changePhoneNumberController.newPhoneNumber
            }
        }
        set {
            switch value {
            case .oldValue:
                changePhoneNumberController.oldPhoneNumber = newValue
            case .newValue:
                changePhoneNumberController.newPhoneNumber = newValue
            }
        }
    }

    var countryName: String { countryState.countryName }
    var callingCode: String { countryState.callingCode }
    var countryCode: String { countryState.countryCode }

    // TODO:
    private enum InlineError {
        case invalidNumber
        case rateLimit(expiration: Date)
    }

    private var phoneNumberError: InlineError?
//    {
        // TODO:
//        didSet { view.setNeedsLayout() }
//    }

    var phoneNumberString: String? {
        get { phoneNumberTextField.text }
        set {
            phoneNumberTextField.text = newValue
            applyPhoneNumberFormatting()
        }
    }

    let phoneNumberTextField: UITextField = {
        let field = UITextField()
        field.font = UIFont.ows_dynamicTypeBodyClamped
        field.textColor = Theme.primaryTextColor
        field.textAlignment = (CurrentAppContext().isRTL
                               ? .left
                               : .right)
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

        return field
    }()

    private func applyPhoneNumberFormatting() {
        AssertIsOnMainThread()
        ViewControllerUtils.reformatPhoneNumber(phoneNumberTextField, callingCode: callingCode)
    }

    var sectionHeaderTitle: String {
        switch value {
        case .oldValue:
            return NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_OLD_PHONE_NUMBER_SECTION_TITLE",
                                     comment: "Title for the 'old phone number' section in the 'change phone number' settings.")
        case .newValue:
            return NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_NEW_PHONE_NUMBER_SECTION_TITLE",
                                     comment: "Title for the 'new phone number' section in the 'change phone number' settings.")
        }
    }

    var accessibilityIdentifierPrefix: String {
        switch value {
        case .oldValue:
            return "old"
        case .newValue:
            return "new"
        }
    }

    var accessibilityIdentifier_PhoneNumberTextfield: String {
        accessibilityIdentifierPrefix + "_phone_number_textfield"
    }

    var accessibilityIdentifier_PhoneNumber: String {
        accessibilityIdentifierPrefix + "_phone_number"
    }

    var accessibilityIdentifier_CountryCode: String {
        accessibilityIdentifierPrefix + "_country_code"
    }

    enum ParsedValue {
        case noNumber
        case invalidNumber
//        case rateLimit(expiration: Date)
        case validNumber(phoneNumber: PhoneNumber)
    }

    func tryToParse() -> ParsedValue {
        guard let phoneNumberWithoutCallingCode = phoneNumberString?.strippedOrNil else {
            self.phoneNumber = nil
            return .noNumber
        }

        let phoneNumberWithCallingCode = "\(callingCode)\(phoneNumberWithoutCallingCode)"
        guard let phoneNumber = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: phoneNumberWithCallingCode),
              let e164 = phoneNumber.toE164().strippedOrNil,
              PhoneNumberValidator().isValidForRegistration(phoneNumber: phoneNumber) else {
                  self.phoneNumber = nil
                  return .invalidNumber
              }

        self.phoneNumber = RegistrationPhoneNumber(e164: e164, userInput: phoneNumberWithoutCallingCode)
        return .validNumber(phoneNumber: phoneNumber)
    }
}

// MARK: -

extension ChangePhoneNumberValueViews: UITextFieldDelegate {
    public func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String) -> Bool {

            if case .invalidNumber = phoneNumberError {
                phoneNumberError = nil
            }

            // If ViewControllerUtils applied the edit on our behalf, inform UIKit
            // so the edit isn't applied twice.
            let result = ViewControllerUtils.phoneNumber(
                textField,
                shouldChangeCharactersIn: range,
                replacementString: string,
                callingCode: callingCode)

            textFieldDidChange(textField)

            return result
        }

    @objc
    private func textFieldDidChange(_ textField: UITextField) {
        applyPhoneNumberFormatting()
        delegate?.valueDidChange(valueViews: self)
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        delegate?.valueDidPressEnter(valueViews: self)
        return false
    }
}

// MARK: -

extension ChangePhoneNumberValueViews: CountryCodeViewControllerDelegate {
    public func countryCodeViewController(_ vc: CountryCodeViewController,
                                          didSelectCountry countryState: RegistrationCountryState) {
        self.countryState = countryState
        delegate?.valueDidUpdateCountryState(valueViews: self)
    }
}

// MARK: -

extension RegistrationPhoneNumber {

    var withoutCountryCallingCode: String? {
        guard let countryState = RegistrationCountryState.countryState(forE164: e164) else {
            owsFailDebug("Missing countryState.")
            return nil
        }
        let prefix = countryState.callingCode
        guard e164.hasPrefix(prefix) else {
            owsFailDebug("Unexpected callingCode: \(prefix) for e164: \(e164).")
            return nil
        }
        guard let result = String(e164.dropFirst(prefix.count)).strippedOrNil else {
            owsFailDebug("Could not remove callingCode: \(prefix) from e164: \(e164).")
            return nil
        }
        return result
    }
}
