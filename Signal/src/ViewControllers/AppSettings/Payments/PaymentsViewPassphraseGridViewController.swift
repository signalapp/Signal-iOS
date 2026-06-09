//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentsViewPassphraseGridViewController: OWSViewController {

    private let passphrase: PaymentsPassphrase

    private weak var viewPassphraseDelegate: PaymentsViewPassphraseDelegate?

    init(
        passphrase: PaymentsPassphrase,
        viewPassphraseDelegate: PaymentsViewPassphraseDelegate,
    ) {
        self.passphrase = passphrase
        self.viewPassphraseDelegate = viewPassphraseDelegate

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let screenLockUI = AppEnvironment.shared.screenLockUI
        screenLockUI.sensitiveContentDidLoad(inViewController: self)

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_TITLE",
            comment: "Title for the 'view payments passphrase' view of the app settings.",
        )

        view.backgroundColor = .Signal.groupedBackground

        let explanationLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_WORDS_EXPLANATION",
            comment: "Header text for the 'review payments passphrase words' step in the 'view payments passphrase' settings.",
        ))

        let copyToClipboardButton = UIButton(
            configuration: .smallSecondary(title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COPY_TO_CLIPBOARD",
                comment: "Label for the 'copy to clipboard' button in the 'view payments passphrase' views.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.showCopyToClipboardConfirmUI()
            },
        )
        let passphraseGrid = PaymentsUI.buildPassphraseGrid(
            passphrase: passphrase,
            footerButton: copyToClipboardButton,
        )
        let passphraseGridContainer = UIView()
        passphraseGridContainer.directionalLayoutMargins = .init(margin: 24)
        passphraseGridContainer.backgroundColor = .Signal.secondaryGroupedBackground
        if #available(iOS 26, *) {
            passphraseGridContainer.cornerConfiguration = .uniformCorners(radius: 26)
        } else {
            passphraseGridContainer.layer.cornerRadius = 10
        }
        passphraseGridContainer.addSubview(passphraseGrid)
        passphraseGrid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            passphraseGrid.topAnchor.constraint(equalTo: passphraseGridContainer.layoutMarginsGuide.topAnchor),
            passphraseGrid.leadingAnchor.constraint(equalTo: passphraseGridContainer.layoutMarginsGuide.leadingAnchor),
            passphraseGrid.trailingAnchor.constraint(equalTo: passphraseGridContainer.layoutMarginsGuide.trailingAnchor),
            passphraseGrid.bottomAnchor.constraint(equalTo: passphraseGridContainer.layoutMarginsGuide.bottomAnchor),
        ])

        let warningLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_WORDS_FOOTER_2",
            comment: "Footer text for the 'review payments passphrase words' step in the 'view payments passphrase' settings.",
        ))

        let nextButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.nextButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapNextButton()
            },
        )

        let stackView = addStaticContentStackView(
            arrangedSubviews: [
                .spacer(withHeight: 16),
                explanationLabel,
                passphraseGridContainer,
                warningLabel,
                .vStretchingSpacer(),
                [nextButton].enclosedInVerticalStackView(isFullWidthButtons: true),
            ],
            isScrollable: true,
        )
        stackView.setCustomSpacing(24, after: explanationLabel)
    }

    // MARK: - Events

    private func didTapNextButton() {
        guard let viewPassphraseDelegate else {
            dismiss(animated: false, completion: nil)
            return
        }
        let view = PaymentsViewPassphraseConfirmViewController(
            passphrase: passphrase,
            viewPassphraseDelegate: viewPassphraseDelegate,
        )
        navigationController?.pushViewController(view, animated: true)
    }

    private func showCopyToClipboardConfirmUI() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COPY_TO_CLIPBOARD_CONFIRM_TITLE",
                comment: "Title for the 'copy recovery passphrase to clipboard confirm' alert in the payment settings.",
            ),
            message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COPY_TO_CLIPBOARD_CONFIRM_MESSAGE",
                comment: "Message for the 'copy recovery passphrase to clipboard confirm' alert in the payment settings.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.copyButton,
            style: .default,
        ) { [weak self] _ in
            self?.didTapCopyToClipboard()
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func didTapCopyToClipboard() {
        // Ensure that passphrase only resides in pasteboard for short window of time.
        let pasteboardDuration: TimeInterval = .second * 30
        let expireDate = Date().addingTimeInterval(pasteboardDuration)
        UIPasteboard.general.setItems(
            [[UIPasteboard.typeAutomatic: passphrase.asPassphrase]],
            options: [.expirationDate: expireDate],
        )

        presentToast(
            text: OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COPIED_TO_CLIPBOARD",
                comment: "Indicator that the payments passphrase has been copied to the clipboard in the 'view payments passphrase' views.",
            ),
            image: .copy,
        )
    }
}
