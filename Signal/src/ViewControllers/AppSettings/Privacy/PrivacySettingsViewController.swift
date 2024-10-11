//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PrivacySettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_PRIVACY_TITLE", comment: "")

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: .syncManagerConfigurationSyncDidComplete,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    @objc
    private func updateTableContents() {
        let contents = OWSTableContents()

        let whoCanSection = OWSTableSection()

        whoCanSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_PHONE_NUMBER_PRIVACY_TITLE",
                comment: "The title for phone number privacy settings."),
            actionBlock: { [weak self] in
                let vc = PhoneNumberPrivacySettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        whoCanSection.footerTitle = OWSLocalizedString(
            "SETTINGS_PHONE_NUMBER_PRIVACY_DESCRIPTION_LABEL",
            comment: "Description label for Phone Number Privacy"
        )

        if !whoCanSection.items.isEmpty {
            contents.add(whoCanSection)
        }

        let blockedSection = OWSTableSection()
        blockedSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_BLOCK_LIST_TITLE",
                comment: "Label for the block list section of the settings view"
            ),
            actionBlock: { [weak self] in
                let vc = BlockListViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        contents.add(blockedSection)

        let messagingSection = OWSTableSection()
        messagingSection.footerTitle = OWSLocalizedString(
            "SETTINGS_MESSAGING_FOOTER",
            comment: "Explanation for the 'messaging' privacy settings."
        )
        messagingSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_READ_RECEIPT",
                comment: "Label for the 'read receipts' setting."
            ),
            isOn: { SSKEnvironment.shared.receiptManagerRef.areReadReceiptsEnabled() },
            target: self,
            selector: #selector(didToggleReadReceiptsSwitch)
        ))
        messagingSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_TYPING_INDICATORS",
                comment: "Label for the 'typing indicators' setting."
            ),
            isOn: { SSKEnvironment.shared.typingIndicatorsRef.areTypingIndicatorsEnabled() },
            target: self,
            selector: #selector(didToggleTypingIndicatorsSwitch)
        ))
        contents.add(messagingSection)

        let disappearingMessagesSection = OWSTableSection()
        disappearingMessagesSection.footerTitle = OWSLocalizedString(
            "SETTINGS_DISAPPEARING_MESSAGES_FOOTER",
            comment: "Explanation for the 'disappearing messages' privacy settings."
        )
        let disappearingMessagesConfiguration = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            return dmConfigurationStore.fetchOrBuildDefault(for: .universal, tx: tx.asV2Read)
        }
        disappearingMessagesSection.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = OWSTableItem.buildCell(
                    itemName: OWSLocalizedString(
                        "SETTINGS_DISAPPEARING_MESSAGES",
                        comment: "Label for the 'disappearing messages' privacy settings."
                    ),
                    accessoryText: disappearingMessagesConfiguration.isEnabled
                        ? DateUtil.formatDuration(seconds: disappearingMessagesConfiguration.durationSeconds, useShortFormat: true)
                        : CommonStrings.switchOff,
                    accessoryType: .disclosureIndicator,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "disappearing_messages")
                )
                return cell
            }, actionBlock: { [weak self] in
                let vc = DisappearingMessagesTimerSettingsViewController(configuration: disappearingMessagesConfiguration, isUniversal: true) { configuration in
                    if self != nil {
                        SSKEnvironment.shared.databaseStorageRef.write { transaction in
                            configuration.anyUpsert(transaction: transaction)
                        }
                        SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
                    }
                    self?.updateTableContents()
                }
                self?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))
        contents.add(disappearingMessagesSection)

        let appSecuritySection = OWSTableSection()
        appSecuritySection.headerTitle = OWSLocalizedString("SETTINGS_SECURITY_TITLE", comment: "Section header")

        switch DeviceOwnerAuthenticationType.current {
        case .unknown:
            appSecuritySection.footerTitle = OWSLocalizedString("SETTINGS_SECURITY_DETAIL", comment: "Section footer")
        case .passcode:
            appSecuritySection.footerTitle = OWSLocalizedString("SETTINGS_SECURITY_DETAIL_PASSCODE", comment: "Section footer")
        case .faceId:
            appSecuritySection.footerTitle = OWSLocalizedString("SETTINGS_SECURITY_DETAIL_FACEID", comment: "Section footer")
        case .touchId:
            appSecuritySection.footerTitle = OWSLocalizedString("SETTINGS_SECURITY_DETAIL_TOUCHID", comment: "Section footer")
        case .opticId:
            appSecuritySection.footerTitle = OWSLocalizedString("SETTINGS_SECURITY_DETAIL_OPTICID", comment: "Section footer")
        }

        appSecuritySection.add(.switch(
            withText: OWSLocalizedString("SETTINGS_SCREEN_SECURITY", comment: ""),
            isOn: { SSKEnvironment.shared.preferencesRef.isScreenSecurityEnabled },
            target: self,
            selector: #selector(didToggleScreenSecuritySwitch)
        ))
        appSecuritySection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_SCREEN_LOCK_SWITCH_LABEL",
                comment: "Label for the 'enable screen lock' switch of the privacy settings."
            ),
            isOn: { ScreenLock.shared.isScreenLockEnabled() },
            target: self,
            selector: #selector(didToggleScreenLockSwitch)
        ))
        if ScreenLock.shared.isScreenLockEnabled() {
            appSecuritySection.add(.disclosureItem(
                withText: OWSLocalizedString(
                    "SETTINGS_SCREEN_LOCK_ACTIVITY_TIMEOUT",
                    comment: "Label for the 'screen lock activity timeout' setting of the privacy settings."
                ),
                accessoryText: formatScreenLockTimeout(ScreenLock.shared.screenLockTimeout()),
                actionBlock: { [weak self] in
                    self?.showScreenLockTimeoutPicker()
                }
            ))
        }
        contents.add(appSecuritySection)

        // Payments
        let paymentsSection = OWSTableSection()
        paymentsSection.headerTitle = OWSLocalizedString("SETTINGS_PAYMENTS_SECURITY_TITLE", comment: "Title for the payments section in the app’s privacy settings tableview")

        switch DeviceOwnerAuthenticationType.current {
        case .unknown:
            paymentsSection.footerTitle = OWSLocalizedString("SETTINGS_PAYMENTS_SECURITY_DETAIL", comment: "Caption for footer label beneath the payments lock privacy toggle for a biometry type that is unknown.")
        case .passcode:
            paymentsSection.footerTitle = OWSLocalizedString("SETTINGS_PAYMENTS_SECURITY_DETAIL_PASSCODE", comment: "Caption for footer label beneath the payments lock privacy toggle for a biometry type that is a passcode.")
        case .faceId:
            paymentsSection.footerTitle = OWSLocalizedString("SETTINGS_PAYMENTS_SECURITY_DETAIL_FACEID", comment: "Caption for footer label beneath the payments lock privacy toggle for faceid biometry.")
        case .touchId:
            paymentsSection.footerTitle = OWSLocalizedString("SETTINGS_PAYMENTS_SECURITY_DETAIL_TOUCHID", comment: "Caption for footer label beneath the payments lock privacy toggle for touchid biometry")
        case .opticId:
            paymentsSection.footerTitle = OWSLocalizedString("SETTINGS_PAYMENTS_SECURITY_DETAIL_OPTICID", comment: "Caption for footer label beneath the payments lock privacy toggle for opticid biometry")
        }

        paymentsSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_PAYMENTS_LOCK_SWITCH_LABEL",
                comment: "Label for UISwitch based payments-lock setting that when enabled requires biometric-authentication (or passcode) to transfer funds or view the recovery phrase."
            ),
            isOn: { SSKEnvironment.shared.owsPaymentsLockRef.isPaymentsLockEnabled() },
            target: self,
            selector: #selector(didTogglePaymentsLockSwitch)
        ))
        contents.add(paymentsSection)

        let callsSection = OWSTableSection()
        callsSection.headerTitle = OWSLocalizedString(
            "SETTINGS_SECTION_TITLE_CALLING",
            comment: "settings topic header for table section"
        )
        callsSection.footerTitle = OWSLocalizedString(
            "SETTINGS_SECTION_FOOTER_CALLING",
            comment: "Footer for table section"
        )
        callsSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_PRIVACY_CALLKIT_SYSTEM_CALL_LOG_PREFERENCE_TITLE",
                comment: "Short table cell label"
            ),
            isOn: {
                return SSKEnvironment.shared.databaseStorageRef.read(block: SSKEnvironment.shared.preferencesRef.isSystemCallLogEnabled(tx:))
            },
            target: self,
            selector: #selector(didToggleEnableSystemCallLogSwitch)
        ))
        contents.add(callsSection)

        let advancedSection = OWSTableSection()
        advancedSection.footerTitle = OWSLocalizedString(
            "SETTINGS_PRIVACY_ADVANCED_FOOTER",
            comment: "Footer for table section"
        )
        advancedSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_PRIVACY_ADVANCED_TITLE",
                comment: "Title for the advanced privacy settings"
            ),
            actionBlock: { [weak self] in
                let vc = AdvancedPrivacySettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        contents.add(advancedSection)

        self.contents = contents
    }

    @objc
    private func didToggleReadReceiptsSwitch(_ sender: UISwitch) {
        SSKEnvironment.shared.receiptManagerRef.setAreReadReceiptsEnabledWithSneakyTransactionAndSyncConfiguration(sender.isOn)
    }

    @objc
    private func didToggleTypingIndicatorsSwitch(_ sender: UISwitch) {
        SSKEnvironment.shared.typingIndicatorsRef.setTypingIndicatorsEnabledAndSendSyncMessage(value: sender.isOn)
    }

    @objc
    private func didToggleScreenSecuritySwitch(_ sender: UISwitch) {
        SSKEnvironment.shared.preferencesRef.setIsScreenSecurityEnabled(sender.isOn)
    }

    @objc
    private func didToggleScreenLockSwitch(_ sender: UISwitch) {
        ScreenLock.shared.setIsScreenLockEnabled(sender.isOn)
        updateTableContents()
    }

    @objc
    private func didTogglePaymentsLockSwitch(_ sender: UISwitch) {
        // Require unlock to disable payments lock
        if SSKEnvironment.shared.owsPaymentsLockRef.isPaymentsLockEnabled() {
            SSKEnvironment.shared.owsPaymentsLockRef.tryToUnlock { [weak self] outcome in
                guard let self = self else { return }
                guard case .success = outcome else {
                    self.updateTableContents()
                    PaymentActionSheets.showBiometryAuthFailedActionSheet()
                    return
                }
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    SSKEnvironment.shared.owsPaymentsLockRef.setIsPaymentsLockEnabled(false, transaction: transaction)
                }
                self.updateTableContents()
            }
        } else {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                SSKEnvironment.shared.owsPaymentsLockRef.setIsPaymentsLockEnabled(true, transaction: transaction)
            }
            self.updateTableContents()
        }
    }

    private func showScreenLockTimeoutPicker() {
        let actionSheet = ActionSheetController(title: OWSLocalizedString(
            "SETTINGS_SCREEN_LOCK_ACTIVITY_TIMEOUT",
            comment: "Label for the 'screen lock activity timeout' setting of the privacy settings."
        ))

        for timeout in ScreenLock.shared.screenLockTimeouts {
            actionSheet.addAction(.init(
                title: formatScreenLockTimeout(timeout, useShortFormat: false),
                handler: { [weak self] _ in
                    ScreenLock.shared.setScreenLockTimeout(timeout)
                    self?.updateTableContents()
                }
            ))
        }

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func formatScreenLockTimeout(_ value: TimeInterval, useShortFormat: Bool = true) -> String {
        guard value > 0 else {
            return OWSLocalizedString(
                "SCREEN_LOCK_ACTIVITY_TIMEOUT_NONE",
                comment: "Indicates a delay of zero seconds, and that 'screen lock activity' will timeout immediately."
            )
        }
        return DateUtil.formatDuration(seconds: UInt32(value), useShortFormat: useShortFormat)
    }

    @objc
    private func didToggleEnableSystemCallLogSwitch(_ sender: UISwitch) {
        SSKEnvironment.shared.preferencesRef.setIsSystemCallLogEnabled(sender.isOn)

        // rebuild callUIAdapter since CallKit configuration changed.
        AppEnvironment.shared.callService.rebuildCallUIAdapter()
    }
}
