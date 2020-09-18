//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class PhoneNumberSharingSettingsTableViewController: OWSTableViewController {

    @objc
    class var nameForCurrentMode: String {
        return nameForMode(udManager.phoneNumberSharingMode)
    }

    class func nameForMode(_ mode: PhoneNumberSharingMode) -> String {
        switch mode {
        case .everybody:
            return NSLocalizedString("PHONE_NUMBER_SHARING_EVERYBODY",
                                     comment: "A user friendly name for the 'everybody' phone number sharing mode.")
        case .contactsOnly:
            return NSLocalizedString("PHONE_NUMBER_SHARING_CONTACTS_ONLY",
                                     comment: "A user friendly name for the 'contacts only' phone number sharing mode.")
        case .nobody:
            return NSLocalizedString("PHONE_NUMBER_SHARING_NOBODY",
                                     comment: "A user friendly name for the 'nobody' phone number sharing mode.")
        }
    }

    @objc
    class var descriptionForCurrentMode: String {
        switch udManager.phoneNumberSharingMode {
        case .everybody:
            return NSLocalizedString("PHONE_NUMBER_SHARING_EVERYBODY_DESCRIPTION",
                                     comment: "A user friendly description of the 'everybody' phone number sharing mode.")
        case .contactsOnly:
            return NSLocalizedString("PHONE_NUMBER_SHARING_CONTACTS_ONLY_DESCRIPTION",
                                     comment: "A user friendly description of the 'contacts only' phone number sharing mode.")
        case .nobody:
            return NSLocalizedString("PHONE_NUMBER_SHARING_NOBODY_DESCRIPTION",
                                     comment: "A user friendly description of the 'nobody' phone number sharing mode.")

        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PHONE_NUMBER_SHARING_TITLE",
                                  comment: "The title for the phone number sharing settings.")

        self.useThemeBackgroundColors = true

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.customHeaderView = .spacer(withHeight: 32)
        section.footerTitle = Self.descriptionForCurrentMode

        section.add(modeItem(.everybody))
        section.add(modeItem(.contactsOnly))
        section.add(modeItem(.nobody))

        contents.addSection(section)

        self.contents = contents
    }

    func modeItem(_ mode: PhoneNumberSharingMode) -> OWSTableItem {
        return OWSTableItem(
            text: Self.nameForMode(mode),
            actionBlock: { [weak self] in
                self?.changeMode(mode)
            },
            accessoryType: udManager.phoneNumberSharingMode == mode ? .checkmark : .none
        )
    }

    func changeMode(_ mode: PhoneNumberSharingMode) {
        databaseStorage.asyncWrite(block: { [weak self] transaction in
            self?.udManager.setPhoneNumberSharingMode(
                mode,
                updateStorageService: true,
                transaction: transaction.unwrapGrdbWrite
            )
        }) { [weak self] in
            self?.updateTableContents()
        }
    }
}
