//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

class AdvancedPinSettingsTableViewController: OWSTableViewController2 {

    private let context: ViewControllerContext

    public override init() {
        // TODO[ViewContextPiping]
        self.context = ViewControllerContext.shared
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_ADVANCED_PIN_TITLE", comment: "The title for the advanced pin settings.")

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let pinsSection = OWSTableSection()

        pinsSection.add(OWSTableItem.actionItem(
            withText: (context.keyBackupService.hasMasterKey && !context.keyBackupService.hasBackedUpMasterKey)
                ? NSLocalizedString("SETTINGS_ADVANCED_PINS_ENABLE_PIN_ACTION",
                                    comment: "")
                : NSLocalizedString("SETTINGS_ADVANCED_PINS_DISABLE_PIN_ACTION",
                                    comment: ""),
            textColor: Theme.accentBlueColor,
            accessibilityIdentifier: "advancedPinSettings.disable",
            actionBlock: { [weak self] in
                self?.enableOrDisablePin()
        }))
        contents.addSection(pinsSection)

        self.contents = contents
    }

    private func enableOrDisablePin() {
        if context.keyBackupService.hasMasterKey && !context.keyBackupService.hasBackedUpMasterKey {
            enablePin()
        } else {
            if self.paymentsHelper.arePaymentsEnabled,
               !PaymentsSettingsViewController.hasReviewedPassphraseWithSneakyTransaction() {
                showReviewPassphraseAlertUI()
            } else {
                disablePin()
            }
        }
    }

    private func enablePin() {
        let viewController = PinSetupViewController(
            mode: .creating,
            hideNavigationBar: false,
            completionHandler: { [weak self] _, _ in
                guard let self = self else { return }
                self.navigationController?.popToViewController(self, animated: true)
                self.updateTableContents()
            }
        )
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func disablePin() {
        firstly(on: DispatchQueue.main) {
            PinSetupViewController.disablePinWithConfirmation(fromViewController: self)
        }.done { [weak self] _ in
            self?.updateTableContents()
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private func showReviewPassphraseAlertUI() {
        AssertIsOnMainThread()

        let actionSheet = ActionSheetController(title: NSLocalizedString("SETTINGS_PAYMENTS_RECORD_PASSPHRASE_DISABLE_PIN_TITLE",
                                                                         comment: "Title for the 'record payments passphrase to disable pin' UI in the app settings."),
                                                message: NSLocalizedString("SETTINGS_PAYMENTS_RECORD_PASSPHRASE_DISABLE_PIN_DESCRIPTION",
                                                                           comment: "Description for the 'record payments passphrase to disable pin' UI in the app settings."))

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("SETTINGS_PAYMENTS_RECORD_PASSPHRASE_DISABLE_PIN_RECORD_PASSPHRASE",
                                                                         comment: "Label for the 'record recovery passphrase' button in the 'record payments passphrase to disable pin' UI in the app settings."),
                                                accessibilityIdentifier: "payments.settings.disable-pin.record-passphrase",
                                                style: .default) { [weak self] _ in
            self?.showRecordPaymentsPassphraseUI()
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func showRecordPaymentsPassphraseUI() {
        guard let passphrase = paymentsSwift.passphrase else {
            owsFailDebug("Missing passphrase.")
            return
        }
        let view = PaymentsViewPassphraseSplashViewController(passphrase: passphrase,
                                                              style: .reviewed,
                                                              viewPassphraseDelegate: self)
        let navigationVC = OWSNavigationController(rootViewController: view)
        present(navigationVC, animated: true)
    }
}

// MARK: -

extension AdvancedPinSettingsTableViewController: PaymentsViewPassphraseDelegate {
    public func viewPassphraseDidComplete() {
        PaymentsSettingsViewController.setHasReviewedPassphraseWithSneakyTransaction()

        presentToast(text: NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COMPLETE_TOAST",
                                             comment: "Message indicating that 'payments passphrase review' is complete."))
    }

    public func viewPassphraseDidCancel(viewController: PaymentsViewPassphraseSplashViewController) {
        viewController.dismiss(animated: true)
    }
}
