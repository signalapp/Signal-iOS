//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public class PaymentsViewPassphraseGridViewController: OWSTableViewController2 {

    private let passphrase: PaymentsPassphrase

    private weak var viewPassphraseDelegate: PaymentsViewPassphraseDelegate?

    private let bottomStack = UIStackView()

    open override var bottomFooter: UIView? {
        get { bottomStack }
        set {}
    }

    public required init(passphrase: PaymentsPassphrase,
                         viewPassphraseDelegate: PaymentsViewPassphraseDelegate) {
        self.passphrase = passphrase
        self.viewPassphraseDelegate = viewPassphraseDelegate

        super.init()

        self.shouldAvoidKeyboard = true
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_TITLE",
                                  comment: "Title for the 'view payments passphrase' view of the app settings.")

        buildBottomView()
        updateTableContents()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateTableContents()
    }

    private func buildBottomView() {
        let nextButton = OWSFlatButton.button(title: CommonStrings.nextButton,
                                              font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                              titleColor: .white,
                                              backgroundColor: .ows_accentBlue,
                                              target: self,
                                              selector: #selector(didTapNextButton))
        nextButton.autoSetHeightUsingFont()

        bottomStack.axis = .vertical
        bottomStack.alignment = .fill
        bottomStack.isLayoutMarginsRelativeArrangement = true
        bottomStack.layoutMargins = cellOuterInsetsWithMargin(top: 8, left: 20, right: 20)
        bottomStack.addArrangedSubviews([
            nextButton,
            UIView.spacer(withHeight: 8)
        ])
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.customHeaderView = buildHeader()
        section.customFooterView = buildFooter()
        section.hasBackground = false
        section.shouldDisableCellSelection = true

        let passphrase = self.passphrase
        section.add(OWSTableItem(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            guard let self = self else { return cell }
            let passphraseGrid = self.buildPassphraseGrid(passphrase: passphrase)
            cell.contentView.addSubview(passphraseGrid)
            passphraseGrid.autoPinEdgesToSuperviewMargins()
            return cell
        },
        actionBlock: nil))
        contents.addSection(section)

        self.contents = contents
    }

    private func buildPassphraseGrid(passphrase: PaymentsPassphrase) -> UIView {
        let copyToClipboardLabel = UILabel()
        copyToClipboardLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COPY_TO_CLIPBOARD",
                                                      comment: "Label for the 'copy to clipboard' button in the 'view payments passphrase' views.")
        copyToClipboardLabel.textColor = .ows_accentBlue
        copyToClipboardLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        let copyToClipboardButton = OWSLayerView.pillView()
        copyToClipboardButton.backgroundColor = Theme.secondaryBackgroundColor
        copyToClipboardButton.addSubview(copyToClipboardLabel)
        copyToClipboardButton.layoutMargins = .init(hMargin: 16, vMargin: 4)
        copyToClipboardLabel.autoPinEdgesToSuperviewMargins()
        copyToClipboardButton.isUserInteractionEnabled = true
        copyToClipboardButton.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                                          action: #selector(showCopyToClipboardConfirmUI)))

        return PaymentsViewUtils.buildPassphraseGrid(passphrase: passphrase,
                                                     footerButton: copyToClipboardButton)
    }

    private func buildHeader() -> UIView {
        let explanationLabel = UILabel()
        explanationLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_WORDS_EXPLANATION",
                                                  comment: "Header text for the 'review payments passphrase words' step in the 'view payments passphrase' settings.")
        explanationLabel.font = .ows_dynamicTypeBody2Clamped
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.textAlignment = .center
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping

        let topStack = UIStackView(arrangedSubviews: [
            explanationLabel
        ])
        topStack.axis = .vertical
        topStack.alignment = .center
        topStack.isLayoutMarginsRelativeArrangement = true
        topStack.layoutMargins = cellOuterInsetsWithMargin(top: 32, left: 20, bottom: 40, right: 20)
        return topStack
    }

    private func buildFooter() -> UIView {
        let explanationLabel = UILabel()
        explanationLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_WORDS_FOOTER",
                                                  comment: "Footer text for the 'review payments passphrase words' step in the 'view payments passphrase' settings.")
        explanationLabel.font = .ows_dynamicTypeSubheadlineClamped
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.textAlignment = .center
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping

        let topStack = UIStackView(arrangedSubviews: [
            explanationLabel
        ])
        topStack.axis = .vertical
        topStack.alignment = .center
        topStack.isLayoutMarginsRelativeArrangement = true
        topStack.layoutMargins = cellOuterInsetsWithMargin(hMargin: 20, vMargin: 16)
        return topStack
    }

    // MARK: - Events

    @objc
    func didTapNextButton() {
        guard let viewPassphraseDelegate = viewPassphraseDelegate else {
            dismiss(animated: false, completion: nil)
            return
        }
        let view = PaymentsViewPassphraseConfirmViewController(passphrase: passphrase,
                                                               viewPassphraseDelegate: viewPassphraseDelegate)
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    func showCopyToClipboardConfirmUI() {

        let actionSheet = ActionSheetController(title: NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COPY_TO_CLIPBOARD_CONFIRM_TITLE",
                                                                         comment: "Title for the 'copy recovery passphrase to clipboard confirm' alert in the payment settings."),
                                                message: NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COPY_TO_CLIPBOARD_CONFIRM_MESSAGE",
                                                                           comment: "Message for the 'copy recovery passphrase to clipboard confirm' alert in the payment settings."))

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.copyButton,
                                                accessibilityIdentifier: "payments.settings.copy_passphrase_to_clipboard",
                                                style: .default) { [weak self] _ in
            self?.didTapCopyToClipboard()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    @objc
    func didTapCopyToClipboard() {
        // Ensure that passphrase only resides in pasteboard for short window of time.
        let pasteboardDuration = kSecondInterval * 30
        let expireDate = Date().addingTimeInterval(pasteboardDuration)
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: passphrase.asPassphrase]],
                                      options: [.expirationDate: expireDate])

        self.presentToast(text: NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COPIED_TO_CLIPBOARD",
                                                  comment: "Indicator that the payments passphrase has been copied to the clipboard in the 'view payments passphrase' views."),
                          extraVInset: bottomStack.height)
    }
}
