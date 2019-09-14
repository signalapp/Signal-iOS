//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

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
        assert(ows2FAManager.is2FAEnabled())

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

        let attributes = [NSAttributedString.Key.font: pinEntryView.boldLabelFont]

        let attributedInstructionsText = NSAttributedString(string: instructionsTextHeader, attributes: attributes) + " " + instructionsTextBody

        pinEntryView.attributedInstructionsText = attributedInstructionsText

        view.addSubview(pinEntryView)

        pinEntryView.autoPinWidthToSuperview(withMargin: 20)
        pinEntryView.autoPin(toTopLayoutGuideOf: self, withInset: ScaleFromIPhone5(16))
        pinEntryView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
    }

    // MARK: PinEntryViewDelegate
    public func pinEntryView(_ entryView: PinEntryView, submittedPinCode pinCode: String) {
        Logger.info("")

        ows2FAManager.verifyPin(pinCode) { success in
            if success {
                self.didSubmitCorrectPin()
            } else {
                self.didSubmitWrongPin()
            }
        }
    }

    //textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
    public func pinEntryView(_ entryView: PinEntryView, pinCodeDidChange pinCode: String) {
        // optimistically match, without having to press "done"
        ows2FAManager.verifyPin(pinCode) { success in

            if success {
                self.didSubmitCorrectPin()

            // We have a legacy pin that may have been truncated to 16 characters.
            } else if self.ows2FAManager.needsLegacyPinMigration(), pinCode.count > kLegacyTruncated2FAv1PinLength {
                let truncatedPinCode = pinCode.substring(to: Int(kLegacyTruncated2FAv1PinLength))
                self.ows2FAManager.verifyPin(truncatedPinCode) { success in
                    if success {
                        self.didSubmitCorrectPin()
                    }
                }
            }
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

    private func didSubmitCorrectPin() {
        Logger.info("noWrongGuesses: \(noWrongGuesses)")

        // Migrate to 2FA v2 if they've proved they know their pin
        if let pinCode = ows2FAManager.pinCode, FeatureFlags.registrationLockV2, ows2FAManager.mode == .V1 {
            // enabling 2fa v2 automatically disables v1 on the server
            ows2FAManager.enable2FAPromise(with: pinCode)
                .ensure {
                    self.dismiss(animated: true)
                }.catch { error in
                    // We don't need to bubble this up to the user, since they
                    // don't know / care that something is changing in this moment.
                    // We can try and migrate them again during their next reminder.
                    owsFailDebug("Unexpected error \(error) while migrating to reg lock v2")
                }.retainUntilComplete()
        } else {
            self.dismiss(animated: true)
        }

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

extension OWS2FAManager {
    func enable2FAPromise(with pin: String) -> Promise<Void> {
        return Promise { resolver in
            requestEnable2FA(withPin: pin, success: {
                resolver.fulfill(())
            }, failure: { error in
                resolver.reject(error)
            })
        }
    }
}
