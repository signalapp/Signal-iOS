//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

// MARK: - RegistrationSignalLoginFullDetailsState

public struct RegistrationSignalLoginFullDetailsState: Equatable {
    let aci: Aci
    let aep: SignalServiceKit.AccountEntropyPool
}

// MARK: - RegistrationSignalLoginFullDetailsViewController

/// Shows the full account ID and recovery key of a Signal Login, with
/// buttons to copy each one.
class RegistrationSignalLoginFullDetailsViewController: OWSViewController {

    private enum Constants {
        static let sectionSpacing: CGFloat = 12
        static let sectionHeaderInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16)

        static let cardSize = CGSize(width: 176, height: 100)
        static let cardCornerRadius: CGFloat = 12

        static let recoveryKeyLineSpacing: CGFloat = 8

        static let fieldCornerRadius: CGFloat = 26
        static let fieldInsets = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 16)
        static let actionButtonSize: CGFloat = 24
        static let actionButtonSpacing: CGFloat = 12
        static let recoveryKeyInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 12)

        static let zeroWidthSpace = "\u{200B}"
    }

    private let state: RegistrationSignalLoginFullDetailsState

    init(state: RegistrationSignalLoginFullDetailsState) {
        self.state = state
        super.init()
    }

    @available(*, unavailable)
    override init() {
        owsFail("This should not be called")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.groupedBackground

        navigationItem.title = OWSLocalizedString(
            "REGISTRATION_SIGNAL_LOGIN_FULL_DETAILS_TITLE",
            comment: "Title for the sheet showing the accountID and recovery key of a Signal Login.",
        )

        navigationItem.rightBarButtonItem = .closeButton { [weak self] in
            self?.dismiss(animated: true)
        }

        // Account ID

        let accountIdLabel = UILabel()
        accountIdLabel.font = .monospacedSystemFont(
            ofSize: UIFont.dynamicTypeBodyClamped.pointSize,
            weight: .regular,
        )
        accountIdLabel.textColor = .Signal.label
        accountIdLabel.numberOfLines = 0
        accountIdLabel.lineBreakMode = .byWordWrapping
        // Allow line breaks only after the hyphens, so each group of the UUID stays on one line.
        let accountId = state.aci.serviceIdUppercaseString
        accountIdLabel.text = accountId.replacingOccurrences(
            of: "-",
            with: "-\(Constants.zeroWidthSpace)",
        )
        accountIdLabel.accessibilityLabel = accountId

        let accountIdField = buildField(
            contentView: accountIdLabel,
            actionAccessibilityLabel: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_FULL_DETAILS_COPY_ACCOUNT_ID_ACCESSIBILITY",
                comment: "Accessibility label for the button that copies the account ID on the 'Signal Login' details sheet.",
            ),
            action: { [weak self] in
                self?.copyAccountId()
            },
            actionImage: .copy,
        )

        // Recovery Key

        let aepTextView = AccountEntropyPoolTextView(
            mode: .display(state.aep.forDisplay),
            lineSpacing: Constants.recoveryKeyLineSpacing,
        )
        // The field supplies the background, corners, and insets; the text
        // view sizes its font to fill whatever width remains.
        aepTextView.layer.cornerRadius = 0
        aepTextView.layoutMargins = Constants.recoveryKeyInsets

        let recoveryKeyField = buildField(
            contentView: aepTextView,
            actionAccessibilityLabel: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_FULL_DETAILS_COPY_RECOVERY_KEY_ACCESSIBILITY",
                comment: "Accessibility label for the button that copies the recovery key on the 'Signal Login' details sheet.",
            ),
            action: { [weak self] in
                self?.copyRecoveryKeyWithConfirmation()
            },
            actionImage: .copy,
        )

        // Buttons

        let saveToPasswordManagerButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_FULL_DETAILS_PASSWORD_MANAGER_BUTTON",
                comment: "Button on the 'Signal Login' details sheet to save login to a password manager.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapSaveToPasswordManager()
            },
        )

        let saveAsPDFButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_FULL_DETAILS_SAVE_AS_PDF_BUTTON",
                comment: "Button on the 'Signal Login' details sheet to save the login details as a PDF.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapSaveAsPDF()
            },
        )

        let stackView = addStaticContentStackView(
            arrangedSubviews: [
                buildCardView(),
                buildSectionHeader(text: OWSLocalizedString(
                    "REGISTRATION_SIGNAL_LOGIN_FULL_DETAILS_ACCOUNT_ID_HEADER",
                    comment: "Header above the account ID on the 'Signal Login' details sheet.",
                )),
                accountIdField,
                buildSectionHeader(text: OWSLocalizedString(
                    "REGISTRATION_SIGNAL_LOGIN_FULL_DETAILS_RECOVERY_KEY_HEADER",
                    comment: "Header above the recovery key on the 'Signal Login' details sheet.",
                )),
                recoveryKeyField,
                .vStretchingSpacer(),
                [saveToPasswordManagerButton, saveAsPDFButton].enclosedInVerticalStackView(isFullWidthButtons: true),
            ],
            isScrollable: true,
        )
        stackView.spacing = Constants.sectionSpacing
    }

    // MARK: Views

    private func buildCardView() -> UIView {
        let cardImageView = UIImageView(image: .signalLoginCardSmall)
        cardImageView.translatesAutoresizingMaskIntoConstraints = false
        cardImageView.contentMode = .scaleAspectFit
        cardImageView.layer.shadowColor = UIColor.black.cgColor
        cardImageView.layer.shadowOpacity = 0.2
        cardImageView.layer.shadowRadius = 8
        cardImageView.layer.shadowOffset = CGSize(width: 0, height: 4)
        cardImageView.layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: Constants.cardSize),
            cornerRadius: Constants.cardCornerRadius,
        ).cgPath

        let container = UIView.transparentContainer()
        container.addSubview(cardImageView)
        NSLayoutConstraint.activate([
            cardImageView.widthAnchor.constraint(equalToConstant: Constants.cardSize.width),
            cardImageView.heightAnchor.constraint(equalToConstant: Constants.cardSize.height),
            cardImageView.topAnchor.constraint(equalTo: container.topAnchor),
            cardImageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            cardImageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])
        return container
    }

    private func buildSectionHeader(text: String) -> UIView {
        let label = UILabel()
        label.font = .dynamicTypeHeadlineClamped
        label.textColor = .Signal.label
        label.numberOfLines = 0
        label.text = text
        label.accessibilityTraits = .header

        let container = UIView.transparentContainer()
        container.directionalLayoutMargins = Constants.sectionHeaderInsets
        container.addSubview(label)
        label.autoPinEdgesToSuperviewMargins()
        return container
    }

    /// A rounded field showing `contentView` with a copy button in its
    /// top-trailing corner.
    private func buildField(
        contentView: UIView,
        actionAccessibilityLabel: String,
        action: @escaping () -> Void,
        actionImage: UIImage,
    ) -> UIView {
        var actionConfig = UIButton.Configuration.plain()
        actionConfig.image = actionImage
        actionConfig.contentInsets = .zero
        actionConfig.baseForegroundColor = .Signal.label
        let actionButton = UIButton(
            configuration: actionConfig,
            primaryAction: UIAction { _ in
                action()
            },
        )
        actionButton.accessibilityLabel = actionAccessibilityLabel
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        let field = UIView()
        field.backgroundColor = .Signal.secondaryGroupedBackground
        field.layer.cornerRadius = Constants.fieldCornerRadius
        field.layer.cornerCurve = .continuous
        field.directionalLayoutMargins = Constants.fieldInsets

        contentView.translatesAutoresizingMaskIntoConstraints = false
        field.addSubview(contentView)
        field.addSubview(actionButton)

        let margins = field.layoutMarginsGuide
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: margins.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            contentView.trailingAnchor.constraint(
                equalTo: actionButton.leadingAnchor,
                constant: -Constants.actionButtonSpacing,
            ),

            actionButton.topAnchor.constraint(equalTo: margins.topAnchor),
            actionButton.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: Constants.actionButtonSize),
            actionButton.heightAnchor.constraint(equalToConstant: Constants.actionButtonSize),
        ])
        return field
    }

    // MARK: Actions

    private func copyAccountId() {
        UIPasteboard.general.string = state.aci.serviceIdUppercaseString
        presentCopiedToast(text: OWSLocalizedString(
            "REGISTRATION_SIGNAL_LOGIN_FULL_DETAILS_ACCOUNT_ID_COPIED_TOAST",
            comment: "Toast shown after copying the account ID on the 'Signal Login' details sheet.",
        ))
    }

    private func copyRecoveryKeyWithConfirmation() {
        let warningSheet = BackupNeverShareRecoveryKeySheet(
            primaryButton: HeroSheetViewController.Button(
                title: OWSLocalizedString(
                    "BACKUP_RECORD_KEY_COPY_WARNING_SHEET_PRIMARY_BUTTON_TITLE",
                    comment: "Title for the primary button in a warning sheet shown before copying the user's 'Recovery Key' to the clipboard, which acknowledges the warning and proceeds with the copy.",
                ),
                action: { [weak self] sheet in
                    sheet.dismiss(animated: true) {
                        self?.copyRecoveryKey()
                    }
                },
            ),
            secondaryButton: nil,
        )
        present(warningSheet, animated: true)
    }

    private func copyRecoveryKey() {
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: state.aep.forDisplay.displayString]],
            options: [
                // Don't sync the key across devices.
                .localOnly: true,
                // Only keep the key on the pasteboard for a minute.
                .expirationDate: Date().addingTimeInterval(.minute),
            ],
        )
        presentCopiedToast(text: OWSLocalizedString(
            "REGISTRATION_SIGNAL_LOGIN_FULL_DETAILS_RECOVERY_KEY_COPIED_TOAST",
            comment: "Toast shown after copying the recovery key on the 'Signal Login' details sheet.",
        ))
    }

    private func presentCopiedToast(text: String) {
        let toast = ToastController(text: text, image: .copy)
        toast.presentToastView(from: .bottom, of: view, inset: view.safeAreaInsets.bottom + 8)
    }

    private func didTapSaveToPasswordManager() {
        // TODO[#less]: Save the Signal Login to a password manager.
    }

    private func didTapSaveAsPDF() {
        // TODO[#less]: Export the Signal Login as a PDF.
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    let state = RegistrationSignalLoginFullDetailsState(
        aci: Aci.randomForTesting(),
        aep: AccountEntropyPool(),
    )
    return UINavigationController(
        rootViewController: RegistrationSignalLoginFullDetailsViewController(state: state),
    )
}

#endif
