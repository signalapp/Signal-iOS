//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class AccountSettingsViewController: OWSTableViewController2 {

    private let appReadiness: AppReadinessSetter
    private let context: ViewControllerContext

    public init(appReadiness: AppReadinessSetter) {
        self.appReadiness = appReadiness
        // TODO[ViewContextPiping]
        self.context = ViewControllerContext.shared
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_ACCOUNT", comment: "Title for the 'account' link in settings.")

        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
        tableView.layoutIfNeeded()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        // Show the change pin and reglock sections
        if DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice {
            let pinSection = OWSTableSection()
            pinSection.headerTitle = OWSLocalizedString(
                "SETTINGS_PINS_TITLE",
                comment: "Title for the 'PINs' section of the privacy settings."
            )
            pinSection.footerAttributedTitle = NSAttributedString.composed(of: [
                OWSLocalizedString(
                    "SETTINGS_PINS_FOOTER",
                    comment: "Footer for the 'PINs' section of the privacy settings."
                ),
                " ",
                CommonStrings.learnMore.styled(with: .link(URL(string: "https://support.signal.org/hc/articles/360007059792")!))
            ]).styled(
                with: .font(.dynamicTypeCaption1Clamped),
                .color(Theme.secondaryTextAndIconColor)
            )

            pinSection.add(.disclosureItem(
                withText: SSKEnvironment.shared.ows2FAManagerRef.is2FAEnabled
                    ? OWSLocalizedString(
                        "SETTINGS_PINS_ITEM",
                        comment: "Label for the 'pins' item of the privacy settings when the user does have a pin."
                    )
                    : OWSLocalizedString(
                        "SETTINGS_PINS_ITEM_CREATE",
                        comment: "Label for the 'pins' item of the privacy settings when the user doesn't have a pin."
                    ),
                actionBlock: { [weak self] in
                    self?.showCreateOrChangePin()
                }
            ))

            // Reminders toggle.
            if SSKEnvironment.shared.ows2FAManagerRef.is2FAEnabled {
                pinSection.add(.switch(
                    withText: OWSLocalizedString(
                        "SETTINGS_PIN_REMINDER_SWITCH_LABEL",
                        comment: "Label for the 'pin reminder' switch of the privacy settings."
                    ),
                    isOn: { SSKEnvironment.shared.ows2FAManagerRef.areRemindersEnabled },
                    target: self,
                    selector: #selector(arePINRemindersEnabledDidChange)
                ))
            }

            contents.add(pinSection)

            let regLockSection = OWSTableSection()
            regLockSection.footerTitle = OWSLocalizedString(
                "SETTINGS_TWO_FACTOR_PINS_AUTH_FOOTER",
                comment: "Footer for the 'two factor auth' section of the privacy settings when Signal PINs are available."
            )

            regLockSection.add(.switch(
                withText: OWSLocalizedString(
                    "SETTINGS_TWO_FACTOR_AUTH_SWITCH_LABEL",
                    comment: "Label for the 'enable registration lock' switch of the privacy settings."
                ),
                isOn: { SSKEnvironment.shared.ows2FAManagerRef.isRegistrationLockV2Enabled },
                target: self,
                selector: #selector(isRegistrationLockV2EnabledDidChange)
            ))

            contents.add(regLockSection)

            let advancedSection = OWSTableSection()
            advancedSection.add(.disclosureItem(
                withText: OWSLocalizedString(
                    "SETTINGS_ADVANCED_PIN_SETTINGS",
                    comment: "Label for the 'advanced pin settings' button."
                ),
                actionBlock: { [weak self] in
                    let vc = AdvancedPinSettingsTableViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            ))
            contents.add(advancedSection)
        }

        let accountSection = OWSTableSection()
        accountSection.headerTitle = OWSLocalizedString("SETTINGS_ACCOUNT", comment: "Title for the 'account' link in settings.")

        let tsRegistrationState = DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction
        if tsRegistrationState.isDeregistered {
            accountSection.add(.actionItem(
                withText: tsRegistrationState.isPrimaryDevice ?? true
                    ? OWSLocalizedString("SETTINGS_REREGISTER_BUTTON", comment: "Label for re-registration button.")
                    : OWSLocalizedString("SETTINGS_RELINK_BUTTON", comment: "Label for re-link button."),
                textColor: .ows_accentBlue,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "reregister"),
                actionBlock: { [weak self] in
                    self?.reregisterUser()
                }
            ))
            accountSection.add(.actionItem(
                withText: OWSLocalizedString("SETTINGS_DELETE_DATA_BUTTON",
                                            comment: "Label for 'delete data' button."),
                textColor: .ows_accentRed,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "delete_data"),
                actionBlock: { [weak self] in
                    self?.deleteUnregisteredUserData()
                }
            ))
        } else if tsRegistrationState.isRegisteredPrimaryDevice {
            switch self.changeNumberState() {
            case .disallowed:
                break
            case .allowed:
                accountSection.add(.actionItem(
                    withText: OWSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_BUTTON", comment: "Label for button in settings views to change phone number"),
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "change_phone_number"),
                    actionBlock: { [weak self] in
                        guard let self else {
                            return
                        }
                        // Fetch the state again in case it changed from under us
                        // between when the button was rendered and when it was tapped.
                        switch self.changeNumberState() {
                        case .disallowed:
                            return
                        case .allowed(let changeNumberParams):
                            self.changePhoneNumber(changeNumberParams)
                        }
                    }
                ))
            }
            accountSection.add(.actionItem(
                withText: OWSLocalizedString(
                    "SETTINGS_ACCOUNT_DATA_REPORT_BUTTON",
                    comment: "Label for button in settings to get your account data report"
                ),
                accessibilityIdentifier: UIView.accessibilityIdentifier(
                    in: self,
                    name: "request_account_data_report"
                ),
                actionBlock: { [weak self] in
                    self?.requestAccountDataReport()
                }
            ))
            accountSection.add(.actionItem(
                withText: OWSLocalizedString("SETTINGS_DELETE_ACCOUNT_BUTTON", comment: ""),
                textColor: .ows_accentRed,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "delete_account"),
                actionBlock: { [weak self] in
                    self?.unregisterUser()
                }
            ))
        } else {
            accountSection.add(.actionItem(
                withText: OWSLocalizedString("SETTINGS_DELETE_DATA_BUTTON",
                                            comment: "Label for 'delete data' button."),
                textColor: .ows_accentRed,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "delete_data"),
                actionBlock: { [weak self] in
                    self?.deleteLinkedData()
                }
            ))
        }

        contents.add(accountSection)

        self.contents = contents
    }

    // MARK: - Account

    private func reregisterUser() {
        RegistrationUtils.showReregistrationUI(fromViewController: self, appReadiness: appReadiness)
    }

    private func deleteLinkedData() {
        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString("CONFIRM_DELETE_LINKED_DATA_TITLE", comment: ""),
            message: OWSLocalizedString("CONFIRM_DELETE_LINKED_DATA_TEXT", comment: ""),
            proceedTitle: OWSLocalizedString("PROCEED_BUTTON", comment: ""),
            proceedStyle: .destructive
        ) { _ in
            let deviceId = DependenciesBridge.shared.tsAccountManager.storedDeviceIdWithMaybeTransaction
            SignalApp.resetLinkedAppDataWithUI(localDeviceId: deviceId)
        }
    }

    private func unregisterUser() {
        let vc = DeleteAccountConfirmationViewController(appReadiness: appReadiness)
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    private func deleteUnregisteredUserData() {
        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString("CONFIRM_DELETE_DATA_TITLE", comment: ""),
            message: OWSLocalizedString("CONFIRM_DELETE_DATA_TEXT", comment: ""),
            proceedTitle: OWSLocalizedString("PROCEED_BUTTON", comment: ""),
            proceedStyle: .destructive
        ) { _ in
            SignalApp.resetAppDataWithUI()
        }
    }

    private func requestAccountDataReport() {
        let vc = RequestAccountDataReportViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    enum ChangeNumberState {
        case disallowed
        case allowed(RegistrationMode.ChangeNumberParams)
    }

    private func changeNumberState() -> ChangeNumberState {
        return SSKEnvironment.shared.databaseStorageRef.read { transaction -> ChangeNumberState in
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            let tsRegistrationState = tsAccountManager.registrationState(tx: transaction)
            guard tsRegistrationState.isRegistered else {
                return .disallowed
            }
            let loader = RegistrationCoordinatorLoaderImpl(dependencies: .from(self))
            switch loader.restoreLastMode(transaction: transaction) {
            case .none, .changingNumber:
                break
            case .registering, .reRegistering:
                // Don't allow changing number if we are in the middle of registering.
                return .disallowed
            }
            let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
            guard
                let localIdentifiers = tsAccountManager.localIdentifiers(tx: transaction),
                let localE164 = E164(localIdentifiers.phoneNumber),
                let authToken = tsAccountManager.storedServerAuthToken(tx: transaction),
                let localRecipient = recipientDatabaseTable.fetchRecipient(
                    serviceId: localIdentifiers.aci,
                    transaction: transaction
                ),
                let localDeviceId = tsAccountManager.storedDeviceId(tx: transaction).ifValid
            else {
                return .disallowed
            }
            let localRecipientUniqueId = localRecipient.uniqueId
            let localUserAllDeviceIds = localRecipient.deviceIds

            return .allowed(RegistrationMode.ChangeNumberParams(
                oldE164: localE164,
                oldAuthToken: authToken,
                localAci: localIdentifiers.aci,
                localAccountId: localRecipientUniqueId,
                localDeviceId: localDeviceId,
                localUserAllDeviceIds: localUserAllDeviceIds
            ))
        }
    }

    private func changePhoneNumber(_ params: RegistrationMode.ChangeNumberParams) {
        Logger.info("Attempting to start change number from settings")
        let dependencies = RegistrationCoordinatorDependencies.from(NSObject())
        let desiredMode = RegistrationMode.changingNumber(params)
        let loader = RegistrationCoordinatorLoaderImpl(dependencies: dependencies)
        let coordinator = SSKEnvironment.shared.databaseStorageRef.write {
            return loader.coordinator(
                forDesiredMode: desiredMode,
                transaction: $0
            )
        }
        let navController = RegistrationNavigationController.withCoordinator(coordinator, appReadiness: appReadiness)
        let window: UIWindow = CurrentAppContext().mainWindow!
        window.rootViewController = navController
    }

    // MARK: - PINs

    @objc
    private func arePINRemindersEnabledDidChange(_ sender: UISwitch) {
        if sender.isOn {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                SSKEnvironment.shared.ows2FAManagerRef.setAreRemindersEnabled(true, transaction: transaction)
            }
        } else {
            let pinConfirmationVC = PinConfirmationViewController(
                title: OWSLocalizedString(
                    "SETTINGS_PIN_REMINDER_DISABLE_CONFIRMATION_TITLE",
                    comment: "The title for the dialog asking user to confirm their PIN to disable reminders"
                ),
                explanation: OWSLocalizedString(
                    "SETTINGS_PIN_REMINDER_DISABLE_CONFIRMATION_EXPLANATION",
                    comment: "The explanation for the dialog asking user to confirm their PIN to disable reminders"
                ),
                actionText: OWSLocalizedString(
                    "SETTINGS_PIN_REMINDER_DISABLE_CONFIRMATION_ACTION",
                    comment: "The button text for the dialog asking user to confirm their PIN to disable reminders"
                )
            ) { [weak self] confirmed in
                guard let self = self else { return }
                if confirmed {
                    SSKEnvironment.shared.databaseStorageRef.write { transaction in
                        SSKEnvironment.shared.ows2FAManagerRef.setAreRemindersEnabled(false, transaction: transaction)
                    }

                    ExperienceUpgradeManager.dismissPINReminderIfNecessary()
                } else {
                    self.updateTableContents()
                }
            }
            present(pinConfirmationVC, animated: true)
        }
    }

    @objc
    private func isRegistrationLockV2EnabledDidChange(_ sender: UISwitch) {
        let shouldBeEnabled = sender.isOn

        guard shouldBeEnabled != SSKEnvironment.shared.ows2FAManagerRef.isRegistrationLockV2Enabled else { return }

        let actionSheet: ActionSheetController
        if shouldBeEnabled {
            actionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "SETTINGS_REGISTRATION_LOCK_TURN_ON_TITLE",
                    comment: "Title for the alert confirming that the user wants to turn on registration lock."
                ),
                message: OWSLocalizedString(
                    "SETTINGS_REGISTRATION_LOCK_TURN_ON_MESSAGE",
                    comment: "Body for the alert confirming that the user wants to turn on registration lock."
                )
            )

            let turnOnAction = ActionSheetAction(title: OWSLocalizedString(
                "SETTINGS_REGISTRATION_LOCK_TURN_ON",
                comment: "Action to turn on registration lock"
            )) { [weak self] _ in
                if SSKEnvironment.shared.ows2FAManagerRef.is2FAEnabled {
                    Task {
                        do {
                            try await SSKEnvironment.shared.ows2FAManagerRef.enableRegistrationLockV2()
                            self?.updateTableContents()
                        } catch {
                            owsFailDebug("Error enabling reglock \(error)")
                        }
                    }
                } else {
                    self?.showCreatePin(enableRegistrationLock: true)
                }
            }
            actionSheet.addAction(turnOnAction)
        } else {
            actionSheet = ActionSheetController(title: OWSLocalizedString(
                "SETTINGS_REGISTRATION_LOCK_TURN_OFF_TITLE",
                comment: "Title for the alert confirming that the user wants to turn off registration lock."
            ))

            let turnOffAction = ActionSheetAction(
                title: OWSLocalizedString(
                    "SETTINGS_REGISTRATION_LOCK_TURN_OFF",
                    comment: "Action to turn off registration lock"
                ),
                style: .destructive
            ) { [weak self] _ in
                Task {
                    do {
                        try await SSKEnvironment.shared.ows2FAManagerRef.disableRegistrationLockV2()
                        self?.updateTableContents()
                    } catch {
                        owsFailDebug("Failed to disable reglock \(error)")
                    }
                }
            }
            actionSheet.addAction(turnOffAction)
        }

        let cancelAction = ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel
        ) { _ in
            sender.setOn(!shouldBeEnabled, animated: true)
        }
        actionSheet.addAction(cancelAction)

        presentActionSheet(actionSheet)
    }

    public func showCreateOrChangePin() {
        if SSKEnvironment.shared.ows2FAManagerRef.is2FAEnabled {
            showChangePin()
        } else {
            showCreatePin()
        }
    }

    private func showChangePin() {
        let vc = PinSetupViewController(mode: .changing, hideNavigationBar: false) { [weak self] _, _ in
            guard let self = self else { return }
            self.navigationController?.popToViewController(self, animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showCreatePin(enableRegistrationLock: Bool = false) {
        let vc = PinSetupViewController(
            mode: .creating,
            hideNavigationBar: false,
            enableRegistrationLock: enableRegistrationLock
        ) { [weak self] _, _ in
            guard let self = self else { return }
            self.navigationController?.popToViewController(self, animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}
