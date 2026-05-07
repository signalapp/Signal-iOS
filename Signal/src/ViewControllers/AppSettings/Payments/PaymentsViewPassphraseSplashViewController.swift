//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

@MainActor
protocol PaymentsViewPassphraseDelegate: AnyObject {
    func viewPassphraseDidCancel(viewController: PaymentsViewPassphraseSplashViewController)
    func viewPassphraseDidComplete()
}

// MARK: -

class PaymentsViewPassphraseSplashViewController: OWSViewController {

    enum Style: Int, CaseIterable {
        /// From settings menu when user has not completed recovery phrase
        case view
        /// From settings menu after user has completed recovery phrase
        case reviewed
        /// When balance becomes non-zero for the first time
        case fromBalance
        /// From the help card on payments settings
        case fromHelpCard
        /// When dismissing the help card on payments settings
        case fromHelpCardDismiss
    }

    let style: Style

    private let passphrase: PaymentsPassphrase

    private weak var viewPassphraseDelegate: PaymentsViewPassphraseDelegate?

    init(
        passphrase: PaymentsPassphrase,
        style: Style,
        viewPassphraseDelegate: PaymentsViewPassphraseDelegate,
    ) {
        self.passphrase = passphrase
        self.style = style
        self.viewPassphraseDelegate = viewPassphraseDelegate

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_TITLE",
            comment: "Title for the 'view payments passphrase' view of the app settings.",
        )
        navigationItem.leftBarButtonItem = .closeButton { [weak self] in
            self?.didTapDismiss()
        }

        view.backgroundColor = .Signal.groupedBackground

        let heroImage = UIImageView(image: UIImage(named: "recovery-phrase"))
        let heroImageContainer = UIView.container()
        heroImageContainer.addSubview(heroImage)
        heroImage.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heroImage.topAnchor.constraint(equalTo: heroImageContainer.topAnchor, constant: 24),
            heroImage.centerYAnchor.constraint(equalTo: heroImageContainer.centerYAnchor),

            heroImage.leadingAnchor.constraint(greaterThanOrEqualTo: heroImageContainer.leadingAnchor),
            heroImage.centerXAnchor.constraint(equalTo: heroImageContainer.centerXAnchor),
        ])

        let titleLabel = UILabel.title1Label(text: style.title)

        let explanationLabel = PaymentsUI.buildTextWithLearnMoreLinkTextView(
            text: style.explanationText,
            font: .dynamicTypeSubheadlineClamped,
            learnMoreUrl: style.explanationUrl,
        )

        let nextButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.nextButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapNextButton()
            },
        )
        let cancelButton = UIButton(
            configuration: .largeSecondary(title: CommonStrings.notNowButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapDismiss()
            },
        )

        addStaticContentStackView(arrangedSubviews: [
            heroImageContainer,
            titleLabel,
            explanationLabel,
            .vStretchingSpacer(),
            [nextButton, cancelButton].enclosedInVerticalStackView(isFullWidthButtons: true),
        ])
    }

    func showDismissConfirmation() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_PASSPHRASE_DISCARD_CONFIRMATION_TITLE",
                comment: "Title of confirmation alert when discarding recovery phrase.",
            ),
            message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_PASSPHRASE_DISCARD_CONFIRMATION_MESSAGE",
                comment: "Message of confirmation alert when discarding recovery phrase.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_PASSPHRASE_DISCARD_CONFIRMATION_BUTTON",
                comment: "Button when discarding recovery phrase.",
            ),
            style: .destructive,
            handler: { [weak self] _ in
                self?.notifyCancelled()
            },
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
            handler: nil,
        ))
        presentActionSheet(actionSheet)
    }

    private func notifyCancelled() {
        viewPassphraseDelegate?.viewPassphraseDidCancel(viewController: self)
    }

    // MARK: - Events

    private func didTapDismiss() {
        if style.shouldConfirmCancel {
            showDismissConfirmation()
        } else {
            notifyCancelled()
        }
    }

    private func didTapNextButton() {
        guard let viewPassphraseDelegate else {
            dismiss(animated: false, completion: nil)
            return
        }

        guard SSKEnvironment.shared.owsPaymentsLockRef.isPaymentsLockEnabled() else {
            let viewController = PaymentsViewPassphraseGridViewController(
                passphrase: passphrase,
                viewPassphraseDelegate: viewPassphraseDelegate,
            )
            navigationController?.pushViewController(viewController, animated: true)
            return
        }

        SSKEnvironment.shared.owsPaymentsLockRef.tryToUnlock { [weak self] outcome in
            guard let self else { return }
            guard outcome == OWSPaymentsLock.LocalAuthOutcome.success else {
                PaymentActionSheets.showBiometryAuthFailedActionSheet { _ in
                    self.dismiss(animated: false, completion: nil)
                }
                return
            }

            let view = PaymentsViewPassphraseGridViewController(
                passphrase: self.passphrase,
                viewPassphraseDelegate: viewPassphraseDelegate,
            )
            self.navigationController?.pushViewController(view, animated: true)
        }
    }
}

extension PaymentsViewPassphraseSplashViewController.Style {

    var title: String {
        switch self {
        case .reviewed:
            return OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_START_TITLE",
                comment: "Title for the first step of the 'view payments passphrase' views.",
            )
        case .fromBalance, .fromHelpCard, .fromHelpCardDismiss, .view:
            return OWSLocalizedString(
                "SETTINGS_PAYMENTS_SAVE_PASSPHRASE_START_TITLE",
                comment: "Title for the first step of the 'save payments passphrase' views.",
            )
        }
    }

    var explanationText: String {
        switch self {
        case .view, .reviewed:
            return OWSLocalizedString(
                "SETTINGS_PAYMENTS_PASSPHRASE_EXPLANATION",
                comment: "Explanation of the 'payments passphrase' in the 'view payments passphrase' settings.",
            )
        case .fromHelpCard, .fromHelpCardDismiss:
            return OWSLocalizedString(
                "SETTINGS_PAYMENTS_PASSPHRASE_EXPLANATION_FROM_HELP_CARD",
                comment: "Explanation of the 'payments passphrase' when from the help card.",
            )
        case .fromBalance:
            return OWSLocalizedString(
                "SETTINGS_PAYMENTS_PASSPHRASE_EXPLANATION_FROM_BALANCE",
                comment: "Explanation of the 'payments passphrase' when there is a balance.",
            )
        }
    }

    var explanationUrl: URL {
        return URL.Support.Payments.walletViewPassphrase
    }

    var shouldConfirmCancel: Bool {
        switch self {
        case .reviewed:
            return false
        case .fromBalance, .fromHelpCard, .fromHelpCardDismiss, .view:
            return true
        }
    }

    var shouldShowHelpCardAfterCancel: Bool {
        switch self {
        case .reviewed, .fromHelpCardDismiss:
            return false
        case .fromBalance, .fromHelpCard, .view:
            return true
        }
    }
}
