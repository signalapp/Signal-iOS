//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct PhoneNumberDiscoverability {
    static func nameForDiscoverability(_ isDiscoverable: Bool) -> String {
        if isDiscoverable {
            return NSLocalizedString("PHONE_NUMBER_DISCOVERABILITY_EVERYBODY",
                                     comment: "A user friendly name for the 'everybody' phone number discoverability mode.")
        } else {
            return NSLocalizedString("PHONE_NUMBER_DISCOVERABILITY_NOBODY",
                                     comment: "A user friendly name for the 'nobody' phone number discoverability mode.")
        }
    }

    static func descriptionForDiscoverability(_ isDiscoverable: Bool) -> String {
        if isDiscoverable {
            return NSLocalizedString("PHONE_NUMBER_DISCOVERABILITY_EVERYBODY_DESCRIPTION",
                                     comment: "A user friendly description of the 'everybody' phone number discoverability mode.")
        } else {
            return NSLocalizedString("PHONE_NUMBER_DISCOVERABILITY_NOBODY_DESCRIPTION",
            comment: "A user friendly description of the 'nobody' phone number discoverability mode.")
        }
    }
}

@objc
class PhoneNumberDiscoverabilitySettingsTableViewController: OWSTableViewController2 {

    @objc
    class var nameForCurrentDiscoverability: String {
        return PhoneNumberDiscoverability.nameForDiscoverability(tsAccountManager.isDiscoverableByPhoneNumber())
    }

    @objc
    class var descriptionForCurrentDiscoverability: String {
        return PhoneNumberDiscoverability.descriptionForDiscoverability(tsAccountManager.isDiscoverableByPhoneNumber())
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PHONE_NUMBER_DISCOVERABILITY_TITLE",
                                  comment: "The title for the phone number discoverability settings.")

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.customHeaderView = .spacer(withHeight: 32)
        section.footerTitle = Self.descriptionForCurrentDiscoverability

        section.add(discoverabilityItem(true))
        section.add(discoverabilityItem(false))

        contents.addSection(section)

        self.contents = contents
    }

    func discoverabilityItem(_ isDiscoverable: Bool) -> OWSTableItem {
        return OWSTableItem(
            text: PhoneNumberDiscoverability.nameForDiscoverability(isDiscoverable),
            actionBlock: { [weak self] in
                self?.changeDiscoverability(isDiscoverable)
            },
            accessoryType: tsAccountManager.isDiscoverableByPhoneNumber() == isDiscoverable ? .checkmark : .none
        )
    }

    func changeDiscoverability(_ isDiscoverable: Bool) {
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
}
