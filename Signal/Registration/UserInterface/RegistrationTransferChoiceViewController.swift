//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - RegistrationTransferChoicePresenter

protocol RegistrationTransferChoicePresenter: AnyObject {
    func transferDevice()
    func continueRegistration()
}

// MARK: - RegistrationTransferChoiceViewController

class RegistrationTransferChoiceViewController: OWSViewController {
    private weak var presenter: RegistrationTransferChoicePresenter?

    public init(presenter: RegistrationTransferChoicePresenter) {
        self.presenter = presenter

        super.init()

        navigationItem.hidesBackButton = true
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        // Create UI elements.
        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_DEVICE_TRANSFER_CHOICE_TITLE",
            comment: "If a user is installing Signal on a new phone, they may be asked whether they want to transfer their account from their old device. This is the title on the screen that asks them this question."
        ))
        titleLabel.accessibilityIdentifier = "registration.transferChoice.titleLabel"

        let explanationLabel = UILabel.explanationLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_DEVICE_TRANSFER_CHOICE_EXPLANATION",
            comment: "If a user is installing Signal on a new phone, they may be asked whether they want to transfer their account from their old device. This is a description on the screen that asks them this question."
        ))
        explanationLabel.accessibilityIdentifier = "registration.transferChoice.explanationLabel"

        let transferButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "DEVICE_TRANSFER_CHOICE_TRANSFER_TITLE",
                comment: "The title for the device transfer 'choice' view 'transfer' option"
            ),
            subtitle: OWSLocalizedString(
                "DEVICE_TRANSFER_CHOICE_TRANSFER_BODY",
                comment: "The body for the device transfer 'choice' view 'transfer' option"
            ),
            iconName: Theme.iconName(.transfer),
            primaryAction: UIAction { [weak self] _ in
                self?.didSelectTransfer()
            }
        )
        transferButton.accessibilityIdentifier = "registration.transferChoice.transferButton"

        let registerButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "DEVICE_TRANSFER_CHOICE_REGISTER_TITLE",
                comment: "The title for the device transfer 'choice' view 'register' option"
            ),
            subtitle: OWSLocalizedString(
                "DEVICE_TRANSFER_CHOICE_REGISTER_BODY",
                comment: "The body for the device transfer 'choice' view 'register' option"
            ),
            iconName: Theme.iconName(.register),
            primaryAction: UIAction { [weak self] _ in
                self?.didSelectRegister()
            }
        )
        registerButton.accessibilityIdentifier = "registration.transferChoice.registerButton"

        // Put UI elements in a stack view and stack view in a scroll view.
        let scrollView = UIScrollView()
        scrollView.preservesSuperviewLayoutMargins = true
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            registerButton,
            transferButton,
            UIView.vStretchingSpacer(),
        ])
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 12
        stackView.setCustomSpacing(24, after: explanationLabel)
        stackView.preservesSuperviewLayoutMargins = true
        stackView.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
        ])
    }

    // MARK: Events

    private func didSelectTransfer() {
        Logger.info("")

        presenter?.transferDevice()
    }

    private func didSelectRegister() {
        Logger.info("")

        presenter?.continueRegistration()
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationTransferChoicePresenter: RegistrationTransferChoicePresenter {
    func transferDevice() {
        print("transferDevice")
    }
    func continueRegistration() {
        print("continueRegistration")
    }
}
@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationTransferChoicePresenter()
    return UINavigationController(
        rootViewController: RegistrationTransferChoiceViewController(
            presenter: presenter
        )
    )
}

#endif
