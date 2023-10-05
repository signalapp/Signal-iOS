//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PhoneNumberPrivacySettingsViewController: OWSTableViewController2 {

    private var sharingFeatureEnabled: Bool = false
    private var discoverabilityFeatureEnabled: Bool = false
    private var phoneNumberSharingMode: PhoneNumberSharingMode = .nobody

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        sharingFeatureEnabled = FeatureFlags.phoneNumberSharing
        discoverabilityFeatureEnabled = FeatureFlags.phoneNumberDiscoverability
            && (DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice ?? true)
        phoneNumberSharingMode = databaseStorage.read { tx in udManager.phoneNumberSharingMode(tx: tx) }
        title = OWSLocalizedString(
            "SETTINGS_PHONE_NUMBER_PRIVACY_TITLE",
            comment: "The title for phone number privacy settings.")
        updateTableContents()
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    // MARK: Build Table

    private func updateTableContents() {
        let contents = OWSTableContents()

        var sections = [OWSTableSection]()
        if sharingFeatureEnabled {
            let seeMyNumberSection = OWSTableSection()
            seeMyNumberSection.headerTitle = OWSLocalizedString(
                "SETTINGS_PHONE_NUMBER_SHARING_TITLE",
                comment: "The title for the phone number sharing setting section.")
            seeMyNumberSection.footerTitle = descriptionForCurrentPhoneNumberSharingMode
            seeMyNumberSection.add(sharingItem(.everybody))
            seeMyNumberSection.add(sharingItem(.nobody))
            sections.append(seeMyNumberSection)
        }

        if discoverabilityFeatureEnabled {
            let findByNumberSection = OWSTableSection()
            findByNumberSection.headerTitle = OWSLocalizedString(
                "SETTINGS_PHONE_NUMBER_DISCOVERABILITY_TITLE",
                comment: "The title for the phone number discoverability setting section.")
            findByNumberSection.footerTitle = Self.descriptionForCurrentDiscoverability
            findByNumberSection.add(discoverabilityItem(true))

            if sharingFeatureEnabled, phoneNumberSharingMode != .everybody {
                // By design, only include the 'nobody' option if
                // phone number sharing is disabled.
                findByNumberSection.add(discoverabilityItem(false))
            }

            sections.append(findByNumberSection)
        }
        contents.add(sections: sections)

        self.contents = contents
    }

    // MARK: Update Setting Values

    private func discoverabilityItem(_ isDiscoverable: Bool) -> OWSTableItem {
        let currentlyIsDiscoverable = DependenciesBridge.shared.db.read(
            block: DependenciesBridge.shared.tsAccountManager.isDiscoverableByPhoneNumber(tx:)
        )
        return OWSTableItem(
            text: PhoneNumberDiscoverability.nameForDiscoverability(isDiscoverable),
            actionBlock: { [weak self] in
                self?.updateDiscoverability(isDiscoverable)
            },
            accessoryType: currentlyIsDiscoverable == isDiscoverable ? .checkmark : .none
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

    private func updateDiscoverability(_ isDiscoverable: Bool) {
        let currentlyIsDiscoverable = DependenciesBridge.shared.db.read(
            block: DependenciesBridge.shared.tsAccountManager.isDiscoverableByPhoneNumber(tx:)
        )
        guard currentlyIsDiscoverable != isDiscoverable else { return }

        databaseStorage.asyncWrite(block: { transaction in
            DependenciesBridge.shared.phoneNumberDiscoverabilityManager.setIsDiscoverableByPhoneNumber(
                isDiscoverable,
                updateStorageService: true,
                authedAccount: .implicit(),
                tx: transaction.asV2Write
            )
        }) { [weak self] in
            self?.updateTableContents()
        }
    }

    private func updatePhoneNumberSharing(_ mode: PhoneNumberSharingMode) {
        guard phoneNumberSharingMode != mode else { return }

        databaseStorage.asyncWrite(block: { [weak self] transaction in
            self?.udManager.setPhoneNumberSharingMode(mode, updateStorageService: true, tx: transaction)

            // If sharing is set to `everybody`, discovery needs to be
            // updated to match this.
            if mode == .everybody {
                DependenciesBridge.shared.phoneNumberDiscoverabilityManager.setIsDiscoverableByPhoneNumber(
                    true,
                    updateStorageService: true,
                    authedAccount: .implicit(),
                    tx: transaction.asV2Write
                )
            }
        }) { [weak self] in
            guard let self else { return }
            self.phoneNumberSharingMode = self.databaseStorage.read { tx in self.udManager.phoneNumberSharingMode(tx: tx) }
            self.updateTableContents()
        }
    }
}

struct PhoneNumberDiscoverability {
    static func nameForDiscoverability(_ isDiscoverable: Bool) -> String {
        if isDiscoverable {
            return OWSLocalizedString(
                "PHONE_NUMBER_DISCOVERABILITY_EVERYBODY",
                comment: "A user friendly name for the 'everybody' phone number discoverability mode.")
        } else {
            return OWSLocalizedString(
                "PHONE_NUMBER_DISCOVERABILITY_NOBODY",
                comment: "A user friendly name for the 'nobody' phone number discoverability mode.")
        }
    }

    static func descriptionForDiscoverability(_ isDiscoverable: Bool) -> String {
        if isDiscoverable {
            return OWSLocalizedString(
                "PHONE_NUMBER_DISCOVERABILITY_EVERYBODY_DESCRIPTION",
                comment: "A user friendly description of the 'everybody' phone number discoverability mode.")
        } else {
            return OWSLocalizedString(
                "PHONE_NUMBER_DISCOVERABILITY_NOBODY_DESCRIPTION",
                comment: "A user friendly description of the 'nobody' phone number discoverability mode.")
        }
    }
}

extension PhoneNumberPrivacySettingsViewController {
    fileprivate class var descriptionForCurrentDiscoverability: String {
        let isDiscoverable = DependenciesBridge.shared.db.read {
            return DependenciesBridge.shared.tsAccountManager.isDiscoverableByPhoneNumber(tx: $0)
        }
        return PhoneNumberDiscoverability.descriptionForDiscoverability(isDiscoverable)
    }

    fileprivate var descriptionForCurrentPhoneNumberSharingMode: String {
        switch phoneNumberSharingMode {
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
