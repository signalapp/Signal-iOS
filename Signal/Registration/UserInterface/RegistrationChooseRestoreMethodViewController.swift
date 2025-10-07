//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

protocol RegistrationChooseRestoreMethodPresenter: AnyObject {
    func didChooseRestoreMethod(method: RegistrationRestoreMethod)
    func didCancelRestoreMethodSelection()
}

public enum RegistrationRestoreMethod {
    case deviceTransfer
    case local
    case remote
    case declined
}

class RegistrationChooseRestoreMethodViewController: OWSViewController {

    private weak var presenter: RegistrationChooseRestoreMethodPresenter?
    private let restorePath: RegistrationStep.RestorePath

    public init(
        presenter: RegistrationChooseRestoreMethodPresenter,
        restorePath: RegistrationStep.RestorePath
    ) {
        self.presenter = presenter
        self.restorePath = restorePath

        super.init()

        navigationItem.hidesBackButton = true
    }

    // MARK: UI

    private func prominentRestoreButton() -> UIButton {
        return UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_BACKUPS_TITLE",
                comment: "The title for the device transfer 'choice' view 'restore backup' option"
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_BACKUPS_BODY",
                comment: "The body for the device transfer 'choice' view 'restore backup' option"
            ),
            iconName: "signal-backups-48",
            primaryAction: UIAction { [weak self] _ in
                self?.didSelectRestoreFromBackup()
            }
        )
    }

    private func prominentTransferButton() -> UIButton {
        return UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_TRANSFER_TITLE",
                comment: "The title for the device transfer 'choice' view 'transfer' option"
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_TRANSFER_BODY",
                comment: "The body for the device transfer 'choice' view 'transfer' option"
            ),
            iconName: "transfer-48",
            primaryAction: UIAction { [weak self] _ in
                self?.didSelectDeviceTransfer()
            }
        )
    }

    private func prominentSkipRestoreButton() -> UIButton {
        return UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_SKIP_RESTORE_TITLE",
                comment: "The title for the skip restore 'choice' option"
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_SKIP_RESTORE_BODY",
                comment: "The body for the skip restore 'choice' option"
            ),
            iconName: "continue-48",
            primaryAction: UIAction { [weak self] _ in
                self?.didSkipRestore()
            }
        )
    }

    private func skipRestoreButton(isLargeButton: Bool) -> UIButton {
        let buttonTitle = OWSLocalizedString(
            "ONBOARDING_CHOOSE_RESTORE_METHOD_SKIP_RESTORE_SMALL_TITLE",
            comment: "The title for a less-prominent skip restore 'choice' option"
        )
        let buttonConfiguration: UIButton.Configuration
        if isLargeButton {
            buttonConfiguration = .largeSecondary(title: buttonTitle)
        } else {
            buttonConfiguration = .mediumSecondary(title: buttonTitle)
        }
        return UIButton(
            configuration: buttonConfiguration,
            primaryAction: UIAction { [weak self] _ in
                self?.didSkipRestore()
            }
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        // Content view.
        let stackView = UIStackView()
        var bottomView: UIView?
        switch self.restorePath {
        case .quickRestore(let tier, let platform) where platform == .android:
            switch tier {
            case .free, .paid:
                addDefaultTitle(to: stackView)
                stackView.addArrangedSubviews([
                    prominentRestoreButton(),
                    prominentSkipRestoreButton(),
                ])
            case .none:
                addNoRestoreOptionViews(to: stackView)
            }
        case .quickRestore(let tier, _):
            addDefaultTitle(to: stackView)
            switch tier {
            case .free:
                stackView.addArrangedSubviews([
                    prominentTransferButton(),
                    prominentRestoreButton(),
                ])
                bottomView = addCompactButtonToTheBottom(button: skipRestoreButton(isLargeButton: false))
            case .paid:
                stackView.addArrangedSubviews([
                    prominentRestoreButton(),
                    prominentTransferButton()
                ])
                bottomView = addCompactButtonToTheBottom(button: skipRestoreButton(isLargeButton: false))
            case .none:
                stackView.addArrangedSubviews([
                    prominentTransferButton(),
                    prominentSkipRestoreButton(),
                ])
            }
        case .manualRestore:
            addDefaultTitle(to: stackView)
            stackView.addArrangedSubviews([
                prominentRestoreButton(),
                prominentSkipRestoreButton(),
            ])
            let cancelButton = UIButton(
                configuration: .mediumSecondary(title: CommonStrings.cancelButton),
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapCancel()
                }
            )
            bottomView = addCompactButtonToTheBottom(button: cancelButton)
        case .unspecified:
            addDefaultTitle(to: stackView)
            stackView.addArrangedSubviews([
                prominentTransferButton(),
                prominentRestoreButton(),
                prominentSkipRestoreButton(),
            ])
        }
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 12
        stackView.preservesSuperviewLayoutMargins = true
        stackView.isLayoutMarginsRelativeArrangement = true

        // Constraints.
        let scrollView = UIScrollView()
        scrollView.preservesSuperviewLayoutMargins = true
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        if let bottomView {
            NSLayoutConstraint.activate([
                scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: bottomView.topAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
        }

        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func addDefaultTitle(to stackView: UIStackView) {
        let titleLabel = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_TITLE",
                comment: "If a user is installing Signal on a new phone, they may be asked whether they want to restore their device from a backup."
            )
        )
        let explanationLabel = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_DESCRIPTION",
                comment: "If a user is installing Signal on a new phone, they may be asked whether they want to restore their device from a backup. This is a description of that question."
            )
        )
        stackView.addArrangedSubviews([
            titleLabel,
            explanationLabel
        ])
        stackView.setCustomSpacing(24, after: explanationLabel)
    }

    private func addCompactButtonToTheBottom(button: UIButton) -> UIView {
        button.setContentHuggingVerticalHigh()

        // Compact button centered in a short container view.
        let buttonContainer = UIView.container()
        buttonContainer.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            button.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            button.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: -16),
        ])

        view.addSubview(buttonContainer)
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buttonContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        return buttonContainer
    }

    private func addNoRestoreOptionViews(to stackView: UIStackView) {
        let title = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_NONE_AVAILABLE_TITLE",
                comment: "Title displayed to a user during registration if there are no restore options available."
            )
        )
        let body = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_CHOOSE_RESTORE_METHOD_NONE_AVAILABLE_BODY",
                comment: "Message body displayed to a user during registration if there are no restore options available."
            )
        )
        stackView.addArrangedSubviews([
            title,
            body
        ])
        stackView.setCustomSpacing(32, after: body)

        func labelWithImage(imageName: String, text: String) -> UIView {
            let image = UIImageView(image: UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate))
            image.tintColor = .Signal.secondaryLabel
            let label = UILabel.explanationLabelForRegistration(text: text)
            label.textAlignment = .natural
            let stackView = UIStackView(
                arrangedSubviews: [
                    image,
                    label,
                    SpacerView()
                ]
            )
            stackView.axis = .horizontal
            stackView.alignment = .firstBaseline
            stackView.isLayoutMarginsRelativeArrangement = true
            stackView.spacing = 16
            stackView.directionalLayoutMargins = .init(top: 6, leading: 30, bottom: 6, trailing: 30)
            return stackView
        }

        stackView.addArrangedSubviews([
            labelWithImage(imageName: "device-phone", text: OWSLocalizedString(
                "REGISTRATION_RESTORE_METHOD_MAKE_BACKUP_TUTORIAL_OPEN_SIGNAL",
                comment: "First step in directions for how to make a backup"
            )),
            labelWithImage(imageName: "backup", text: OWSLocalizedString(
                "REGISTRATION_RESTORE_METHOD_MAKE_BACKUP_TUTORIAL_TAP_SETTINGS",
                comment: "Second step in directions for how to make a backup"
            )),
            labelWithImage(imageName: "check-circle", text: OWSLocalizedString(
                "REGISTRATION_RESTORE_METHOD_MAKE_BACKUP_TUTORIAL_ENABLE_BACKUPS",
                comment: "Third step in directions for how to make a backup"
            ))
        ])

        let buttonContainer = UIView.container()
        buttonContainer.preservesSuperviewLayoutMargins = true

        // Show large "No backup to restore" and "Skip Restore"
        let continueButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.okayButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapCancel()
            }
        )
        buttonContainer.addSubview(continueButton)

        let skipRestoreButton = skipRestoreButton(isLargeButton: true)
        buttonContainer.addSubview(skipRestoreButton)

        continueButton.translatesAutoresizingMaskIntoConstraints = false
        skipRestoreButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            continueButton.centerXAnchor.constraint(equalTo: buttonContainer.layoutMarginsGuide.centerXAnchor),
            continueButton.topAnchor.constraint(equalTo: buttonContainer.layoutMarginsGuide.topAnchor),
            continueButton.leadingAnchor.constraint(equalTo: buttonContainer.layoutMarginsGuide.leadingAnchor, constant: 22),

            skipRestoreButton.topAnchor.constraint(equalTo: continueButton.bottomAnchor, constant: 12),
            skipRestoreButton.leadingAnchor.constraint(equalTo: continueButton.leadingAnchor),
            skipRestoreButton.trailingAnchor.constraint(equalTo: continueButton.trailingAnchor),
            skipRestoreButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: -16),
        ])

        view.addSubview(buttonContainer)
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buttonContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
   }

    // MARK: Events

    private func didSelectRestoreFromBackup() {
        presenter?.didChooseRestoreMethod(method: .remote)
    }

    private func didSelectDeviceTransfer() {
        presenter?.didChooseRestoreMethod(method: .deviceTransfer)
    }

    private func didSkipRestore() {
        presenter?.didChooseRestoreMethod(method: .declined)
    }

    private func didTapCancel() {
        presenter?.didCancelRestoreMethodSelection()
    }
}

#if DEBUG
private class PreviewRegistrationChooseRestoreMethodPresenter: RegistrationChooseRestoreMethodPresenter {
    func didChooseRestoreMethod(method: RegistrationRestoreMethod) {
        print("restore method: \(method)")
    }

    func didCancelRestoreMethodSelection() {
        print("did cancel")
    }
}

// Need to hold a reference to this since it's held weakly by the VC
private let presenter = PreviewRegistrationChooseRestoreMethodPresenter()

@available(iOS 17, *)
#Preview("Quick Restore iOS free") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(.free, .ios),
        )
    )
}

@available(iOS 17, *)
#Preview("Quick Restore iOS paid") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(.paid, .ios),
        )
    )
}

@available(iOS 17, *)
#Preview("Quick Restore iOS no backups") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(nil, .ios),
        )
    )
}

@available(iOS 17, *)
#Preview("Quick Restore Android source, free") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(.free, .android),
        )
    )
}

@available(iOS 17, *)
#Preview("Quick Restore Android source, paid") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(.paid, .android),
        )
    )
}

@available(iOS 17, *)
#Preview("Quick Restore Android source, no backup") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .quickRestore(nil, .android),
        )
    )
}

@available(iOS 17, *)
#Preview("Manual Restore") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .manualRestore,
        )
    )
}

@available(iOS 17, *)
#Preview("Unspecified") {
    OWSNavigationController(
        rootViewController: RegistrationChooseRestoreMethodViewController(
            presenter: presenter,
            restorePath: .unspecified,
        )
    )
}
#endif
