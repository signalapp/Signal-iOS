//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

@objc
public class OnboardingBaseViewController: OWSViewController {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    // MARK: -

    // Unlike a delegate, we can and should retain a strong reference to the OnboardingController.
    let onboardingController: OnboardingController

    @objc
    public init(onboardingController: OnboardingController) {
        self.onboardingController = onboardingController

        super.init(nibName: nil, bundle: nil)

        self.shouldUseTheme = false
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - Factory Methods

    func titleLabel(text: String) -> UILabel {
        let titleLabel = UILabel()
        titleLabel.text = text
        titleLabel.textColor = Theme.primaryColor
        titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_mediumWeight()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        return titleLabel
    }

    func explanationLabel(explanationText: String, linkText: String, selector: Selector) -> UILabel {
        let explanationText = NSAttributedString(string: explanationText)
            .rtlSafeAppend(NSAttributedString(string: " "))
            .rtlSafeAppend(linkText,
                           attributes: [
                            NSAttributedStringKey.foregroundColor: UIColor.ows_materialBlue
                ])
        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.secondaryColor
        explanationLabel.font = UIFont.ows_dynamicTypeCaption1
        explanationLabel.attributedText = explanationText
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.isUserInteractionEnabled = true
        explanationLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: selector))
        return explanationLabel
    }

    func button(title: String, selector: Selector) -> OWSFlatButton {
        // TODO: Make sure this all fits if dynamic font sizes are maxed out.
        let buttonHeight: CGFloat = 48
        let button = OWSFlatButton.button(title: title,
                                          font: OWSFlatButton.fontForHeight(buttonHeight),
                                          titleColor: .white,
                                          backgroundColor: .ows_materialBlue,
                                          target: self,
                                          selector: selector)
        button.autoSetDimension(.height, toSize: buttonHeight)
        return button
    }

    // MARK: - View Lifecycle

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // TODO: Is there a better way to do this?
        if let navigationController = self.navigationController as? OWSNavigationController {
            SignalApp.shared().signUpFlowNavigationController = navigationController
        } else {
            owsFailDebug("Missing or invalid navigationController")
        }
    }

    // MARK: - Registration

    func tryToRegister(smsVerification: Bool) {

        guard let phoneNumber = onboardingController.phoneNumber else {
            owsFailDebug("Missing phoneNumber.")
            return
        }

        // We eagerly update this state, regardless of whether or not the
        // registration request succeeds.
        OnboardingController.setLastRegisteredCountryCode(value: onboardingController.countryState.countryCode)
        OnboardingController.setLastRegisteredPhoneNumber(value: phoneNumber.userInput)

        let captchaToken = onboardingController.captchaToken

        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: true) { (modal) in

                                                        self.tsAccountManager.register(withPhoneNumber: phoneNumber.e164,
                                                                                       captchaToken: captchaToken,
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
                                                        }, smsVerification: smsVerification)
        }
    }

    private func registrationSucceeded() {
        self.onboardingController.onboardingRegistrationSucceeded(viewController: self)
    }

    private func registrationFailed(error: NSError) {
        if error.code == 402 {
            Logger.info("Captcha requested.")

            self.onboardingController.onboardingDidRequireCaptcha(viewController: self)
            return
        } else if error.code == 400 {
            OWSAlerts.showAlert(title: NSLocalizedString("REGISTRATION_ERROR", comment: ""),
                                message: NSLocalizedString("REGISTRATION_NON_VALID_NUMBER", comment: ""))

        } else {
            OWSAlerts.showAlert(title: error.localizedDescription,
                                message: error.localizedRecoverySuggestion)
        }
    }

    // MARK: - Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}
