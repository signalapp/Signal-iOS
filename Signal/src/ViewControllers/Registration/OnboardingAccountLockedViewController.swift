//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import SafariServices

@objc
public class OnboardingAccountLockedViewController: OnboardingBaseViewController {
    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.titleLabel(text:
            NSLocalizedString("ONBOARDING_ACCOUNT_LOCKED_TITLE",
                              comment: "Title of the 'onboarding account locked' view."))
        titleLabel.accessibilityIdentifier = "onboarding.accountLocked." + "titleLabel"

        let explanationLabel = self.explanationLabel(explanationText:
            NSLocalizedString("ONBOARDING_ACCOUNT_LOCKED_EXPLANATION",
                              comment: "Explanation of the 'onboarding account locked' view."))
        explanationLabel.font = UIFont.ows_dynamicTypeBodyClamped
        explanationLabel.textColor = Theme.primaryTextColor
        explanationLabel.accessibilityIdentifier = "onboarding.accountLocked." + "explanationLabel"

        let okayButton = self.primaryButton(
            title: NSLocalizedString("BUTTON_OKAY",
                                     comment: "Label for the 'okay' button."),
            selector: #selector(okayPressed)
        )
        okayButton.accessibilityIdentifier = "onboarding.accountLocked." + "okayButton"
        let primaryButtonView = OnboardingBaseViewController.horizontallyWrap(primaryButton: okayButton)

        let learnMoreLink = self.linkButton(
            title: NSLocalizedString("ONBOARDING_ACCOUNT_LOCKED_LEARN_MORE",
                                     comment: "Label for the 'learn more' link in the 'onboarding account locked' view."),
            selector: #selector(learnMoreLinkTapped)
        )
        learnMoreLink.accessibilityIdentifier = "onboarding.accountLocked." + "learnMoreLink"

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 10),
            explanationLabel,
            UIView.vStretchingSpacer(),
            primaryButtonView,
            learnMoreLink
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
        let vc = SFSafariViewController(url: URL(string: "https://support.signal.org/hc/en-us/articles/360007059792")!)
        present(vc, animated: true, completion: nil)
    }

    @objc func okayPressed() {
        Logger.info("")

        navigationController?.popToRootViewController(animated: true)
    }
}
