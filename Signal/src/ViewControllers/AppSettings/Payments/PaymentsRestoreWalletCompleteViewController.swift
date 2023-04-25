//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public class PaymentsRestoreWalletCompleteViewController: OWSTableViewController2 {

    private let passphrase: PaymentsPassphrase

    private weak var restoreWalletDelegate: PaymentsRestoreWalletDelegate?

    private let bottomStack = UIStackView()

    open override var bottomFooter: UIView? {
        get { bottomStack }
        set {}
    }

    public required init(restoreWalletDelegate: PaymentsRestoreWalletDelegate,
                         passphrase: PaymentsPassphrase) {
        self.passphrase = passphrase
        self.restoreWalletDelegate = restoreWalletDelegate

        super.init()

        self.shouldAvoidKeyboard = true
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_TITLE",
                                  comment: "Title for the 'restore payments wallet' view of the app settings.")

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
        let doneButton = OWSFlatButton.button(title: CommonStrings.doneButton,
                                              font: UIFont.dynamicTypeBody.semibold(),
                                              titleColor: .white,
                                              backgroundColor: .ows_accentBlue,
                                              target: self,
                                              selector: #selector(didTapDoneButton))
        doneButton.autoSetHeightUsingFont()

        let editButton = OWSFlatButton.button(title: CommonStrings.editButton,
                                              font: .dynamicTypeBody,
                                              titleColor: .ows_accentBlue,
                                              backgroundColor: self.tableBackgroundColor,
                                              target: self,
                                              selector: #selector(didTapEditButton))
        editButton.autoSetHeightUsingFont()

        bottomStack.axis = .vertical
        bottomStack.alignment = .fill
        bottomStack.isLayoutMarginsRelativeArrangement = true
        bottomStack.layoutMargins = cellOuterInsetsWithMargin(top: 8, left: 20, right: 20)
        bottomStack.addArrangedSubviews([
            doneButton,
            UIView.spacer(withHeight: 8),
            editButton,
            UIView.spacer(withHeight: 8)
        ])
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.customHeaderView = buildHeader()
        section.shouldDisableCellSelection = true

        let passphrase = self.passphrase
        section.add(OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()
            let passphraseGrid = PaymentsViewUtils.buildPassphraseGrid(passphrase: passphrase)
            cell.contentView.addSubview(passphraseGrid)
            passphraseGrid.autoPinEdgesToSuperviewMargins()
            return cell
        },
        actionBlock: nil))
        contents.addSection(section)

        self.contents = contents
    }

    private func buildHeader() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_COMPLETE_TITLE",
                                            comment: "Title for the 'review payments passphrase' step of the 'restore payments wallet' views.")
        titleLabel.font = UIFont.dynamicTypeTitle2Clamped.semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center

        let explanationLabel = UILabel()
        explanationLabel.text = OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_COMPLETE_EXPLANATION",
                                                  comment: "Explanation of the 'review payments passphrase' step of the 'restore payments wallet' views.")
        explanationLabel.font = .dynamicTypeBody2Clamped
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.textAlignment = .center
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping

        let topStack = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 10),
            explanationLabel
        ])
        topStack.axis = .vertical
        topStack.alignment = .center
        topStack.isLayoutMarginsRelativeArrangement = true
        topStack.layoutMargins = cellOuterInsetsWithMargin(top: 32, left: 20, bottom: 40, right: 20)
        return topStack
    }

    private func showInvalidPassphraseAlert() {
        let actionSheet = ActionSheetController(title: OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_INVALID_PASSPHRASE_TITLE",
                                                                         comment: "Title for the 'invalid payments wallet passphrase' error alert in the app payments settings."),
                                                message: OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_INVALID_PASSPHRASE_MESSAGE",
                                                                           comment: "Message for the 'invalid payments wallet passphrase' error alert in the app payments settings."))
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okayButton,
                                                style: .default) { [weak self] _ in
            self?.returnToFirstWordView(shouldClearInput: true)
        })

        presentActionSheet(actionSheet)
    }

    private func showRestoreFailureAlert() {
        OWSActionSheets.showErrorAlert(message: OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_FAILED",
                                                                  comment: "Error indicating that 'restore payments wallet failed' in the app payments settings."))
    }

    // MARK: - Events

    @objc
    func didTapDoneButton() {
        guard payments.paymentsEntropy == nil else {
            owsFailDebug("paymentsEntropy already set.")
            dismiss(animated: true, completion: nil)
            showRestoreFailureAlert()
            return
        }
        guard let paymentsEntropy = paymentsSwift.paymentsEntropy(forPassphrase: passphrase) else {
            showInvalidPassphraseAlert()
            return
        }
        let didSucceed = databaseStorage.write { transaction in
            paymentsHelperSwift.enablePayments(withPaymentsEntropy: paymentsEntropy,
                                               transaction: transaction)
        }
        guard didSucceed else {
            owsFailDebug("Could not restore payments entropy.")
            dismiss(animated: true, completion: nil)
            showRestoreFailureAlert()
            return
        }

        let restoreWalletDelegate = self.restoreWalletDelegate
        dismiss(animated: true, completion: {
            restoreWalletDelegate?.restoreWalletDidComplete()
        })
    }

    @objc
    func didTapEditButton() {
        returnToFirstWordView(shouldClearInput: false)
    }

    private func returnToFirstWordView(shouldClearInput: Bool) {
        guard let navigationController = navigationController else {
            return
        }

        // We want to pop back to the _first_ of the "enter wallet passphrase" views.
        for viewController in navigationController.viewControllers {
            guard let viewController = viewController as? PaymentsRestoreWalletWordViewController else {
                continue
            }
            if shouldClearInput {
                viewController.clearInput()
            }
            navigationController.popToViewController(viewController, animated: true)
            return
        }
        owsFailDebug("Could not return to start of passphrase.")
    }
}
