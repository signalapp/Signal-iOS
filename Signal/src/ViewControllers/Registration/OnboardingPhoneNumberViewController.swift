//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

@objc
public class OnboardingPhoneNumberViewController: OnboardingBaseViewController {

    private let countryNameLabel = UILabel()
    private let callingCodeLabel = UILabel()
    private let phoneNumberTextField = UITextField()
    private var nextButton: OWSFlatButton?
    private var phoneStrokeNormal: UIView?
    private var phoneStrokeError: UIView?
    private let validationWarningLabel = UILabel()
    private var isPhoneNumberInvalid = false

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        populateDefaults()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.titleLabel(text: NSLocalizedString("ONBOARDING_PHONE_NUMBER_TITLE", comment: "Title of the 'onboarding phone number' view."))
        titleLabel.accessibilityIdentifier = "onboarding.phoneNumber." + "titleLabel"

        // Country

        let rowHeight: CGFloat = 40

        countryNameLabel.textColor = Theme.primaryTextColor
        countryNameLabel.font = UIFont.ows_dynamicTypeBodyClamped
        countryNameLabel.setContentHuggingHorizontalLow()
        countryNameLabel.setCompressionResistanceHorizontalLow()
        countryNameLabel.accessibilityIdentifier = "onboarding.phoneNumber." + "countryNameLabel"

        let countryIcon = UIImage(named: (CurrentAppContext().isRTL
            ? "small_chevron_left"
            : "small_chevron_right"))
        let countryImageView = UIImageView(image: countryIcon?.withRenderingMode(.alwaysTemplate))
        countryImageView.tintColor = Theme.placeholderColor
        countryImageView.setContentHuggingHigh()
        countryImageView.setCompressionResistanceHigh()
        countryImageView.accessibilityIdentifier = "onboarding.phoneNumber." + "countryImageView"

        let countryRow = UIStackView(arrangedSubviews: [
            countryNameLabel,
            countryImageView
            ])
        countryRow.axis = .horizontal
        countryRow.alignment = .center
        countryRow.spacing = 10
        countryRow.isUserInteractionEnabled = true
        countryRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(countryRowTapped)))
        countryRow.autoSetDimension(.height, toSize: rowHeight)
        _ = countryRow.addBottomStroke()
        countryRow.accessibilityIdentifier = "onboarding.phoneNumber." + "countryRow"

        callingCodeLabel.textColor = Theme.primaryTextColor
        callingCodeLabel.font = UIFont.ows_dynamicTypeBodyClamped
        callingCodeLabel.setContentHuggingHorizontalHigh()
        callingCodeLabel.setCompressionResistanceHorizontalHigh()
        callingCodeLabel.isUserInteractionEnabled = true
        callingCodeLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(countryCodeTapped)))
        _ = callingCodeLabel.addBottomStroke()
        callingCodeLabel.autoSetDimension(.width, toSize: rowHeight, relation: .greaterThanOrEqual)
        callingCodeLabel.accessibilityIdentifier = "onboarding.phoneNumber." + "callingCodeLabel"

        phoneNumberTextField.textAlignment = .left
        phoneNumberTextField.delegate = self
        phoneNumberTextField.keyboardType = .numberPad
        phoneNumberTextField.textColor = Theme.primaryTextColor
        phoneNumberTextField.font = UIFont.ows_dynamicTypeBodyClamped
        phoneNumberTextField.setContentHuggingHorizontalLow()
        phoneNumberTextField.setCompressionResistanceHorizontalLow()
        phoneNumberTextField.accessibilityIdentifier = "onboarding.phoneNumber." + "phoneNumberTextField"

        phoneStrokeNormal = phoneNumberTextField.addBottomStroke()
        phoneStrokeError = phoneNumberTextField.addBottomStroke(color: .ows_accentRed, strokeWidth: 2)

        let phoneNumberRow = UIStackView(arrangedSubviews: [
            callingCodeLabel,
            phoneNumberTextField
            ])
        phoneNumberRow.axis = .horizontal
        phoneNumberRow.alignment = .fill
        phoneNumberRow.spacing = 10
        phoneNumberRow.autoSetDimension(.height, toSize: rowHeight)
        callingCodeLabel.autoMatch(.height, to: .height, of: phoneNumberTextField)

        validationWarningLabel.text = NSLocalizedString("ONBOARDING_PHONE_NUMBER_VALIDATION_WARNING",
                                                        comment: "Label indicating that the phone number is invalid in the 'onboarding phone number' view.")
        validationWarningLabel.textColor = .ows_accentRed
        validationWarningLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        validationWarningLabel.autoSetDimension(.height, toSize: validationWarningLabel.font.lineHeight)
        validationWarningLabel.accessibilityIdentifier = "onboarding.phoneNumber." + "validationWarningLabel"

        let validationWarningRow = UIView()
        validationWarningRow.addSubview(validationWarningLabel)
        validationWarningLabel.autoPinHeightToSuperview()
        validationWarningLabel.autoPinEdge(toSuperviewEdge: .trailing)

        let nextButton = self.primaryButton(title: CommonStrings.nextButton,
                                           selector: #selector(nextPressed))
        nextButton.accessibilityIdentifier = "onboarding.phoneNumber." + "nextButton"
        self.nextButton = nextButton
        let primaryButtonView = OnboardingBaseViewController.horizontallyWrap(primaryButton: nextButton)

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let compressableBottomMargin = UIView.vStretchingSpacer(minHeight: 16, maxHeight: primaryLayoutMargins.bottom)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            topSpacer,
            countryRow,
            UIView.spacer(withHeight: 8),
            phoneNumberRow,
            UIView.spacer(withHeight: 8),
            validationWarningRow,
            bottomSpacer,
            primaryButtonView,
            compressableBottomMargin
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        primaryView.addSubview(stackView)

        // Because of the keyboard, vertical spacing can get pretty cramped,
        // so we have custom spacer logic.
        stackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)
        autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)

        // Ensure whitespace is balanced, so inputs are vertically centered.
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        validationWarningLabel.autoPinEdge(.leading, to: .leading, of: phoneNumberTextField)
    }

    // MARK: - View Lifecycle

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        isPhoneNumberInvalid = false

        updateViewState()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        phoneNumberTextField.becomeFirstResponder()

        if tsAccountManager.isReregistering {
            // If re-registering, pre-populate the country (country code, calling code, country name)
            // and phone number state.
            guard let phoneNumberE164 = tsAccountManager.reregistrationPhoneNumber() else {
                owsFailDebug("Could not resume re-registration; missing phone number.")
                return
            }
            tryToReregister(phoneNumberE164: phoneNumberE164)
        }
    }

    private func tryToReregister(phoneNumberE164: String) {
        guard phoneNumberE164.count > 0 else {
            owsFailDebug("Could not resume re-registration; invalid phoneNumberE164.")
            return
        }
        guard let parsedPhoneNumber = PhoneNumber(fromE164: phoneNumberE164) else {
            owsFailDebug("Could not resume re-registration; couldn't parse phoneNumberE164.")
            return
        }
        guard let callingCodeNumeric = parsedPhoneNumber.getCountryCode() else {
            owsFailDebug("Could not resume re-registration; missing callingCode.")
            return
        }
        let callingCode = "\(COUNTRY_CODE_PREFIX)\(callingCodeNumeric)"
        let countryCodes: [String] =
            PhoneNumberUtil.sharedThreadLocal().countryCodes(fromCallingCode: callingCode)
        guard let countryCode = countryCodes.first else {
            owsFailDebug("Could not resume re-registration; unknown countryCode.")
            return
        }
        guard let countryName = PhoneNumberUtil.countryName(fromCountryCode: countryCode) else {
            owsFailDebug("Could not resume re-registration; unknown countryName.")
            return
        }
        if !phoneNumberE164.hasPrefix(callingCode) {
            owsFailDebug("Could not resume re-registration; non-matching calling code.")
            return
        }
        let phoneNumberWithoutCallingCode = phoneNumberE164.substring(from: callingCode.count)

        guard countryCode.count > 0 else {
            owsFailDebug("Invalid country code.")
            return
        }
        guard countryName.count > 0 else {
            owsFailDebug("Invalid country name.")
            return
        }
        guard callingCode.count > 0 else {
            owsFailDebug("Invalid calling code.")
            return
        }

        let countryState = OnboardingCountryState(countryName: countryName, callingCode: callingCode, countryCode: countryCode)
        onboardingController.update(countryState: countryState)

        phoneNumberTextField.text = phoneNumberWithoutCallingCode

        // Don't let user edit their phone number while re-registering.
        phoneNumberTextField.isEnabled = false

        updateViewState()

        // Trigger the formatting logic with a no-op edit.
        _ = textField(phoneNumberTextField, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "")
    }

    // MARK: -

    private var countryName: String {
        get {
            return onboardingController.countryState.countryName
        }
    }
    private var callingCode: String {
        get {
            AssertIsOnMainThread()

            return onboardingController.countryState.callingCode
        }
    }
    private var countryCode: String {
        get {
            AssertIsOnMainThread()

            return onboardingController.countryState.countryCode
        }
    }

    private func populateDefaults() {
        if let lastRegisteredPhoneNumber = OnboardingController.lastRegisteredPhoneNumber(),
            lastRegisteredPhoneNumber.count > 0 {
            phoneNumberTextField.text = lastRegisteredPhoneNumber
        } else if let phoneNumber = onboardingController.phoneNumber {
            phoneNumberTextField.text = phoneNumber.userInput
        }

        updateViewState()

        // Trigger the formatting logic with a no-op edit.
        _ = textField(phoneNumberTextField, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "")
    }

    private func updateViewState() {
        AssertIsOnMainThread()

        countryNameLabel.text = countryName
        callingCodeLabel.text = callingCode

        self.phoneNumberTextField.placeholder = ViewControllerUtils.examplePhoneNumber(forCountryCode: countryCode, callingCode: callingCode)

        updateValidationWarnings()
    }

    private func updateValidationWarnings() {
        AssertIsOnMainThread()

        phoneStrokeNormal?.isHidden = isPhoneNumberInvalid
        phoneStrokeError?.isHidden = !isPhoneNumberInvalid
        validationWarningLabel.isHidden = !isPhoneNumberInvalid
    }

     // MARK: - Events

    @objc func countryRowTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        showCountryPicker()
    }

    @objc func countryCodeTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        showCountryPicker()
    }

    @objc func nextPressed() {
        Logger.info("")

        parseAndTryToRegister()
    }

    // MARK: - Country Picker

    private func showCountryPicker() {
        guard !tsAccountManager.isReregistering else {
            return
        }

        let countryCodeController = CountryCodeViewController()
        countryCodeController.countryCodeDelegate = self
        countryCodeController.interfaceOrientationMask = UIDevice.current.isIPad ? .all : .portrait
        let navigationController = OWSNavigationController(rootViewController: countryCodeController)
        self.present(navigationController, animated: true, completion: nil)
    }

    // MARK: - Register

    private func parseAndTryToRegister() {
        guard let phoneNumberText = phoneNumberTextField.text?.ows_stripped(),
            phoneNumberText.count > 0 else {

                isPhoneNumberInvalid = true
                updateValidationWarnings()

                OWSActionSheets.showActionSheet(title:
                    NSLocalizedString("REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_TITLE",
                                      comment: "Title of alert indicating that users needs to enter a phone number to register."),
                    message:
                    NSLocalizedString("REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_MESSAGE",
                                      comment: "Message of alert indicating that users needs to enter a phone number to register."))
                return
        }

        let phoneNumber = "\(callingCode)\(phoneNumberText)"
        guard let localNumber = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: phoneNumber),
            localNumber.toE164().count > 0,
            PhoneNumberValidator().isValidForRegistration(phoneNumber: localNumber) else {

                isPhoneNumberInvalid = true
                updateValidationWarnings()

                OWSActionSheets.showActionSheet(title:
                    NSLocalizedString("REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_TITLE",
                                      comment: "Title of alert indicating that users needs to enter a valid phone number to register."),
                    message:
                    NSLocalizedString("REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_MESSAGE",
                                      comment: "Message of alert indicating that users needs to enter a valid phone number to register."))
                return
        }
        let e164PhoneNumber = localNumber.toE164()

        onboardingController.update(phoneNumber: OnboardingPhoneNumber(e164: e164PhoneNumber, userInput: phoneNumberText))
        onboardingController.requestVerification(fromViewController: self, isSMS: true)
    }
}

// MARK: -

extension OnboardingPhoneNumberViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        ViewControllerUtils.phoneNumber(textField, shouldChangeCharactersIn: range, replacementString: string, callingCode: callingCode)

        isPhoneNumberInvalid = false
        updateValidationWarnings()

        // Inform our caller that we took care of performing the change.
        return false
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        parseAndTryToRegister()
        return false
    }
}

// MARK: -

extension OnboardingPhoneNumberViewController: CountryCodeViewControllerDelegate {
    public func countryCodeViewController(_ vc: CountryCodeViewController, didSelectCountryCode countryCode: String, countryName: String, callingCode: String) {
        guard countryCode.count > 0 else {
            owsFailDebug("Invalid country code.")
            return
        }
        guard countryName.count > 0 else {
            owsFailDebug("Invalid country name.")
            return
        }
        guard callingCode.count > 0 else {
            owsFailDebug("Invalid calling code.")
            return
        }

        let countryState = OnboardingCountryState(countryName: countryName, callingCode: callingCode, countryCode: countryCode)

        onboardingController.update(countryState: countryState)

        updateViewState()

            // Trigger the formatting logic with a no-op edit.
        _ = textField(phoneNumberTextField, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "")
    }
}
