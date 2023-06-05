//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalUI

protocol Deprecated_RegistrationPinAttemptsExhaustedViewDelegate: AnyObject {
    var hasPendingRestoration: Bool { get }

    func pinAttemptsExhaustedViewDidComplete(viewController: Deprecated_RegistrationPinAttemptsExhaustedViewController)
}

// MARK: -

public class Deprecated_RegistrationPinAttemptsExhaustedViewController: Deprecated_RegistrationBaseViewController {

    private weak var delegate: Deprecated_RegistrationPinAttemptsExhaustedViewDelegate?

    var hasPendingRestoration: Bool { delegate?.hasPendingRestoration ?? false }

    required init(delegate: Deprecated_RegistrationPinAttemptsExhaustedViewDelegate) {
        self.delegate = delegate
    }

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleText: String
        let explanationText: String
        let primaryButtonText: String
        let linkButtonText: String

        if hasPendingRestoration {
            titleText = OWSLocalizedString("ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_TITLE",
                                          comment: "Title of the 'onboarding pin attempts exhausted' view when reglock is disabled.")
            explanationText = OWSLocalizedString("ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_EXPLANATION",
                                                comment: "Explanation of the 'onboarding pin attempts exhausted' view when reglock is disabled.")
            primaryButtonText = OWSLocalizedString("ONBOARDING_2FA_CREATE_NEW_PIN",
                                                  comment: "Label for the 'create new pin' button when reglock is disabled during onboarding.")
            linkButtonText = OWSLocalizedString("ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_LEARN_MORE",
                                               comment: "Label for the 'learn more' link when reglock is disabled in the 'onboarding pin attempts exhausted' view.")
        } else {
            titleText = OWSLocalizedString("ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_REGLOCK_TITLE",
                                          comment: "Title of the 'onboarding pin attempts exhausted' view when reglock is enabled.")
            explanationText = OWSLocalizedString("ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_REGLOCK_EXPLANATION",
                                                comment: "Explanation of the 'onboarding pin attempts exhausted' view when reglock is enabled.")
            primaryButtonText = OWSLocalizedString("BUTTON_OKAY",
                                                  comment: "Label for the 'okay' button.")
            linkButtonText = OWSLocalizedString("ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_REGLOCK_LEARN_MORE",
                                               comment: "Label for the 'learn more' link when reglock is enabled in the 'onboarding pin attempts exhausted' view.")
        }

        let titleLabel = self.createTitleLabel(text: titleText)
        titleLabel.accessibilityIdentifier = "onboarding.pinAtttemptsExhausted." + "titleLabel"

        let explanationLabel = self.createExplanationLabel(explanationText: explanationText)
        explanationLabel.font = UIFont.dynamicTypeBodyClamped
        explanationLabel.textColor = Theme.primaryTextColor
        explanationLabel.accessibilityIdentifier = "onboarding.pinAtttemptsExhausted." + "explanationLabel"

        let primaryButton = self.primaryButton(
            title: primaryButtonText,
            selector: #selector(primaryButtonPressed)
        )
        primaryButton.accessibilityIdentifier = "onboarding.pinAtttemptsExhausted." + "primaryButton"
        let primaryButtonView = Deprecated_OnboardingBaseViewController.horizontallyWrap(primaryButton: primaryButton)

        let linkButton = self.linkButton(
            title: linkButtonText,
            selector: #selector(learnMoreLinkTapped)
        )
        linkButton.accessibilityIdentifier = "onboarding.pinAtttemptsExhausted." + "linkButton"

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 10),
            explanationLabel,
            UIView.vStretchingSpacer(),
            primaryButtonView,
            linkButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        primaryView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
    }

    // MARK: - Events

    @objc
    func learnMoreLinkTapped() {
        Logger.info("")

        // TODO PINs: Open the right support center URL
        let vc = SFSafariViewController(url: URL(string: "https://support.signal.org/hc/articles/360007059792")!)
        present(vc, animated: true, completion: nil)
    }

    @objc
    func primaryButtonPressed() {
        Logger.info("")

        guard navigationController != nil else {
            owsFailDebug("Missing navigationController")
            return
        }

        delegate?.pinAttemptsExhaustedViewDidComplete(viewController: self)
    }
}
