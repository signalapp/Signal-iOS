//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit
import SafariServices

@objc
public class OnboardingPinAttemptsExhaustedViewController: OnboardingBaseViewController {

    var hasPendingRestoration: Bool {
        databaseStorage.read { KeyBackupService.hasPendingRestoration(transaction: $0) }
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
            titleText = NSLocalizedString("ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_TITLE",
                                          comment: "Title of the 'onboarding pin attempts exhausted' view when reglock is disabled.")
            explanationText = NSLocalizedString("ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_EXPLANATION",
                                                comment: "Explanation of the 'onboarding pin attempts exhausted' view when reglock is disabled.")
            primaryButtonText = NSLocalizedString("ONBOARDING_2FA_CREATE_NEW_PIN",
                                                  comment: "Label for the 'create new pin' button when reglock is disabled during onboarding.")
            linkButtonText = NSLocalizedString("ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_LEARN_MORE",
                                               comment: "Label for the 'learn more' link when reglock is disabled in the 'onboarding pin attempts exhausted' view.")
        } else {
            titleText = NSLocalizedString("ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_REGLOCK_TITLE",
                                          comment: "Title of the 'onboarding pin attempts exhausted' view when reglock is enabled.")
            explanationText = NSLocalizedString("ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_REGLOCK_EXPLANATION",
                                                comment: "Explanation of the 'onboarding pin attempts exhausted' view when reglock is enabled.")
            primaryButtonText = NSLocalizedString("BUTTON_OKAY",
                                                  comment: "Label for the 'okay' button.")
            linkButtonText = NSLocalizedString("ONBOARDING_PIN_ATTEMPTS_EXHAUSTED_REGLOCK_LEARN_MORE",
                                               comment: "Label for the 'learn more' link when reglock is enabled in the 'onboarding pin attempts exhausted' view.")
        }

        let titleLabel = self.titleLabel(text: titleText)
        titleLabel.accessibilityIdentifier = "onboarding.pinAtttemptsExhausted." + "titleLabel"

        let explanationLabel = self.explanationLabel(explanationText: explanationText)
        explanationLabel.font = UIFont.ows_dynamicTypeBodyClamped
        explanationLabel.textColor = Theme.primaryTextColor
        explanationLabel.accessibilityIdentifier = "onboarding.pinAtttemptsExhausted." + "explanationLabel"

        let primaryButton = self.primaryButton(
            title: primaryButtonText,
            selector: #selector(primaryButtonPressed)
        )
        primaryButton.accessibilityIdentifier = "onboarding.pinAtttemptsExhausted." + "primaryButton"
        let primaryButtonView = OnboardingBaseViewController.horizontallyWrap(primaryButton: primaryButton)

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

    @objc func learnMoreLinkTapped() {
        Logger.info("")

        // TODO PINs: Open the right support center URL
        let vc = SFSafariViewController(url: URL(string: "https://support.signal.org/hc/articles/360007059792")!)
        present(vc, animated: true, completion: nil)
    }

    @objc func primaryButtonPressed() {
        Logger.info("")

        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        if hasPendingRestoration {
            SDSDatabaseStorage.shared.write { transaction in
                KeyBackupService.clearPendingRestoration(transaction: transaction)
            }
            onboardingController.showNextMilestone(navigationController: navigationController)
        } else {
            navigationController.popToRootViewController(animated: true)

        }
    }
}
