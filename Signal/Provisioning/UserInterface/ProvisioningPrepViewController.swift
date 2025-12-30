//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI

class ProvisioningPrepViewController: ProvisioningBaseViewController {

    private lazy var animationView: LottieAnimationView = {
        let view = LottieAnimationView(name: isTransferring ? "launchApp-iPad" : "launchApp-iPhone")
        view.loopMode = .playOnce
        view.backgroundBehavior = .pauseAndRestore
        view.contentMode = .scaleAspectFit
        return view
    }()

    private let isTransferring: Bool

    init(provisioningController: ProvisioningController, isTransferring: Bool) {
        self.isTransferring = isTransferring
        super.init(provisioningController: provisioningController)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.hidesBackButton = true

        let titleText: String
        if isTransferring {
            titleText = OWSLocalizedString(
                "SECONDARY_TRANSFER_GET_STARTED_BY_OPENING_IPAD",
                comment: "header text before the user can transfer to this device",
            )

        } else {
            titleText = OWSLocalizedString(
                "SECONDARY_ONBOARDING_GET_STARTED_BY_OPENING_PRIMARY",
                comment: "header text before the user can link this device",
            )
        }
        let titleLabel = UILabel.titleLabelForRegistration(text: titleText)
        titleLabel.setCompressionResistanceHigh()
        titleLabel.accessibilityIdentifier = "onboarding.prelink.titleLabel"

        let animationViewContainer = UIView.container()
        animationViewContainer.addSubview(animationView)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            animationView.topAnchor.constraint(equalTo: animationViewContainer.topAnchor),
            animationView.leadingAnchor.constraint(greaterThanOrEqualTo: animationViewContainer.leadingAnchor),
            animationView.centerXAnchor.constraint(equalTo: animationViewContainer.centerXAnchor),
            animationView.bottomAnchor.constraint(equalTo: animationViewContainer.bottomAnchor),
        ])

        let dontHaveSignalButton = UIButton(
            configuration: .mediumBorderless(title: OWSLocalizedString(
                "SECONDARY_ONBOARDING_GET_STARTED_DO_NOT_HAVE_PRIMARY",
                comment: "Link explaining what to do when trying to link a device before having a primary device.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapNoSignalApp()
            },
        )
        dontHaveSignalButton.enableMultilineLabel()
        dontHaveSignalButton.accessibilityIdentifier = "onboarding.prelink.explanationLabel"
        dontHaveSignalButton.isHidden = isTransferring

        let nextButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.nextButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didPressNext()
            },
        )
        nextButton.accessibilityIdentifier = "onboarding.prelink.nextButton"

        let topSpacer = UIView.transparentSpacer()
        let bottomSpacer = UIView.transparentSpacer()

        let stackView = addStaticContentStackView(arrangedSubviews: [
            topSpacer,
            titleLabel,
            animationViewContainer,
            bottomSpacer,
            [dontHaveSignalButton, nextButton].enclosedInVerticalStackView(isFullWidthButtons: true),
        ])
        stackView.setCustomSpacing(24, after: titleLabel)

        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        animationViewContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor, multiplier: 0.5),
            animationViewContainer.heightAnchor.constraint(equalTo: contentLayoutGuide.heightAnchor, multiplier: 0.5),
        ])

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animationView.play()
    }

    // MARK: - Events

    func didTapNoSignalApp() {
        let title = OWSLocalizedString("SECONDARY_ONBOARDING_INSTALL_PRIMARY_FIRST_TITLE", comment: "alert title")
        let message = OWSLocalizedString("SECONDARY_ONBOARDING_INSTALL_PRIMARY_FIRST_BODY", comment: "alert body")
        let alert = ActionSheetController(title: title, message: message)
        alert.addAction(.acknowledge)
        presentActionSheet(alert)
    }

    func didPressNext() {
        Logger.info("")

        Task {
            if isTransferring {
                await provisioningController.transferAccount(fromViewController: self)
            } else {
                await provisioningController.didConfirmSecondaryDevice(from: self)
            }
        }
    }
}
