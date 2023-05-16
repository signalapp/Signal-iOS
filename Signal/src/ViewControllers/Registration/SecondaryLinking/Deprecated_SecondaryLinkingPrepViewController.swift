//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Lottie
import SignalMessaging

public class Deprecated_SecondaryLinkingPrepViewController: Deprecated_OnboardingBaseViewController {

    lazy var animationView = AnimationView(name: isTransferring ? "launchApp-iPad" : "launchApp-iPhone")
    let isTransferring: Bool

    public init(onboardingController: Deprecated_OnboardingController, isTransferring: Bool) {
        self.isTransferring = isTransferring
        super.init(onboardingController: onboardingController)
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

        let titleText: String
        if isTransferring {
            titleText = OWSLocalizedString("SECONDARY_TRANSFER_GET_STARTED_BY_OPENING_IPAD",
                                          comment: "header text before the user can transfer to this device")

        } else {
            titleText = OWSLocalizedString("SECONDARY_ONBOARDING_GET_STARTED_BY_OPENING_PRIMARY",
                                          comment: "header text before the user can link this device")
        }

        let titleLabel = self.createTitleLabel(text: titleText)
        primaryView.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.prelink.titleLabel"

        let dontHaveSignalButton = UILabel()
        dontHaveSignalButton.text = OWSLocalizedString("SECONDARY_ONBOARDING_GET_STARTED_DO_NOT_HAVE_PRIMARY",
                                                      comment: "Link explaining what to do when trying to link a device before having a primary device.")
        dontHaveSignalButton.textColor = Theme.accentBlueColor
        dontHaveSignalButton.font = UIFont.dynamicTypeSubheadlineClamped
        dontHaveSignalButton.numberOfLines = 0
        dontHaveSignalButton.textAlignment = .center
        dontHaveSignalButton.lineBreakMode = .byWordWrapping
        dontHaveSignalButton.isUserInteractionEnabled = true
        dontHaveSignalButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapExplanationLabel)))
        dontHaveSignalButton.accessibilityIdentifier = "onboarding.prelink.explanationLabel"
        dontHaveSignalButton.isHidden = isTransferring

        let nextButton = self.primaryButton(title: CommonStrings.nextButton,
                                            selector: #selector(didPressNext))
        nextButton.accessibilityIdentifier = "onboarding.prelink.nextButton"
        let primaryButtonView = Deprecated_OnboardingBaseViewController.horizontallyWrap(primaryButton: nextButton)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 12),
            animationView,
            dontHaveSignalButton,
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

        let title = OWSLocalizedString("SECONDARY_ONBOARDING_INSTALL_PRIMARY_FIRST_TITLE", comment: "alert title")
        let message = OWSLocalizedString("SECONDARY_ONBOARDING_INSTALL_PRIMARY_FIRST_BODY", comment: "alert body")
        let alert = ActionSheetController(title: title, message: message)

        let dismissTitle = OWSLocalizedString("ALERT_ACTION_ACKNOWLEDGE", comment: "generic button text to acknowledge that the corresponding text was read.")

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

        if isTransferring {
            onboardingController.transferAccount(fromViewController: self)
        } else {
            let provisioningController = Deprecated_ProvisioningController(onboardingController: onboardingController)
            provisioningController.didConfirmSecondaryDevice(from: self)
        }
    }
}
