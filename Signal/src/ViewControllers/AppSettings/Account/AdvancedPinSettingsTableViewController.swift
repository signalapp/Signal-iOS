//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class AdvancedPinSettingsTableViewController: OWSTableViewController2 {

    private let context: ViewControllerContext

    override init() {
        // TODO[ViewContextPiping]
        self.context = ViewControllerContext.shared
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_ADVANCED_PIN_TITLE", comment: "The title for the advanced pin settings.")

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        let pinsSection = OWSTableSection()

        let (
            isPinEnabled,
            isReglockV2Enabled,
            isBackupsEnabled,
        ) = context.db.read { tx in
            let ows2FAManager = SSKEnvironment.shared.ows2FAManagerRef
            let backupSettingsStore = BackupSettingsStore()

            let isBackupsEnabled: Bool
            switch backupSettingsStore.backupPlan(tx: tx) {
            case .disabled:
                isBackupsEnabled = false
            case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
                isBackupsEnabled = true
            }

            return (
                ows2FAManager.isPinEnabled(tx: tx),
                ows2FAManager.isRegistrationLockV2Enabled(transaction: tx),
                isBackupsEnabled,
            )
        }

        pinsSection.add(OWSTableItem.item(
            name: isPinEnabled
                ? OWSLocalizedString(
                    "SETTINGS_ADVANCED_PINS_DISABLE_PIN_ACTION",
                    comment: "",
                )
                : OWSLocalizedString(
                    "SETTINGS_ADVANCED_PINS_ENABLE_PIN_ACTION",
                    comment: "",
                ),
            textColor: Theme.accentBlueColor,
            actionBlock: { [weak self] in
                self?.enableOrDisablePin(
                    isPinEnabled: isPinEnabled,
                    isReglockV2Enabled: isReglockV2Enabled,
                    isBackupsEnabled: isBackupsEnabled,
                )
            },
        ))
        contents.add(pinsSection)

        self.contents = contents
    }

    private func enableOrDisablePin(
        isPinEnabled: Bool,
        isReglockV2Enabled: Bool,
        isBackupsEnabled: Bool,
    ) {
        if isPinEnabled {
            if
                SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled,
                !PaymentsSettingsViewController.hasReviewedPassphraseWithSneakyTransaction()
            {
                showReviewPassphraseAlertUI()
            } else if isReglockV2Enabled {
                OWSActionSheets.showActionSheet(
                    message: OWSLocalizedString(
                        "SETTINGS_ADVANCED_PINS_DISABLE_PIN_ACTION_REGLOCK_DISABLE_REQUIRED",
                        comment: "Message shown in an action sheet when attempting to disable PIN, but registration lock is enabled.",
                    ),
                    fromViewController: self,
                )
            } else if isBackupsEnabled {
                OWSActionSheets.showActionSheet(
                    message: OWSLocalizedString(
                        "SETTINGS_ADVANCED_PINS_DISABLE_PIN_ACTION_BACKUPS_DISABLE_REQUIRED",
                        comment: "Message shown in an action sheet when attempting to disable PIN, but Backups is enabled.",
                    ),
                    fromViewController: self,
                )
            } else {
                disablePinWithConfirmation()
            }
        } else {
            showCreatePin()
        }
    }

    private func showCreatePin() {
        let viewController = PinSetupViewController(
            mode: .creating,
            completionHandler: { [weak self] _, _ in
                guard let self else { return }
                self.navigationController?.popToViewController(self, animated: true)
                self.updateTableContents()
            },
        )
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func disablePinWithConfirmation() {
        let accountEntropyPoolManager = DependenciesBridge.shared.accountEntropyPoolManager
        let db = DependenciesBridge.shared.db
        let ows2FAManager = SSKEnvironment.shared.ows2FAManagerRef

        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString(
                "PIN_CREATION_DISABLE_CONFIRMATION_TITLE",
                comment: "Title of the 'pin disable' action sheet.",
            ),
            message: OWSLocalizedString(
                "PIN_CREATION_DISABLE_CONFIRMATION_MESSAGE",
                comment: "Message of the 'pin disable' action sheet.",
            ),
            proceedTitle: OWSLocalizedString(
                "PIN_CREATION_DISABLE_CONFIRMATION_ACTION",
                comment: "Action of the 'pin disable' action sheet.",
            ),
            proceedStyle: .destructive,
            proceedAction: { _ in
                db.write { tx in
                    Logger.warn("Rotating AEP: disabling PIN!")

                    accountEntropyPoolManager.setAccountEntropyPool(
                        newAccountEntropyPool: AccountEntropyPool(),
                        disablePIN: true,
                        tx: tx,
                    )

                    ows2FAManager.markDisabled(transaction: tx)
                }

                self.updateTableContents()
            },
            fromViewController: self,
        )
    }

    private func showReviewPassphraseAlertUI() {
        AssertIsOnMainThread()

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_RECORD_PASSPHRASE_DISABLE_PIN_TITLE",
                comment: "Title for the 'record payments passphrase to disable pin' UI in the app settings.",
            ),
            message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_RECORD_PASSPHRASE_DISABLE_PIN_DESCRIPTION",
                comment: "Description for the 'record payments passphrase to disable pin' UI in the app settings.",
            ),
        )

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_RECORD_PASSPHRASE_DISABLE_PIN_RECORD_PASSPHRASE",
                comment: "Label for the 'record recovery passphrase' button in the 'record payments passphrase to disable pin' UI in the app settings.",
            ),
            style: .default,
        ) { [weak self] _ in
            self?.showRecordPaymentsPassphraseUI()
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func showRecordPaymentsPassphraseUI() {
        guard let passphrase = SUIEnvironment.shared.paymentsSwiftRef.passphrase else {
            owsFailDebug("Missing passphrase.")
            return
        }
        let view = PaymentsViewPassphraseSplashViewController(
            passphrase: passphrase,
            style: .reviewed,
            viewPassphraseDelegate: self,
        )
        let navigationVC = OWSNavigationController(rootViewController: view)
        present(navigationVC, animated: true)
    }
}

// MARK: -

extension AdvancedPinSettingsTableViewController: PaymentsViewPassphraseDelegate {
    func viewPassphraseDidComplete() {
        PaymentsSettingsViewController.setHasReviewedPassphraseWithSneakyTransaction()

        presentToast(text: OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COMPLETE_TOAST",
            comment: "Message indicating that 'payments passphrase review' is complete.",
        ))
    }

    func viewPassphraseDidCancel(viewController: PaymentsViewPassphraseSplashViewController) {
        viewController.dismiss(animated: true)
    }
}
