//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

public protocol PaymentsRestoreWalletDelegate: AnyObject {
    func restoreWalletDidComplete()
}

// MARK: -

public class PaymentsRestoreWalletSplashViewController: OWSViewController {

    private weak var restoreWalletDelegate: PaymentsRestoreWalletDelegate?

    public required init(restoreWalletDelegate: PaymentsRestoreWalletDelegate) {
        self.restoreWalletDelegate = restoreWalletDelegate

        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_TITLE",
                                  comment: "Title for the 'restore payments wallet' view of the app settings.")

        OWSTableViewController2.removeBackButtonText(viewController: self)

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                           target: self,
                                                           action: #selector(didTapDismiss),
                                                           accessibilityIdentifier: "dismiss")
        createContents()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateContents()
    }

    private let rootView = UIStackView()

    private func createContents() {

        rootView.axis = .vertical
        rootView.alignment = .fill
        view.addSubview(rootView)
        rootView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        rootView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        rootView.autoPinWidthToSuperviewMargins()

        updateContents()
    }

    private func updateContents() {

        let backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)
        view.backgroundColor = backgroundColor

        let heroImage = UIImageView(image: UIImage(named: "recovery-phrase"))

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_SPLASH_TITLE",
                                            comment: "Title for the first step of the 'restore payments wallet' views.")
        titleLabel.font = UIFont.dynamicTypeTitle2Clamped.semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center

        let explanationLabel = PaymentsViewUtils.buildTextWithLearnMoreLinkTextView(
            text: OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_SPLASH_EXPLANATION",
                                    comment: "Explanation of the 'restore payments wallet' process payments settings."),
            font: .dynamicTypeBody2Clamped,
            learnMoreUrl: "https://support.signal.org/hc/en-us/articles/360057625692#payments_wallet_restore_passphrase")
        explanationLabel.textAlignment = .center

        let topStack = UIStackView(arrangedSubviews: [
            heroImage,
            UIView.spacer(withHeight: 20),
            titleLabel,
            UIView.spacer(withHeight: 10),
            explanationLabel
        ])
        topStack.axis = .vertical
        topStack.alignment = .center
        topStack.isLayoutMarginsRelativeArrangement = true
        topStack.layoutMargins = UIEdgeInsets(hMargin: 20, vMargin: 0)

        let pasteFromPasteboardButton = OWSFlatButton.button(title: OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_PASTE_FROM_PASTEBOARD",
                                                                                      comment: "Label for the 'restore passphrase from pasteboard' button in the 'restore payments wallet from passphrase' view."),
                                               font: UIFont.dynamicTypeBody.semibold(),
                                               titleColor: .ows_accentBlue,
                                               backgroundColor: backgroundColor,
                                               target: self,
                                               selector: #selector(didTapPasteFromPasteboardButton))
        pasteFromPasteboardButton.autoSetHeightUsingFont()

        let enterManuallyButton = OWSFlatButton.button(title: OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_ENTER_MANUALLY",
                                                                                comment: "Label for the 'enter passphrase manually' button in the 'restore payments wallet from passphrase' view."),
                                               font: UIFont.dynamicTypeBody.semibold(),
                                               titleColor: .white,
                                               backgroundColor: .ows_accentBlue,
                                               target: self,
                                               selector: #selector(didTapEnterManuallyButton))
        enterManuallyButton.autoSetHeightUsingFont()

        let spacerFactory = SpacerFactory()

        rootView.removeAllSubviews()
        rootView.addArrangedSubviews([
            spacerFactory.buildVSpacer(),
            topStack,
            spacerFactory.buildVSpacer(),
            pasteFromPasteboardButton,
            UIView.spacer(withHeight: 8),
            enterManuallyButton,
            UIView.spacer(withHeight: 8)
        ])

        spacerFactory.finalizeSpacers()
    }

    // MARK: - Events

    @objc
    private func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }

    @objc
    private func didTapPasteFromPasteboardButton() {
        guard let restoreWalletDelegate = restoreWalletDelegate else {
            owsFailDebug("Missing restoreWalletDelegate.")
            dismiss(animated: true, completion: nil)
            return
        }
        let view = PaymentsRestoreWalletPasteboardViewController(restoreWalletDelegate: restoreWalletDelegate)
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    private func didTapEnterManuallyButton() {
        guard let restoreWalletDelegate = restoreWalletDelegate else {
            owsFailDebug("Missing restoreWalletDelegate.")
            dismiss(animated: true, completion: nil)
            return
        }
        // Start by entering the first word of the partial passphrase.
        let view = PaymentsRestoreWalletWordViewController(restoreWalletDelegate: restoreWalletDelegate,
                                                           partialPassphrase: PartialPaymentsPassphrase.empty,
                                                           wordIndex: 0)
        navigationController?.pushViewController(view, animated: true)
    }
}
