//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class AdvancedPinSettingsTableViewController: OWSTableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_ADVANCED_PIN_TITLE", comment: "The title for the advanced pin settings.")

        self.useThemeBackgroundColors = true

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let pinsSection = OWSTableSection()
        pinsSection.headerTitle = NSLocalizedString("SETTINGS_ADVANCED_PINS_HEADER",
                                                     comment: "Table header for the 'pins' section.")

        pinsSection.add(OWSTableItem.actionItem(
            withText: (KeyBackupService.hasMasterKey && !KeyBackupService.hasBackedUpMasterKey)
                ? NSLocalizedString("SETTINGS_ADVANCED_PINS_ENABLE_PIN_ACTION",
                                    comment: "")
                : NSLocalizedString("SETTINGS_ADVANCED_PINS_DISABLE_PIN_ACTION",
                                    comment: ""),
            textColor: Theme.accentBlueColor,
            accessibilityIdentifier: "advancedPinSettings.disable",
            actionBlock: { [weak self] in
                guard let self = self else { return }
                if KeyBackupService.hasMasterKey && !KeyBackupService.hasBackedUpMasterKey {
                    let vc = PinSetupViewController.creating { [weak self] _, _ in
                        guard let self = self else { return }
                        self.navigationController?.setNavigationBarHidden(false, animated: false)
                        self.navigationController?.popToViewController(self, animated: true)
                        self.updateTableContents()
                    }
                    self.navigationController?.pushViewController(vc, animated: true)
                } else {
                    PinSetupViewController.disablePinWithConfirmation(fromViewController: self).done { [weak self] _ in
                        self?.updateTableContents()
                    }
                }
        }))
        contents.addSection(pinsSection)

        self.contents = contents
    }
}
