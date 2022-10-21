//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

@objc
class PrivacySettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PRIVACY_TITLE", comment: "")

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: .OWSSyncManagerConfigurationSyncDidComplete,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    @objc
    func updateTableContents() {
        let contents = OWSTableContents()

        let blockedSection = OWSTableSection()
        blockedSection.add(.disclosureItem(
            withText: NSLocalizedString(
                "SETTINGS_BLOCK_LIST_TITLE",
                comment: "Label for the block list section of the settings view"
            ),
            actionBlock: { [weak self] in
                let vc = BlockListViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        contents.addSection(blockedSection)

        let whoCanSection = OWSTableSection()

        if FeatureFlags.phoneNumberSharing {
            whoCanSection.add(.disclosureItem(
                withText: NSLocalizedString(
                    "SETTINGS_PHONE_NUMBER_SHARING",
                    comment: "Label for the 'phone number sharing' setting."
                ),
                detailText: PhoneNumberSharingSettingsTableViewController.nameForCurrentMode,
                actionBlock: { [weak self] in
                    let vc = PhoneNumberSharingSettingsTableViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            ))
        }

        if FeatureFlags.phoneNumberDiscoverability, tsAccountManager.isPrimaryDevice {
            whoCanSection.add(.disclosureItem(
                withText: NSLocalizedString(
                    "SETTINGS_PHONE_NUMBER_DISCOVERABILITY",
                    comment: "Label for the 'phone number discoverability' setting."
                ),
                detailText: PhoneNumberDiscoverabilitySettingsTableViewController.nameForCurrentDiscoverability,
                actionBlock: { [weak self] in
                    let vc = PhoneNumberDiscoverabilitySettingsTableViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            ))
        }

        if !whoCanSection.items.isEmpty {
            contents.addSection(whoCanSection)
        }

        let messagingSection = OWSTableSection()
        messagingSection.footerTitle = NSLocalizedString(
            "SETTINGS_MESSAGING_FOOTER",
            comment: "Explanation for the 'messaging' privacy settings."
        )
        messagingSection.add(.switch(
            withText: NSLocalizedString(
                "SETTINGS_READ_RECEIPT",
                comment: "Label for the 'read receipts' setting."
            ),
            isOn: { Self.receiptManager.areReadReceiptsEnabled() },
            target: self,
            selector: #selector(didToggleReadReceiptsSwitch)
        ))
        messagingSection.add(.switch(
            withText: NSLocalizedString(
                "SETTINGS_TYPING_INDICATORS",
                comment: "Label for the 'typing indicators' setting."
            ),
            isOn: { Self.typingIndicatorsImpl.areTypingIndicatorsEnabled() },
            target: self,
            selector: #selector(didToggleTypingIndicatorsSwitch)
        ))
        contents.addSection(messagingSection)

        let disappearingMessagesSection = OWSTableSection()
        disappearingMessagesSection.footerTitle = NSLocalizedString(
            "SETTINGS_DISAPPEARING_MESSAGES_FOOTER",
            comment: "Explanation for the 'disappearing messages' privacy settings."
        )
        let disappearingMessagesConfiguration = databaseStorage.read { transaction in
            OWSDisappearingMessagesConfiguration.fetchOrBuildDefaultUniversalConfiguration(with: transaction)
        }
        disappearingMessagesSection.add(.init(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let cell = OWSTableItem.buildIconNameCell(
                    itemName: NSLocalizedString(
                        "SETTINGS_DISAPPEARING_MESSAGES",
                        comment: "Label for the 'disappearing messages' privacy settings."
                    ),
                    accessoryText: disappearingMessagesConfiguration.isEnabled
                    ? NSString.formatDurationSeconds(disappearingMessagesConfiguration.durationSeconds, useShortFormat: true)
                    : CommonStrings.switchOff,
                    accessoryType: .disclosureIndicator,
                    accessoryImage: nil,
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "disappearing_messages")
                )
                return cell
            }, actionBlock: { [weak self] in
                let vc = DisappearingMessagesTimerSettingsViewController(configuration: disappearingMessagesConfiguration, isUniversal: true) { configuration in
                    self?.databaseStorage.write { transaction in
                        configuration.anyUpsert(transaction: transaction)
                    }
                    self?.storageServiceManager.recordPendingLocalAccountUpdates()
                    self?.updateTableContents()
                }
                self?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            }
        ))
        contents.addSection(disappearingMessagesSection)

        let appSecuritySection = OWSTableSection()
        appSecuritySection.headerTitle = NSLocalizedString("SETTINGS_SECURITY_TITLE", comment: "Section header")

        switch OWSScreenLock.shared.biometryType {
        case .unknown:
            appSecuritySection.footerTitle = NSLocalizedString("SETTINGS_SECURITY_DETAIL", comment: "Section footer")
        case .passcode:
            appSecuritySection.footerTitle = NSLocalizedString("SETTINGS_SECURITY_DETAIL_PASSCODE", comment: "Section footer")
        case .faceId:
            appSecuritySection.footerTitle = NSLocalizedString("SETTINGS_SECURITY_DETAIL_FACEID", comment: "Section footer")
        case .touchId:
            appSecuritySection.footerTitle = NSLocalizedString("SETTINGS_SECURITY_DETAIL_TOUCHID", comment: "Section footer")
        }

        appSecuritySection.add(.switch(
            withText: NSLocalizedString("SETTINGS_SCREEN_SECURITY", comment: ""),
            isOn: { Self.preferences.screenSecurityIsEnabled() },
            target: self,
            selector: #selector(didToggleScreenSecuritySwitch)
        ))
        appSecuritySection.add(.switch(
            withText: NSLocalizedString(
                "SETTINGS_SCREEN_LOCK_SWITCH_LABEL",
                comment: "Label for the 'enable screen lock' switch of the privacy settings."
            ),
            isOn: { OWSScreenLock.shared.isScreenLockEnabled() },
            target: self,
            selector: #selector(didToggleScreenLockSwitch)
        ))
        if OWSScreenLock.shared.isScreenLockEnabled() {
            appSecuritySection.add(.disclosureItem(
                withText: NSLocalizedString(
                    "SETTINGS_SCREEN_LOCK_ACTIVITY_TIMEOUT",
                    comment: "Label for the 'screen lock activity timeout' setting of the privacy settings."
                ),
                detailText: formatScreenLockTimeout(OWSScreenLock.shared.screenLockTimeout()),
                actionBlock: { [weak self] in
                    self?.showScreenLockTimeoutPicker()
                }
            ))
        }
        contents.addSection(appSecuritySection)

        if !CallUIAdapter.isCallkitDisabledForLocale {
            let callsSection = OWSTableSection()
            callsSection.headerTitle = NSLocalizedString(
                "SETTINGS_SECTION_TITLE_CALLING",
                comment: "settings topic header for table section"
            )
            callsSection.footerTitle = NSLocalizedString(
                "SETTINGS_SECTION_FOOTER_CALLING",
                comment: "Footer for table section"
            )
            callsSection.add(.switch(
                withText: NSLocalizedString(
                    "SETTINGS_PRIVACY_CALLKIT_SYSTEM_CALL_LOG_PREFERENCE_TITLE",
                    comment: "Short table cell label"
                ),
                isOn: { Self.preferences.isSystemCallLogEnabled() },
                target: self,
                selector: #selector(didToggleEnableSystemCallLogSwitch)
            ))
            contents.addSection(callsSection)
        }

        let advancedSection = OWSTableSection()
        advancedSection.footerTitle = NSLocalizedString(
            "SETTINGS_PRIVACY_ADVANCED_FOOTER",
            comment: "Footer for table section"
        )
        advancedSection.add(.disclosureItem(
            withText: NSLocalizedString(
                "SETTINGS_PRIVACY_ADVANCED_TITLE",
                comment: "Title for the advanced privacy settings"
            ),
            actionBlock: { [weak self] in
                let vc = AdvancedPrivacySettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        contents.addSection(advancedSection)

        self.contents = contents
    }

    @objc
    func didToggleReadReceiptsSwitch(_ sender: UISwitch) {
        receiptManager.setAreReadReceiptsEnabledWithSneakyTransactionAndSyncConfiguration(sender.isOn)
    }

    @objc
    func didToggleTypingIndicatorsSwitch(_ sender: UISwitch) {
        typingIndicatorsImpl.setTypingIndicatorsEnabledAndSendSyncMessage(value: sender.isOn)
    }

    @objc
    func didToggleScreenSecuritySwitch(_ sender: UISwitch) {
        preferences.setScreenSecurity(sender.isOn)
    }

    @objc
    func didToggleScreenLockSwitch(_ sender: UISwitch) {
        OWSScreenLock.shared.setIsScreenLockEnabled(sender.isOn)
        updateTableContents()
    }

    private func showScreenLockTimeoutPicker() {
        let actionSheet = ActionSheetController(title: NSLocalizedString(
            "SETTINGS_SCREEN_LOCK_ACTIVITY_TIMEOUT",
            comment: "Label for the 'screen lock activity timeout' setting of the privacy settings."
        ))

        for timeout in OWSScreenLock.shared.screenLockTimeouts {
            actionSheet.addAction(.init(
                title: formatScreenLockTimeout(timeout, useShortFormat: false),
                handler: { [weak self] _ in
                    OWSScreenLock.shared.setScreenLockTimeout(timeout)
                    self?.updateTableContents()
                }
            ))
        }

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func formatScreenLockTimeout(_ value: TimeInterval, useShortFormat: Bool = true) -> String {
        guard value > 0 else {
            return NSLocalizedString(
                "SCREEN_LOCK_ACTIVITY_TIMEOUT_NONE",
                comment: "Indicates a delay of zero seconds, and that 'screen lock activity' will timeout immediately."
            )
        }
        return NSString.formatDurationSeconds(UInt32(value), useShortFormat: useShortFormat)
    }

    @objc
    func didToggleEnableSystemCallLogSwitch(_ sender: UISwitch) {
        preferences.setIsSystemCallLogEnabled(sender.isOn)

        // rebuild callUIAdapter since CallKit configuration changed.
        Self.callService.createCallUIAdapter()
    }
}
