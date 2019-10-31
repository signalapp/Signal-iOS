//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import Lottie

@objc
public class SecondaryLinkingPrepViewController: OnboardingBaseViewController {

    let provisioningController: ProvisioningController
    let animationView = AnimationView(name: "launchApp")

    public init(provisioningController: ProvisioningController) {
        self.provisioningController = provisioningController
        super.init(onboardingController: provisioningController.onboardingController)
    }

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        animationView.loopMode = .playOnce
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.contentMode = .scaleAspectFit
        animationView.setContentHuggingHigh()

        let titleLabel = self.titleLabel(text: NSLocalizedString("SECONDARY_ONBOARDING_GET_STARTED_BY_OPENING_PRIMARY", comment: "header text before the user can link this device"))
        primaryView.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.prelink.titleLabel"

        let explanationLabel = UILabel()
        explanationLabel.text = NSLocalizedString("SECONDARY_ONBOARDING_GET_STARTED_DO_NOT_HAVE_PRIMARY",
                                                  comment: "Link explaining what to do when trying to link a device before having a primary device.")
        explanationLabel.textColor = .ows_signalBlue
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.isUserInteractionEnabled = true
        explanationLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapExplanationLabel)))
        explanationLabel.accessibilityIdentifier = "onboarding.prelink.explanationLabel"

        let nextButton = self.primaryButton(title: CommonStrings.nextButton,
                                            selector: #selector(didPressNext))
        nextButton.accessibilityIdentifier = "onboarding.prelink.nextButton"
        let primaryButtonView = OnboardingBaseViewController.horizontallyWrap(primaryButton: nextButton)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 12),
            animationView,
            explanationLabel,
            UIView.vStretchingSpacer(minHeight: 12),
            primaryButtonView
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12
        primaryView.addSubview(stackView)

        stackView.autoPinEdgesToSuperviewMargins()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animationView.play()
    }

    // MARK: - Events

    @objc
    func didTapExplanationLabel(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            owsFailDebug("unexpected state: \(sender.state)")
            return
        }

        let title = NSLocalizedString("SECONDARY_ONBOARDING_INSTALL_PRIMARY_FIRST_TITLE", comment: "alert title")
        let message = NSLocalizedString("SECONDARY_ONBOARDING_INSTALL_PRIMARY_FIRST_BODY", comment: "alert body")
        let alert = ActionSheetController(title: title, message: message)

        let dismissTitle = NSLocalizedString("ALERT_ACTION_ACKNOWLEDGE", comment: "generic button text to acknowledge that the corresponding text was read.")

        alert.addAction(
            ActionSheetAction(title: dismissTitle,
                          accessibilityIdentifier: UIView.accessibilityIdentifier(containerName: "alert", name: "acknowledge"),
                          style: .default)
        )

        presentActionSheet(alert)
    }

    @objc
    func didPressNext() {
        Logger.info("")
        provisioningController.didConfirmSecondaryDevice(from: self)
    }
}
