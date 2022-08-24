//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class AdvancedPrivacySettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString(
            "SETTINGS_PRIVACY_ADVANCED_TITLE",
            comment: "Title for the advanced privacy settings"
        )

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: OWSWebSocket.webSocketStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil
        )
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

        // Censorship circumvention has certain disadvantages so it should only be
        // used if necessary.  Therefore:
        //
        // * We disable this setting if the user has a phone number from a censored region -
        //   censorship circumvention will be auto-activated for this user.
        // * We disable this setting if the user is already connected; they're not being
        //   censored.
        // * We continue to show this setting so long as it is set to allow users to disable
        //   it, for example when they leave a censored region.
        let censorshipCircumventionSection = OWSTableSection()

        let isAnySocketOpen = socketManager.isAnySocketOpen
        if self.signalService.hasCensoredPhoneNumber {
            if self.signalService.isCensorshipCircumventionManuallyDisabled {
                censorshipCircumventionSection.footerTitle = NSLocalizedString(
                    "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_MANUALLY_DISABLED",
                    comment: "Table footer for the 'censorship circumvention' section shown when censorship circumvention has been manually disabled."
                )
            } else {
                censorshipCircumventionSection.footerTitle = NSLocalizedString(
                    "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_AUTO_ENABLED",
                    comment: "Table footer for the 'censorship circumvention' section shown when censorship circumvention has been auto-enabled based on local phone number."
                )
            }
        } else if isAnySocketOpen {
            censorshipCircumventionSection.footerTitle = NSLocalizedString(
                "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_WEBSOCKET_CONNECTED",
                comment: "Table footer for the 'censorship circumvention' section shown when the app is connected to the Signal service."
            )
        } else if !reachabilityManager.isReachable {
            censorshipCircumventionSection.footerTitle = NSLocalizedString(
                "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER_NO_CONNECTION",
                comment: "Table footer for the 'censorship circumvention' section shown when the app is not connected to the internet."
            )
        } else {
            censorshipCircumventionSection.footerTitle = NSLocalizedString(
                "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_FOOTER",
                comment: "Table footer for the 'censorship circumvention' section when censorship circumvention can be manually enabled."
            )
        }

        censorshipCircumventionSection.add(.switch(
            withText: NSLocalizedString(
                "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION",
                comment: "Label for the  'manual censorship circumvention' switch."
            ),
            isOn: { self.signalService.isCensorshipCircumventionActive },
            isEnabledBlock: {
                // Do enable if :
                //
                // * ...Censorship circumvention is already manually enabled (to allow users to disable it).
                //
                // Otherwise, don't enable if:
                //
                // * ...Censorship circumvention is already enabled based on the local phone number.
                // * ...The websocket is connected, since that demonstrates that no censorship is in effect.
                // * ...The internet is not reachable, since we don't want to let users to activate
                //      censorship circumvention unnecessarily, e.g. if they just don't have a valid
                //      internet connection.
                if DebugFlags.exposeCensorshipCircumvention {
                    return true
                } else if self.signalService.isCensorshipCircumventionActive {
                    return true
                } else if self.signalService.hasCensoredPhoneNumber,
                          self.signalService.isCensorshipCircumventionManuallyDisabled {
                    return true
                } else if Self.socketManager.isAnySocketOpen {
                    return false
                } else {
                    return Self.reachabilityManager.isReachable
                }
            },
            target: self,
            selector: #selector(didToggleEnableCensorshipCircumventionSwitch)
        ))

        if self.signalService.isCensorshipCircumventionManuallyActivated {
            censorshipCircumventionSection.add(.disclosureItem(
                withText: NSLocalizedString(
                    "SETTINGS_ADVANCED_CENSORSHIP_CIRCUMVENTION_COUNTRY",
                    comment: "Label for the 'manual censorship circumvention' country."
                ),
                detailText: ensureManualCensorshipCircumventionCountry().localizedCountryName,
                actionBlock: { [weak self] in
                    let vc = DomainFrontingCountryViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            ))
        }

        contents.addSection(censorshipCircumventionSection)

        let relayCallsSection = OWSTableSection()
        relayCallsSection.footerTitle = NSLocalizedString(
            "SETTINGS_CALLING_HIDES_IP_ADDRESS_PREFERENCE_TITLE_DETAIL",
            comment: "User settings section footer, a detailed explanation"
        )
        relayCallsSection.add(.switch(
            withText: NSLocalizedString(
                "SETTINGS_CALLING_HIDES_IP_ADDRESS_PREFERENCE_TITLE",
                comment: "Table cell label"
            ),
            isOn: { Self.preferences.doCallsHideIPAddress() },
            target: self,
            selector: #selector(didToggleCallsHideIPAddressSwitch)
        ))
        contents.addSection(relayCallsSection)

        let sealedSenderSection = OWSTableSection()
        sealedSenderSection.headerTitle = NSLocalizedString(
            "SETTINGS_UNIDENTIFIED_DELIVERY_SECTION_TITLE",
            comment: "table section label"
        )
        sealedSenderSection.footerAttributedTitle = NSAttributedString.composed(of: [
            NSLocalizedString(
                "SETTINGS_UNIDENTIFIED_DELIVERY_UNRESTRICTED_ACCESS_FOOTER",
                comment: "table section footer"
            ),
            " ",
            CommonStrings.learnMore.styled(
                with: .link(URL(string: "https://signal.org/blog/sealed-sender/")!)
            )
        ]).styled(
            with: .font(.ows_dynamicTypeCaption1Clamped),
            .color(Theme.secondaryTextAndIconColor)
        )
        sealedSenderSection.add(.init(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                guard let self = self else { return cell }
                cell.selectionStyle = .none

                let stackView = UIStackView()
                stackView.axis = .horizontal
                stackView.spacing = 8
                cell.contentView.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewMargins()

                let nameLabel = UILabel()
                nameLabel.text = NSLocalizedString("SETTINGS_UNIDENTIFIED_DELIVERY_SHOW_INDICATORS", comment: "switch label")
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
                cellSwitch.isOn = Self.preferences.shouldShowUnidentifiedDeliveryIndicators()
                cellSwitch.addTarget(self, action: #selector(self.didToggleUDShowIndicatorsSwitch), for: .valueChanged)
                cell.accessoryView = cellSwitch

                return cell
            },
            actionBlock: {

            }
        ))

        if tsAccountManager.isRegisteredPrimaryDevice {
            sealedSenderSection.add(.switch(
                withText: NSLocalizedString(
                    "SETTINGS_UNIDENTIFIED_DELIVERY_UNRESTRICTED_ACCESS",
                    comment: "switch label"
                ),
                isOn: { Self.udManager.shouldAllowUnrestrictedAccessLocal() },
                target: self,
                selector: #selector(didToggleUDUnrestrictedAccessSwitch)
            ))
        }

        contents.addSection(sealedSenderSection)

        self.contents = contents
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    @objc
    func didToggleEnableCensorshipCircumventionSwitch(_ sender: UISwitch) {
        self.signalService.isCensorshipCircumventionManuallyDisabled = !sender.isOn
        self.signalService.isCensorshipCircumventionManuallyActivated = sender.isOn
        updateTableContents()
    }

    private func ensureManualCensorshipCircumventionCountry() -> OWSCountryMetadata {
        let countryCode = self.signalService.manualCensorshipCircumventionCountryCode ?? PhoneNumber.defaultCountryCode()
        self.signalService.manualCensorshipCircumventionCountryCode = countryCode
        return OWSCountryMetadata(forCountryCode: countryCode)
    }

    @objc
    func didToggleCallsHideIPAddressSwitch(_ sender: UISwitch) {
        preferences.setDoCallsHideIPAddress(sender.isOn)
    }

    @objc
    func didToggleUDShowIndicatorsSwitch(_ sender: UISwitch) {
        preferences.setShouldShowUnidentifiedDeliveryIndicatorsAndSendSyncMessage(sender.isOn)
    }

    @objc
    func didToggleUDUnrestrictedAccessSwitch(_ sender: UISwitch) {
        udManager.setShouldAllowUnrestrictedAccessLocal(sender.isOn)
    }
}
