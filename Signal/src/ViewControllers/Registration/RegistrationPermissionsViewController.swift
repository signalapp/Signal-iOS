//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Lottie

// MARK: - RegistrationPermissionsState

struct RegistrationPermissionsState {
    let shouldRequestAccessToContacts: Bool
}

// MARK: - RegistrationPermissionsPresenter

protocol RegistrationPermissionsPresenter: AnyObject {
    func requestAccessToNotifications() -> Guarantee<Void>
    func requestAccessToContacts() -> Guarantee<Void>
    func goToNextStep()
}

// MARK: - RegistrationPermissionsViewController

class RegistrationPermissionsViewController: OWSViewController {
    private let state: RegistrationPermissionsState
    private weak var presenter: RegistrationPermissionsPresenter?

    public init(
        state: RegistrationPermissionsState,
        presenter: RegistrationPermissionsPresenter?
    ) {
        self.state = state
        self.presenter = presenter

        super.init()
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    // MARK: Rendering

    private lazy var animationView: AnimationView = {
        let animationView = AnimationView(name: "notificationPermission")
        animationView.loopMode = .playOnce
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.contentMode = .scaleAspectFit
        return animationView
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.backgroundColor

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets.layoutMarginsForRegistration(
            traitCollection.horizontalSizeClass
        )
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        let titleText: String
        let explanationText: String
        let giveAccessText: String
        if state.shouldRequestAccessToContacts {
            titleText = OWSLocalizedString(
                "ONBOARDING_PERMISSIONS_TITLE",
                comment: "Title of the 'onboarding permissions' view."
            )
            explanationText = OWSLocalizedString(
                "ONBOARDING_PERMISSIONS_EXPLANATION",
                comment: "Explanation in the 'onboarding permissions' view."
            )
            giveAccessText = OWSLocalizedString(
                "ONBOARDING_PERMISSIONS_ENABLE_PERMISSIONS_BUTTON",
                comment: "Label for the 'give access' button in the 'onboarding permissions' view."
            )
        } else {
            titleText = OWSLocalizedString(
                "LINKED_ONBOARDING_PERMISSIONS_TITLE",
                comment: "Title of the 'onboarding permissions' view."
            )
            explanationText = OWSLocalizedString(
                "LINKED_ONBOARDING_PERMISSIONS_EXPLANATION",
                comment: "Explanation in the 'onboarding permissions' view."
            )
            giveAccessText = OWSLocalizedString(
                "LINKED_ONBOARDING_PERMISSIONS_ENABLE_PERMISSIONS_BUTTON",
                comment: "Label for the 'give access' button in the 'onboarding permissions' view."
            )
        }

        let titleLabel = UILabel.titleLabelForRegistration(text: titleText)
        titleLabel.accessibilityIdentifier = "registration.permissions.titleLabel"
        titleLabel.setCompressionResistanceVerticalHigh()
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(20, after: titleLabel)

        let explanationLabel = UILabel.explanationLabelForRegistration(text: explanationText)
        explanationLabel.accessibilityIdentifier = "registration.permissions.explanationLabel"
        explanationLabel.setCompressionResistanceVerticalHigh()
        stackView.addArrangedSubview(explanationLabel)
        stackView.setCustomSpacing(60, after: explanationLabel)

        stackView.addArrangedSubview(animationView)
        animationView.setContentHuggingHigh()

        stackView.addArrangedSubview(UIView.vStretchingSpacer(minHeight: 80))

        let giveAccessButton = OWSFlatButton.primaryButtonForRegistration(
            title: giveAccessText,
            target: self,
            selector: #selector(giveAccessPressed)
        )
        giveAccessButton.accessibilityIdentifier = "registration.permissions.giveAccessButton"
        stackView.addArrangedSubview(giveAccessButton)
        giveAccessButton.autoSetDimension(.width, toSize: 280)
        giveAccessButton.autoHCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            giveAccessButton.autoPinEdge(toSuperviewEdge: .leading)
            giveAccessButton.autoPinEdge(toSuperviewEdge: .trailing)
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        animationView.play()
    }

    // MARK: Events

    @objc
    private func giveAccessPressed() {
        Logger.info("")

        requestPermissions()
    }

    // MARK: Requesting permissions

    private func requestPermissions() {
        firstly { [weak self] () -> Guarantee<Void> in
            guard let presenter = self?.presenter else { return .value(()) }

            Logger.info("Requesting notification permissions")
            return presenter.requestAccessToNotifications()
        }.then { [weak self] () -> Guarantee<Void> in
            guard let self, let presenter = self.presenter else {
                return .value(())
            }

            if self.state.shouldRequestAccessToContacts {
                Logger.info("Requesting contact permissions")
                return presenter.requestAccessToContacts()
            } else {
                Logger.info("Not requesting contact permissions")
                return .value(())
            }
        }.done { [weak self] in
            Logger.info("Done requesting permissions")
            self?.presenter?.goToNextStep()
        }
    }
}
