//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

@objc
public class OnboardingPhoneNumberViewController: OnboardingBaseViewController {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    // MARK: -

    private let countryNameLabel = UILabel()
    private let callingCodeLabel = UILabel()
    private let phoneNumberTextField = UITextField()
    private var nextButton: OWSFlatButton?

    override public func loadView() {
        super.loadView()

        // TODO: Is this still necessary?
        if let navigationController = self.navigationController as? OWSNavigationController {
            SignalApp.shared().signUpFlowNavigationController = navigationController
        } else {
            owsFailDebug("Missing or invalid navigationController")
        }

        populateDefaults()

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero

        // TODO:
//        navigationItem.title = NSLocalizedString("SETTINGS_BACKUP", comment: "Label for the backup view in app settings.")

        let titleLabel = self.titleLabel(text: NSLocalizedString("ONBOARDING_PHONE_NUMBER_TITLE", comment: "Title of the 'onboarding phone number' view."))

        // Country

        let rowHeight: CGFloat = 40

        countryNameLabel.textColor = Theme.primaryColor
        countryNameLabel.font = UIFont.ows_dynamicTypeBody
        countryNameLabel.setContentHuggingHorizontalLow()
        countryNameLabel.setCompressionResistanceHorizontalLow()

        let countryIcon = UIImage(named: (CurrentAppContext().isRTL
            ? "small_chevron_left"
            : "small_chevron_right"))
        let countryImageView = UIImageView(image: countryIcon?.withRenderingMode(.alwaysTemplate))
        countryImageView.tintColor = Theme.placeholderColor
        countryImageView.setContentHuggingHigh()
        countryImageView.setCompressionResistanceHigh()

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
        addBottomStroke(countryRow)

        callingCodeLabel.textColor = Theme.primaryColor
        callingCodeLabel.font = UIFont.ows_dynamicTypeBody
        callingCodeLabel.setContentHuggingHorizontalHigh()
        callingCodeLabel.setCompressionResistanceHorizontalHigh()
        callingCodeLabel.isUserInteractionEnabled = true
        callingCodeLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(countryCodeTapped)))
        addBottomStroke(callingCodeLabel)
        callingCodeLabel.autoSetDimension(.width, toSize: rowHeight, relation: .greaterThanOrEqual)

        phoneNumberTextField.textAlignment = .left
        phoneNumberTextField.delegate = self
        phoneNumberTextField.keyboardType = .numberPad
        phoneNumberTextField.textColor = Theme.primaryColor
        phoneNumberTextField.font = UIFont.ows_dynamicTypeBody
        phoneNumberTextField.setContentHuggingHorizontalLow()
        phoneNumberTextField.setCompressionResistanceHorizontalLow()

        addBottomStroke(phoneNumberTextField)

        let phoneNumberRow = UIStackView(arrangedSubviews: [
            callingCodeLabel,
            phoneNumberTextField
            ])
        phoneNumberRow.axis = .horizontal
        phoneNumberRow.alignment = .fill
        phoneNumberRow.spacing = 10
        phoneNumberRow.autoSetDimension(.height, toSize: rowHeight)
        callingCodeLabel.autoMatch(.height, to: .height, of: phoneNumberTextField)

        // TODO: Finalize copy.

        let nextButton = self.button(title: NSLocalizedString("BUTTON_NEXT",
                                                                comment: "Label for the 'next' button."),
                                           selector: #selector(nextPressed))
        self.nextButton = nextButton
        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            topSpacer,
            countryRow,
            UIView.spacer(withHeight: 8),
            phoneNumberRow,
            bottomSpacer,
            nextButton
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)

        // Ensure whitespace is balanced, so inputs are vertically centered.
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
    }

    private func addBottomStroke(_ view: UIView) {
        let strokeView = UIView()
        strokeView.backgroundColor = Theme.middleGrayColor
        view.addSubview(strokeView)
        strokeView.autoSetDimension(.height, toSize: CGHairlineWidth())
        strokeView.autoPinWidthToSuperview()
        strokeView.autoPinEdge(toSuperviewEdge: .bottom)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.navigationController?.isNavigationBarHidden = false

        phoneNumberTextField.becomeFirstResponder()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.navigationController?.isNavigationBarHidden = false

        phoneNumberTextField.becomeFirstResponder()

        if tsAccountManager.isReregistering() {
            // If re-registering, pre-populate the country (country code, calling code, country name)
            // and phone number state.
            guard let phoneNumberE164 = tsAccountManager.reregisterationPhoneNumber() else {
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
        guard let callingCode = parsedPhoneNumber.getCountryCode() else {
            owsFailDebug("Could not resume re-registration; missing callingCode.")
            return
        }
        let callingCodeText = "\(COUNTRY_CODE_PREFIX)\(callingCode)"
        let countryCodes: [String] =
            PhoneNumberUtil.sharedThreadLocal().countryCodes(fromCallingCode: callingCodeText)
        guard let countryCode = countryCodes.first else {
            owsFailDebug("Could not resume re-registration; unknown countryCode.")
            return
        }
        guard let countryName = PhoneNumberUtil.countryName(fromCountryCode: countryCode) else {
            owsFailDebug("Could not resume re-registration; unknown countryName.")
            return
        }
        if !phoneNumberE164.hasPrefix(callingCodeText) {
            owsFailDebug("Could not resume re-registration; non-matching calling code.")
            return
        }
        let phoneNumberWithoutCallingCode = phoneNumberE164.substring(from: callingCodeText.count)

        update(withCountryName: countryName, callingCode: callingCodeText, countryCode: countryCode)

        phoneNumberTextField.text = phoneNumberWithoutCallingCode
        // Don't let user edit their phone number while re-registering.
        phoneNumberTextField.isEnabled = false
    }

    // MARK: -

    private var countryName = ""
    private var callingCode = ""
    private var countryCode = ""

    private func populateDefaults() {

        var countryCode: String = PhoneNumber.defaultCountryCode()
        if let lastRegisteredCountryCode = self.lastRegisteredCountryCode(),
            lastRegisteredCountryCode.count > 0 {
            countryCode = lastRegisteredCountryCode
        }

        let callingCodeNumber: NSNumber = PhoneNumberUtil.sharedThreadLocal().nbPhoneNumberUtil.getCountryCode(forRegion: countryCode)
        let callingCode = "\(COUNTRY_CODE_PREFIX)\(callingCodeNumber)"

        if let lastRegisteredPhoneNumber = self.lastRegisteredPhoneNumber(),
            lastRegisteredPhoneNumber.count > 0,
            lastRegisteredPhoneNumber.hasPrefix(callingCode) {
            phoneNumberTextField.text = lastRegisteredPhoneNumber.substring(from: callingCode.count)
        }

        var countryName = NSLocalizedString("UNKNOWN_COUNTRY_NAME", comment: "Label for unknown countries.")
        if let countryNameDerived = PhoneNumberUtil.countryName(fromCountryCode: countryCode) {
            countryName = countryNameDerived
        }

        update(withCountryName: countryName, callingCode: callingCode, countryCode: countryCode)
    }

    private func update(withCountryName countryName: String, callingCode: String, countryCode: String) {
        AssertIsOnMainThread()

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

        self.countryName = countryName
        self.callingCode = callingCode
        self.countryCode = countryCode

        countryNameLabel.text = countryName
        callingCodeLabel.text = callingCode

        self.phoneNumberTextField.placeholder = ViewControllerUtils.examplePhoneNumber(forCountryCode: countryCode, callingCode: callingCode)
    }

    // MARK: - Debug

    private let kKeychainService_LastRegistered = "kKeychainService_LastRegistered"
    private let kKeychainKey_LastRegisteredCountryCode = "kKeychainKey_LastRegisteredCountryCode"
    private let kKeychainKey_LastRegisteredPhoneNumber = "kKeychainKey_LastRegisteredPhoneNumber"

    private func debugValue(forKey key: String) -> String? {
        guard CurrentAppContext().isDebugBuild() else {
            return nil
        }

        do {
            let value = try CurrentAppContext().keychainStorage().string(forService: kKeychainService_LastRegistered, key: key)
            return value
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private func setDebugValue(_ value: String, forKey key: String) {
        guard CurrentAppContext().isDebugBuild() else {
            return
        }

        do {
            try CurrentAppContext().keychainStorage().set(string: value, service: kKeychainService_LastRegistered, key: key)
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    private func lastRegisteredCountryCode() -> String? {
        return debugValue(forKey: kKeychainKey_LastRegisteredCountryCode)
    }

    private func setLastRegisteredCountryCode(value: String) {
        setDebugValue(value, forKey: kKeychainKey_LastRegisteredCountryCode)
    }

    private func lastRegisteredPhoneNumber() -> String? {
        return debugValue(forKey: kKeychainKey_LastRegisteredPhoneNumber)
    }

    private func setLastRegisteredPhoneNumber(value: String) {
        setDebugValue(value, forKey: kKeychainKey_LastRegisteredPhoneNumber)
    }

     // MARK: - Events

    @objc func explanationLabelTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        // TODO:
    }

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

        onboardingController.onboardingPhoneNumberDidComplete(viewController: self)
    }

    // MARK: - Country Picker

    private func showCountryPicker() {
        guard !tsAccountManager.isReregistering() else {
            return
        }

        let countryCodeController = CountryCodeViewController()
        countryCodeController.countryCodeDelegate = self
        countryCodeController.interfaceOrientationMask = .portrait
        let navigationController = OWSNavigationController(rootViewController: countryCodeController)
        self.present(navigationController, animated: true, completion: nil)
    }

    // MARK: - Register

    private func didTapRegisterButton() {
        guard let phoneNumberText = phoneNumberTextField.text?.ows_stripped(),
            phoneNumberText.count > 0 else {
                OWSAlerts.showAlert(title:
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
                OWSAlerts.showAlert(title:
                    NSLocalizedString("REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_TITLE",
                                      comment: "Title of alert indicating that users needs to enter a valid phone number to register."),
                    message:
                    NSLocalizedString("REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_MESSAGE",
                                      comment: "Message of alert indicating that users needs to enter a valid phone number to register."))
                return
        }
        let parsedPhoneNumber = localNumber.toE164()

        if UIDevice.current.isIPad {
            let countryCode = self.countryCode
            OWSAlerts.showConfirmationAlert(title: NSLocalizedString("REGISTRATION_IPAD_CONFIRM_TITLE",
                                                                      comment: "alert title when registering an iPad"),
                                            message: NSLocalizedString("REGISTRATION_IPAD_CONFIRM_BODY",
                                                                        comment: "alert body when registering an iPad"),
                                            proceedTitle: NSLocalizedString("REGISTRATION_IPAD_CONFIRM_BUTTON",
                                                                             comment: "button text to proceed with registration when on an iPad"),
                                            proceedAction: { (_) in
                                                self.sendCode(parsedPhoneNumber: parsedPhoneNumber,
                                                              phoneNumberText: phoneNumberText,
                                                              countryCode: countryCode)
            })
        } else {
            sendCode(parsedPhoneNumber: parsedPhoneNumber,
                     phoneNumberText: phoneNumberText,
                     countryCode: countryCode)
        }
    }

    private func sendCode(parsedPhoneNumber: String,
                          phoneNumberText: String,
                          countryCode: String) {
        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: true) { (modal) in
                                                        self.setLastRegisteredCountryCode(value: countryCode)
                                                        self.setLastRegisteredPhoneNumber(value: phoneNumberText)

                                                        self.tsAccountManager.register(withPhoneNumber: parsedPhoneNumber,
                                                                                       success: {
                                                                                        DispatchQueue.main.async {
                                                                                            modal.dismiss(completion: {
                                                                                                self.registrationSucceeded()
                                                                                            })
                                                                                        }
                                                        }, failure: { (error) in
                                                            Logger.error("Error: \(error)")

                                                            DispatchQueue.main.async {
                                                                modal.dismiss(completion: {
                                                                    self.registrationFailed(error: error as NSError)
                                                                })
                                                            }
                                                        }, smsVerification: true)
        }
    }

    private func registrationSucceeded() {
        self.onboardingController.onboardingPhoneNumberDidComplete(viewController: self)
    }

    private func registrationFailed(error: NSError) {
        if error.code == 400 {
            OWSAlerts.showAlert(title: NSLocalizedString("REGISTRATION_ERROR", comment: ""),
                                message: NSLocalizedString("REGISTRATION_NON_VALID_NUMBER", comment: ""))

        } else {
            OWSAlerts.showAlert(title: error.localizedDescription,
                                message: error.localizedRecoverySuggestion)
        }

        phoneNumberTextField.becomeFirstResponder()
    }
}

// MARK: -

extension OnboardingPhoneNumberViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // TODO: Fix auto-format of phone numbers.
        ViewControllerUtils.phoneNumber(textField, shouldChangeCharactersIn: range, replacementString: string, countryCode: countryCode)

        // Inform our caller that we took care of performing the change.
        return false
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        didTapRegisterButton()
        textField.resignFirstResponder()
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

        update(withCountryName: countryName, callingCode: callingCode, countryCode: countryCode)

            // Trigger the formatting logic with a no-op edit.
        _ = textField(phoneNumberTextField, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "")
    }
}
