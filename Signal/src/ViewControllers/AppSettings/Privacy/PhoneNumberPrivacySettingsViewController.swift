//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PhoneNumberPrivacySettingsViewController: OWSTableViewController2 {

    private var phoneNumberDiscoverability: PhoneNumberDiscoverability!
    private var phoneNumberSharingMode: PhoneNumberSharingMode!

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        loadValues()
        title = OWSLocalizedString(
            "SETTINGS_PHONE_NUMBER_PRIVACY_TITLE",
            comment: "The title for phone number privacy settings.")
        updateTableContents()
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    private func loadValues() {
        databaseStorage.read { tx in
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            phoneNumberDiscoverability = tsAccountManager.phoneNumberDiscoverability(tx: tx.asV2Read).orDefault
            phoneNumberSharingMode = udManager.phoneNumberSharingMode(tx: tx.asV2Read).orDefault
        }
    }

    // MARK: Build Table

    private func updateTableContents() {
        let contents = OWSTableContents()
        var sections = [OWSTableSection]()

        let seeMyNumberSection = OWSTableSection()
        seeMyNumberSection.headerTitle = OWSLocalizedString(
            "SETTINGS_PHONE_NUMBER_SHARING_TITLE",
            comment: "The title for the phone number sharing setting section."
        )
        seeMyNumberSection.footerTitle = descriptionForCurrentPhoneNumberSharingMode
        seeMyNumberSection.add(sharingItem(.everybody))
        seeMyNumberSection.add(sharingItem(.nobody))
        sections.append(seeMyNumberSection)

        let findByNumberSection = OWSTableSection()
        findByNumberSection.headerTitle = OWSLocalizedString(
            "SETTINGS_PHONE_NUMBER_DISCOVERABILITY_TITLE",
            comment: "The title for the phone number discoverability setting section."
        )
        findByNumberSection.footerTitle = phoneNumberDiscoverability.descriptionForDiscoverability
        findByNumberSection.add(discoverabilityItem(.everybody))

        switch phoneNumberSharingMode! {
        case .everybody:
            // Create disabled "nobody" option
            findByNumberSection.add(OWSTableItem(
                text: PhoneNumberDiscoverability.nobody.nameForDiscoverability,
                textColor: Theme.secondaryTextAndIconColor,
                actionBlock: { [weak self] in
                    self?.presentToast(text: OWSLocalizedString(
                        "SETTINGS_PHONE_NUMBER_DISCOVERABILITY_DISABLED_TOAST",
                        comment: "A toast that displays when the user attempts to set discoverability to 'nobody' when their phone number sharing is set to 'everybody', which is not allowed."
                    ))
                },
                accessoryType: .none
            ))
        case .nobody:
            findByNumberSection.add(discoverabilityItem(.nobody))
        }

        sections.append(findByNumberSection)

        contents.add(sections: sections)
        self.contents = contents
    }

    // MARK: Update Setting Values

    private func discoverabilityItem(_ phoneNumberDiscoverability: PhoneNumberDiscoverability) -> OWSTableItem {
        return OWSTableItem(
            text: phoneNumberDiscoverability.nameForDiscoverability,
            actionBlock: { [weak self] in
                self?.updateDiscoverability(phoneNumberDiscoverability)
            },
            accessoryType: self.phoneNumberDiscoverability == phoneNumberDiscoverability ? .checkmark : .none
        )
    }

    private func sharingItem(_ mode: PhoneNumberSharingMode) -> OWSTableItem {
        return OWSTableItem(
            text: Self.nameForMode(mode),
            actionBlock: { [weak self] in
                self?.updatePhoneNumberSharing(mode)
            },
            accessoryType: phoneNumberSharingMode == mode ? .checkmark : .none
        )
    }

    // MARK: Update Table UI

    private func updateDiscoverability(_ phoneNumberDiscoverability: PhoneNumberDiscoverability) {
        guard self.phoneNumberDiscoverability != phoneNumberDiscoverability else { return }

        databaseStorage.asyncWrite(block: { transaction in
            DependenciesBridge.shared.phoneNumberDiscoverabilityManager.setPhoneNumberDiscoverability(
                phoneNumberDiscoverability,
                updateAccountAttributes: true,
                updateStorageService: true,
                authedAccount: .implicit(),
                tx: transaction.asV2Write
            )
        }) { [weak self] in
            guard let self else { return }
            self.loadValues()
            self.updateTableContents()
        }
    }

    private func updatePhoneNumberSharing(_ mode: PhoneNumberSharingMode) {
        guard phoneNumberSharingMode != mode else { return }

        databaseStorage.asyncWrite(block: { [weak self] transaction in
            guard let self else { return }
            self.udManager.setPhoneNumberSharingMode(mode, updateStorageServiceAndProfile: true, tx: transaction)

            // If sharing is set to `everybody`, discovery needs to be
            // updated to match this.
            if mode == .everybody {
                DependenciesBridge.shared.phoneNumberDiscoverabilityManager.setPhoneNumberDiscoverability(
                    .everybody,
                    updateAccountAttributes: true,
                    updateStorageService: true,
                    authedAccount: .implicit(),
                    tx: transaction.asV2Write
                )
            }
        }) { [weak self] in
            guard let self else { return }
            self.loadValues()
            self.updateTableContents()
        }
    }
}

extension PhoneNumberDiscoverability {
    var nameForDiscoverability: String {
        switch self {
        case .everybody:
            return OWSLocalizedString(
                "PHONE_NUMBER_DISCOVERABILITY_EVERYBODY",
                comment: "A user friendly name for the 'everybody' phone number discoverability mode.")
        case .nobody:
            return OWSLocalizedString(
                "PHONE_NUMBER_DISCOVERABILITY_NOBODY",
                comment: "A user friendly name for the 'nobody' phone number discoverability mode.")
        }
    }

    var descriptionForDiscoverability: String {
        switch self {
        case .everybody:
            return OWSLocalizedString(
                "PHONE_NUMBER_DISCOVERABILITY_EVERYBODY_DESCRIPTION",
                comment: "A user friendly description of the 'everybody' phone number discoverability mode.")
        case .nobody:
            return OWSLocalizedString(
                "PHONE_NUMBER_DISCOVERABILITY_NOBODY_DESCRIPTION",
                comment: "A user friendly description of the 'nobody' phone number discoverability mode.")
        }
    }
}

extension PhoneNumberPrivacySettingsViewController {
    fileprivate var descriptionForCurrentPhoneNumberSharingMode: String {
        switch phoneNumberSharingMode! {
        case .everybody:
            return OWSLocalizedString(
                "PHONE_NUMBER_SHARING_EVERYBODY_DESCRIPTION",
                comment: "A user friendly description of the 'everybody' phone number sharing mode.")
        case .nobody:
            return OWSLocalizedString(
                "PHONE_NUMBER_SHARING_NOBODY_DESCRIPTION",
                comment: "A user friendly description of the 'nobody' phone number sharing mode.")
        }
    }

    fileprivate class func nameForMode(_ mode: PhoneNumberSharingMode) -> String {
        switch mode {
        case .everybody:
            return OWSLocalizedString(
                "PHONE_NUMBER_SHARING_EVERYBODY",
                comment: "A user friendly name for the 'everybody' phone number sharing mode.")
        case .nobody:
            return OWSLocalizedString(
                "PHONE_NUMBER_SHARING_NOBODY",
                comment: "A user friendly name for the 'nobody' phone number sharing mode.")
        }
    }
}
