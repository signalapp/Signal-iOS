//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class OWS2FAReminderViewController: UIViewController, PinEntryViewDelegate {

    private var ows2FAManager: OWS2FAManager {
        return OWS2FAManager.shared()
    }

    var pinEntryView: PinEntryView!

    @objc
    public class func wrappedInNavController() -> OWSNavigationController {
        let navController = OWSNavigationController()
        navController.pushViewController(OWS2FAReminderViewController(), animated: false)

        return navController
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pinEntryView.makePinTextFieldFirstResponder()
    }

    override public func loadView() {
        assert(ows2FAManager.pinCode != nil)

        self.navigationItem.title = NSLocalizedString("REMINDER_2FA_NAV_TITLE", comment: "Navbar title for when user is periodically prompted to enter their registration lock PIN")

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(didPressCloseButton))

        let view = UIView()
        self.view = view
        view.backgroundColor = Theme.backgroundColor

        let pinEntryView = PinEntryView()
        self.pinEntryView = pinEntryView
        pinEntryView.delegate = self

        let instructionsTextHeader = NSLocalizedString("REMINDER_2FA_BODY_HEADER", comment: "Body header for when user is periodically prompted to enter their registration lock PIN")
        let instructionsTextBody = NSLocalizedString("REMINDER_2FA_BODY", comment: "Body text for when user is periodically prompted to enter their registration lock PIN")

        let attributes = [NSAttributedStringKey.font: pinEntryView.boldLabelFont]

        let attributedInstructionsText = NSAttributedString(string: instructionsTextHeader, attributes: attributes).rtlSafeAppend(" ").rtlSafeAppend(instructionsTextBody)

        pinEntryView.attributedInstructionsText = attributedInstructionsText

        view.addSubview(pinEntryView)

        pinEntryView.autoPinWidthToSuperview(withMargin: 20)
        pinEntryView.autoPin(toTopLayoutGuideOf: self, withInset: ScaleFromIPhone5(16))
        pinEntryView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
    }

    // MARK: PinEntryViewDelegate
    public func pinEntryView(_ entryView: PinEntryView, submittedPinCode pinCode: String) {
        Logger.info("")
        if checkResult(pinCode: pinCode) {
            didSubmitCorrectPin()
        } else {
            didSubmitWrongPin()
        }
    }

    //textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
    public func pinEntryView(_ entryView: PinEntryView, pinCodeDidChange pinCode: String) {
        // optimistically match, without having to press "done"
        if checkResult(pinCode: pinCode) {
            didSubmitCorrectPin()
        }
    }

    public func pinEntryViewForgotPinLinkTapped(_ entryView: PinEntryView) {
        Logger.info("")
        let alertBody = NSLocalizedString("REMINDER_2FA_FORGOT_PIN_ALERT_MESSAGE",
                                          comment: "Alert message explaining what happens if you forget your 'two-factor auth pin'")
        OWSAlerts.showAlert(title: nil, message: alertBody)
    }

    // MARK: Helpers

    @objc
    private func didPressCloseButton(sender: UIButton) {
        Logger.info("")
        // We'll ask again next time they launch
        self.dismiss(animated: true)
    }

    private func checkResult(pinCode: String) -> Bool {
        return pinCode == ows2FAManager.pinCode
    }

    private func didSubmitCorrectPin() {
        Logger.info("noWrongGuesses: \(noWrongGuesses)")

        self.dismiss(animated: true)

        OWS2FAManager.shared().updateRepetitionInterval(withWasSuccessful: noWrongGuesses)
    }

    var noWrongGuesses = true
    private func didSubmitWrongPin() {
        noWrongGuesses = false
        Logger.info("")
        let alertTitle = NSLocalizedString("REMINDER_2FA_WRONG_PIN_ALERT_TITLE",
                                          comment: "Alert title after wrong guess for 'two-factor auth pin' reminder activity")
        let alertBody = NSLocalizedString("REMINDER_2FA_WRONG_PIN_ALERT_BODY",
                                          comment: "Alert body after wrong guess for 'two-factor auth pin' reminder activity")
        OWSAlerts.showAlert(title: alertTitle, message: alertBody)
        self.pinEntryView.clearText()
    }
}
