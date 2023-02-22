//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI

class PhoneNumberPrivacySettingsViewController: OWSTableViewController2 {

    private var sharingFeatureEnabled: Bool = false
    private var discoverabilityFeatureEnabled: Bool = false

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        discoverabilityFeatureEnabled = FeatureFlags.phoneNumberDiscoverability && tsAccountManager.isPrimaryDevice
        sharingFeatureEnabled = FeatureFlags.phoneNumberSharing
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
            seeMyNumberSection.footerTitle = Self.descriptionForCurrentMode
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

            if
                FeatureFlags.phoneNumberSharing,
                udManager.phoneNumberSharingMode != .everybody
            {
                // By design, only include the 'nobody' option if
                // phone number sharing is disabled.
                findByNumberSection.add(discoverabilityItem(false))
            }

            sections.append(findByNumberSection)
        }
        contents.addSections(sections)

        self.contents = contents
    }

    // MARK: Update Setting Values

    private func discoverabilityItem(_ isDiscoverable: Bool) -> OWSTableItem {
        let currentlyIsDiscoverable = tsAccountManager.isDiscoverableByPhoneNumber()
        return OWSTableItem(
            text: PhoneNumberDiscoverability.nameForDiscoverability(isDiscoverable),
            actionBlock: { [weak self] in
                self?.updateDiscoverability(isDiscoverable)
            },
            accessoryType: currentlyIsDiscoverable == isDiscoverable ? .checkmark : .none
        )
    }

    private func sharingItem(_ mode: PhoneNumberSharingMode) -> OWSTableItem {
        let currentMode = udManager.phoneNumberSharingMode
        return OWSTableItem(
            text: Self.nameForMode(mode),
            actionBlock: { [weak self] in
                self?.updateSharing(mode)
            },
            accessoryType: currentMode == mode ? .checkmark : .none
        )
    }

    // MARK: Update Table UI

    private func updateDiscoverability(_ isDiscoverable: Bool) {
        guard tsAccountManager.isDiscoverableByPhoneNumber() != isDiscoverable else { return }

        databaseStorage.asyncWrite(block: { [weak self] transaction in

            self?.tsAccountManager.setIsDiscoverableByPhoneNumber(
                isDiscoverable,
                updateStorageService: true,
                transaction: transaction
            )

        }) { [weak self] in
            self?.updateTableContents()
        }
    }

    private func updateSharing(_ mode: PhoneNumberSharingMode) {
        guard udManager.phoneNumberSharingMode != mode else { return }

        databaseStorage.asyncWrite(block: { [weak self] transaction in

            self?.udManager.setPhoneNumberSharingMode(
                mode,
                updateStorageService: true,
                transaction: transaction.unwrapGrdbWrite
            )

            // If sharing is set to `everybody`, discovery needs to be
            // updated to match this.
            if mode == .everybody {
                self?.tsAccountManager.setIsDiscoverableByPhoneNumber(
                    true,
                    updateStorageService: true,
                    transaction: transaction
                )
            }

        }) { [weak self] in
            self?.updateTableContents()
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
        return PhoneNumberDiscoverability.descriptionForDiscoverability(tsAccountManager.isDiscoverableByPhoneNumber())
    }

    fileprivate class var descriptionForCurrentMode: String {
        switch udManager.phoneNumberSharingMode {
        case .everybody:
            return OWSLocalizedString(
                "PHONE_NUMBER_SHARING_EVERYBODY_DESCRIPTION",
                comment: "A user friendly description of the 'everybody' phone number sharing mode.")
        case .contactsOnly:
            return OWSLocalizedString(
                "PHONE_NUMBER_SHARING_CONTACTS_ONLY_DESCRIPTION",
                comment: "A user friendly description of the 'contacts only' phone number sharing mode.")
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
        case .contactsOnly:
            return OWSLocalizedString(
                "PHONE_NUMBER_SHARING_CONTACTS_ONLY",
                comment: "A user friendly name for the 'contacts only' phone number sharing mode.")
        case .nobody:
            return OWSLocalizedString(
                "PHONE_NUMBER_SHARING_NOBODY",
                comment: "A user friendly name for the 'nobody' phone number sharing mode.")
        }
    }
}
