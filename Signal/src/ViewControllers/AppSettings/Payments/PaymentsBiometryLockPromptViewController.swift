//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

@MainActor
protocol PaymentsBiometryLockPromptDelegate: AnyObject {
    func didEnablePaymentsLock()
    func didNotEnablePaymentsLock()
}

// MARK: -

private enum KnownDeviceOwnerAuthenticationType {
    case passcode
    case touchId
    case faceId
    case opticId

    static func from(_ deviceOwnerAuthenticationType: DeviceOwnerAuthenticationType) -> KnownDeviceOwnerAuthenticationType? {
        switch deviceOwnerAuthenticationType {
        case .unknown:
            return nil
        case .passcode:
            return .passcode
        case .faceId:
            return .faceId
        case .touchId:
            return .touchId
        case .opticId:
            return .opticId
        }
    }
}

// MARK: -

class PaymentsBiometryLockPromptViewController: OWSViewController {

    private var hasBeenDoubleReminded: Bool = false

    private let knownDeviceOwnerAuthenticationType: KnownDeviceOwnerAuthenticationType

    private weak var delegate: PaymentsBiometryLockPromptDelegate?

    init?(deviceOwnerAuthenticationType: DeviceOwnerAuthenticationType, delegate: PaymentsBiometryLockPromptDelegate?) {
        guard let knownDeviceOwnerAuthenticationType = KnownDeviceOwnerAuthenticationType.from(deviceOwnerAuthenticationType) else {
            return nil
        }
        self.knownDeviceOwnerAuthenticationType = knownDeviceOwnerAuthenticationType
        self.delegate = delegate

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_ENABLE_PAYMENTS_LOCK_PROMPT",
            comment: "Title for the 'enable payments lock' view of the payments activation flow.",
        )
        navigationItem.leftBarButtonItem = .closeButton { [weak self] in
            self?.didTapClose()
        }

        view.backgroundColor = .Signal.groupedBackground

        let heroImage = UIImageView(image: UIImage(named: "payments-lock"))
        let heroImageContainer = UIView.container()
        heroImageContainer.addSubview(heroImage)
        heroImage.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heroImage.topAnchor.constraint(equalTo: heroImageContainer.topAnchor, constant: 24),
            heroImage.centerYAnchor.constraint(equalTo: heroImageContainer.centerYAnchor),

            heroImage.leadingAnchor.constraint(greaterThanOrEqualTo: heroImageContainer.leadingAnchor),
            heroImage.centerXAnchor.constraint(equalTo: heroImageContainer.centerXAnchor),
        ])

        let titleLabel = UILabel.title1Label(text: OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_PAYMENTS_LOCK_PROMPT_TITLE",
            comment: "Title for the content section of the  'payments lock prompt' view shown after payemts activation.",
        ))

        let explanationLabel = UILabel.explanationTextLabel(text: localizedExplanationLabelText())

        let enableButton = UIButton(
            configuration: .largePrimary(title: enableButtonTitle()),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapEnableButton()
            },
        )

        let notNowButton = UIButton(
            configuration: .largeSecondary(title: CommonStrings.notNowButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapNotNowButton()
            },
        )

        addStaticContentStackView(arrangedSubviews: [
            heroImageContainer,
            titleLabel,
            explanationLabel,
            .vStretchingSpacer(),
            [enableButton, notNowButton].enclosedInVerticalStackView(isFullWidthButtons: true),
        ])
    }

    // MARK: - Events

    private func didTapClose() {
        guard hasBeenDoubleReminded == false else {
            dismiss(animated: true, completion: nil)
            return
        }

        showDoubleReminder()
    }

    private func didTapEnableButton() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            SSKEnvironment.shared.owsPaymentsLockRef.setIsPaymentsLockEnabled(true, transaction: transaction)
        }
        dismiss(animated: true, completion: nil)
    }

    private func didTapNotNowButton() {
        guard hasBeenDoubleReminded == false else {
            dismiss(animated: true, completion: nil)
            return
        }

        showDoubleReminder()
    }

    func showDoubleReminder() {
        hasBeenDoubleReminded = true

        let actionSheet = ActionSheetController(
            title: doubleReminderActionSheetTitle(),
            message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_DOUBLE_REMINDER_MESSAGE",
                comment: "Description for the 'double reminder' action sheet in the 'payments lock prompt' view in the payment settings.",
            ),
        )

        actionSheet.addAction(
            ActionSheetAction(
                title: CommonStrings.skipButton,
                style: .destructive,
            ) { [weak self] _ in
                Logger.debug("User is explicitly skipping the double reminder, so dismiss the 'payments lock prompt' view entirely.")
                self?.dismiss(animated: true, completion: nil)
            },
        )

        actionSheet.addAction(
            ActionSheetAction(
                title: CommonStrings.cancelButton,
                style: .cancel,
            ) { _ in
                Logger.debug("User cancelled the payments lock dismissal, dismiss the action sheet so user can reconsider payments lock decision")
            },
        )

        presentActionSheet(actionSheet)
    }

    // MARK: - User-visible text.

    private func localizedExplanationLabelText() -> String {
        switch knownDeviceOwnerAuthenticationType {
        case .faceId:
            OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_EXPLANATION_FACEID",
                comment: "Explanation of 'payments lock' with Face ID in the 'payments lock prompt' view shown after payments activation.",
            )
        case .touchId:
            OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_EXPLANATION_TOUCHID",
                comment: "Explanation of 'payments lock' with Touch ID in the 'payments lock prompt' view shown after payments activation.",
            )
        case .opticId:
            OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_EXPLANATION_OPTICID",
                comment: "Explanation of 'payments lock' with Optic ID in the 'payments lock prompt' view shown after payments activation.",
            )
        case .passcode:
            OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_EXPLANATION_PASSCODE",
                comment: "Explanation of 'payments lock' with passcode in the 'payments lock prompt' view shown after payments activation.",
            )
        }
    }

    private func enableButtonTitle() -> String {
        switch knownDeviceOwnerAuthenticationType {
        case .faceId:
            OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_ENABLE_BUTTON_FACEID",
                comment: "Enable Button title in Payments Lock Prompt view for Face ID.",
            )
        case .touchId:
            OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_ENABLE_BUTTON_TOUCHID",
                comment: "Enable Button title in Payments Lock Prompt view for Touch ID.",
            )
        case .opticId:
            OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_ENABLE_BUTTON_OPTICID",
                comment: "Enable Button title in Payments Lock Prompt view for Optic ID.",
            )
        case .passcode:
            OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_ENABLE_BUTTON_PASSCODE",
                comment: "Enable Button title in Payments Lock Prompt view for Passcode.",
            )
        }
    }

    private func doubleReminderActionSheetTitle() -> String {
        switch knownDeviceOwnerAuthenticationType {
        case .faceId:
            OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_DOUBLE_REMINDER_TITLE_FACEID",
                comment: "Double reminder action sheet title in Payments Lock Prompt view for Face ID.",
            )
        case .touchId:
            OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_DOUBLE_REMINDER_TITLE_TOUCHID",
                comment: "Double reminder action sheet title in Payments Lock Prompt view for Touch ID.",
            )
        case .opticId:
            OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_DOUBLE_REMINDER_TITLE_OPTICID",
                comment: "Double reminder action sheet title in Payments Lock Prompt view for Optic ID.",
            )
        case .passcode:
            OWSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_DOUBLE_REMINDER_TITLE_PASSCODE",
                comment: "Double reminder action sheet title in Payments Lock Prompt view for Passcode.",
            )
        }
    }
}
