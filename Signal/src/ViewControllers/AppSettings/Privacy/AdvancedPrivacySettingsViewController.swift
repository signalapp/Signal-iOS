//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class AdvancedPrivacySettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PRIVACY_ADVANCED_TITLE",
            comment: "Title for the advanced privacy settings",
        )

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: OWSChatConnection.chatConnectionStateDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: .syncManagerConfigurationSyncDidComplete,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: .isSignalProxyReadyDidChange,
            object: nil,
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    @objc
    private func updateTableContents() {
        let contents = OWSTableContents()

        let censorshipCircumventionSection = OWSTableSection()
        let isCensorshipCircumventionSwitchEnabled: Bool

        if SSKEnvironment.shared.signalServiceRef.hasCensoredPhoneNumber {
            isCensorshipCircumventionSwitchEnabled = true
            if SSKEnvironment.shared.signalServiceRef.isCensorshipCircumventionManuallyDisabled {
                censorshipCircumventionSection.footerTitle = OWSLocalizedString(
                    "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_MANUALLY_DISABLED",
                    comment: "Table footer for the 'censorship circumvention' section shown when censorship circumvention has been manually disabled.",
                )
            } else {
                censorshipCircumventionSection.footerTitle = OWSLocalizedString(
                    "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_AUTO_ENABLED",
                    comment: "Table footer for the 'censorship circumvention' section shown when censorship circumvention has been auto-enabled based on local phone number.",
                )
            }
        } else if
            !SSKEnvironment.shared.signalServiceRef.isCensorshipCircumventionActive,
            DependenciesBridge.shared.chatConnectionManager.unidentifiedConnectionState == .open
        {
            isCensorshipCircumventionSwitchEnabled = false
            censorshipCircumventionSection.footerTitle = OWSLocalizedString(
                "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_WEBSOCKET_CONNECTED",
                comment: "Table footer for the 'censorship circumvention' section shown when the app is connected to the Signal service.",
            )
        } else if !SSKEnvironment.shared.signalServiceRef.isCensorshipCircumventionActive, !SSKEnvironment.shared.reachabilityManagerRef.isReachable {
            isCensorshipCircumventionSwitchEnabled = false
            censorshipCircumventionSection.footerTitle = OWSLocalizedString(
                "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_NO_CONNECTION",
                comment: "Table footer for the 'censorship circumvention' section shown when the app is not connected to the internet.",
            )
        } else {
            isCensorshipCircumventionSwitchEnabled = true
            censorshipCircumventionSection.footerTitle = OWSLocalizedString(
                "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER",
                comment: "Table footer for the 'censorship circumvention' section when censorship circumvention can be manually enabled.",
            )
        }

        censorshipCircumventionSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION",
                comment: "Label for the 'manual censorship circumvention' switch.",
            ),
            isOn: { SSKEnvironment.shared.signalServiceRef.isCensorshipCircumventionActive },
            isEnabled: { isCensorshipCircumventionSwitchEnabled || DebugFlags.exposeCensorshipCircumvention },
            target: self,
            selector: #selector(didToggleEnableCensorshipCircumventionSwitch),
        ))

        if SSKEnvironment.shared.signalServiceRef.isCensorshipCircumventionManuallyActivated {
            censorshipCircumventionSection.add(.disclosureItem(
                withText: OWSLocalizedString(
                    "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_COUNTRY",
                    comment: "Label for the 'manual censorship circumvention' country.",
                ),
                accessoryText: ensureManualCensorshipCircumventionCountry().localizedCountryName,
                actionBlock: { [weak self] in
                    let vc = DomainFrontingCountryViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                },
            ))
        }

        contents.add(censorshipCircumventionSection)

        let proxySection = OWSTableSection()
        proxySection.footerAttributedTitle = .composed(of: [
            OWSLocalizedString("USE_PROXY_EXPLANATION", comment: "Explanation of when you should use a signal proxy"),
            " ",
            CommonStrings.learnMore.styled(with: .link(URL.Support.proxies)),
        ])
        .styled(with: defaultFooterTextStyle)

        proxySection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "PROXY_SETTINGS_TITLE",
                comment: "Title for the signal proxy settings",
            ),
            accessoryText: SignalProxy.isEnabled ? CommonStrings.switchOn : CommonStrings.switchOff,
            actionBlock: { [weak self] in
                let vc = ProxySettingsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            },
        ))
        contents.add(proxySection)

        let relayCallsSection = OWSTableSection()
        relayCallsSection.footerTitle = OWSLocalizedString(
            "SETTINGS_CALLING_HIDES_IP_ADDRESS_PREFERENCE_TITLE_DETAIL",
            comment: "User settings section footer, a detailed explanation",
        )
        relayCallsSection.add(.switch(
            withText: OWSLocalizedString(
                "SETTINGS_CALLING_HIDES_IP_ADDRESS_PREFERENCE_TITLE",
                comment: "Table cell label",
            ),
            isOn: { SSKEnvironment.shared.preferencesRef.doCallsHideIPAddress },
            target: self,
            selector: #selector(didToggleCallsHideIPAddressSwitch),
        ))
        contents.add(relayCallsSection)

        if BuildFlags.KeyTransparency.enabled {
            let keyTransparencySection = OWSTableSection()

            keyTransparencySection.add(.switch(
                withText: OWSLocalizedString(
                    "SETTINGS_KEY_TRANSPARENCY_OPT_OUT_SWITCH_TITLE",
                    comment: "Title for for a settings option describing that Key Transparency is enabled.",
                ),
                isOn: {
                    let db = DependenciesBridge.shared.db
                    let keyTransparencyManager = DependenciesBridge.shared.keyTransparencyManager
                    return db.read { tx in
                        keyTransparencyManager.isEnabled(tx: tx)
                    }
                },
                actionBlock: { uiSwitch in
                    let db = DependenciesBridge.shared.db
                    let keyTransparencyManager = DependenciesBridge.shared.keyTransparencyManager
                    db.write { tx in
                        keyTransparencyManager.setIsEnabled(
                            uiSwitch.isOn,
                            updateStorageService: true,
                            tx: tx,
                        )
                    }
                },
            ))
            keyTransparencySection.footerAttributedTitle = NSAttributedString.composed(of: [
                OWSLocalizedString(
                    "SETTINGS_KEY_TRANSPARENCY_OPT_OUT_FOOTER",
                    comment: "Footer for settings section describing Key Transparency.",
                ),
                " ",
                CommonStrings.learnMore.styled(with: .link(URL.Support.keyTransparency)),
            ]).styled(with: defaultFooterTextStyle)

            contents.add(keyTransparencySection)
        }

        let sealedSenderSection = OWSTableSection()
        sealedSenderSection.headerTitle = OWSLocalizedString(
            "SETTINGS_UNIDENTIFIED_DELIVERY_SECTION_TITLE",
            comment: "table section label",
        )
        sealedSenderSection.add(.init(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                guard let self else { return cell }
                cell.selectionStyle = .none

                let stackView = UIStackView()
                stackView.axis = .horizontal
                stackView.spacing = 8
                cell.contentView.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewMargins()

                let nameLabel = UILabel()
                nameLabel.text = OWSLocalizedString("SETTINGS_UNIDENTIFIED_DELIVERY_SHOW_INDICATORS", comment: "switch label")
                nameLabel.textColor = Theme.primaryTextColor
                nameLabel.font = OWSTableItem.primaryLabelFont
                nameLabel.adjustsFontForContentSizeCategory = true
                nameLabel.numberOfLines = 0
                nameLabel.lineBreakMode = .byWordWrapping
                nameLabel.setCompressionResistanceHorizontalHigh()
                nameLabel.setContentHuggingHorizontalHigh()
                stackView.addArrangedSubview(nameLabel)

                let imageView = UIImageView()
                imageView.contentMode = .center
                imageView.setTemplateImageName(Theme.iconName(.sealedSenderIndicator), tintColor: Theme.primaryTextColor)
                imageView.autoSetDimension(.width, toSize: 20)
                stackView.addArrangedSubview(imageView)

                stackView.addArrangedSubview(.hStretchingSpacer())

                // Leave space for the switch.
                stackView.addArrangedSubview(.spacer(withWidth: 60))

                let cellSwitch = UISwitch()
                cellSwitch.isOn = SSKEnvironment.shared.preferencesRef.shouldShowUnidentifiedDeliveryIndicators
                cellSwitch.addTarget(self, action: #selector(self.didToggleUDShowIndicatorsSwitch), for: .valueChanged)
                cell.accessoryView = cellSwitch

                return cell
            },
            actionBlock: {

            },
        ))

        if DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice {
            sealedSenderSection.add(.switch(
                withText: OWSLocalizedString(
                    "SETTINGS_UNIDENTIFIED_DELIVERY_UNRESTRICTED_ACCESS",
                    comment: "switch label",
                ),
                isOn: { SSKEnvironment.shared.udManagerRef.shouldAllowUnrestrictedAccessLocal() },
                target: self,
                selector: #selector(didToggleUDUnrestrictedAccessSwitch),
            ))
            sealedSenderSection.footerAttributedTitle = NSAttributedString.composed(of: [
                OWSLocalizedString(
                    "SETTINGS_UNIDENTIFIED_DELIVERY_UNRESTRICTED_ACCESS_FOOTER",
                    comment: "table section footer",
                ),
                " ",
                CommonStrings.learnMore.styled(
                    with: .link(URL(string: "https://signal.org/blog/sealed-sender/")!),
                ),
            ])
            .styled(with: defaultFooterTextStyle)

        }

        contents.add(sealedSenderSection)

        self.contents = contents
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    @objc
    private func didToggleEnableCensorshipCircumventionSwitch(_ sender: UISwitch) {
        SSKEnvironment.shared.signalServiceRef.isCensorshipCircumventionManuallyDisabled = !sender.isOn
        SSKEnvironment.shared.signalServiceRef.isCensorshipCircumventionManuallyActivated = sender.isOn
        updateTableContents()
    }

    private func ensureManualCensorshipCircumventionCountry() -> OWSCountryMetadata {
        let preferredCountryCode = SSKEnvironment.shared.signalServiceRef.manualCensorshipCircumventionCountryCode ?? Locale.current.regionCode

        if
            let preferredCountryCode,
            let countryMetadata = OWSCountryMetadata.countryMetadata(countryCode: preferredCountryCode)
        {
            SSKEnvironment.shared.signalServiceRef.manualCensorshipCircumventionCountryCode = preferredCountryCode
            return countryMetadata
        } else {
            let fallbackCountryCode = "US"
            SSKEnvironment.shared.signalServiceRef.manualCensorshipCircumventionCountryCode = fallbackCountryCode
            return OWSCountryMetadata.countryMetadata(countryCode: fallbackCountryCode)!
        }
    }

    @objc
    private func didToggleCallsHideIPAddressSwitch(_ sender: UISwitch) {
        SSKEnvironment.shared.preferencesRef.setDoCallsHideIPAddress(sender.isOn)
    }

    @objc
    private func didToggleUDShowIndicatorsSwitch(_ sender: UISwitch) {
        SSKEnvironment.shared.preferencesRef.setShouldShowUnidentifiedDeliveryIndicatorsAndSendSyncMessage(sender.isOn)
    }

    @objc
    private func didToggleUDUnrestrictedAccessSwitch(_ sender: UISwitch) {
        SSKEnvironment.shared.udManagerRef.setShouldAllowUnrestrictedAccessLocal(sender.isOn)
    }
}
