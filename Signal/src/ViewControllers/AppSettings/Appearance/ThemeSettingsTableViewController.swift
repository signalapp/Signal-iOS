//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
class ThemeSettingsTableViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_APPEARANCE_THEME_TITLE",
                                  comment: "The title for the theme section in the appearance settings.")

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let themeSection = OWSTableSection()
        if #available(iOS 13, *) {
            themeSection.add(appearanceItem(.system))
        }
        themeSection.add(appearanceItem(.light))
        themeSection.add(appearanceItem(.dark))

        contents.addSection(themeSection)

        self.contents = contents
    }

    func appearanceItem(_ mode: ThemeMode) -> OWSTableItem {
        return OWSTableItem(
            text: Self.nameForTheme(mode),
            actionBlock: { [weak self] in
                self?.changeTheme(mode)
            },
            accessoryType: Theme.getOrFetchCurrentTheme() == mode ? .checkmark : .none
        )
    }

    func changeTheme(_ mode: ThemeMode) {
        Theme.setCurrent(mode)
        updateTableContents()
    }

    static var currentThemeName: String {
        return nameForTheme(Theme.getOrFetchCurrentTheme())
    }

    static func nameForTheme(_ mode: ThemeMode) -> String {
        switch mode {
        case .dark:
            return OWSLocalizedString("APPEARANCE_SETTINGS_DARK_THEME_NAME",
                                     comment: "Name indicating that the dark theme is enabled.")
        case .light:
            return OWSLocalizedString("APPEARANCE_SETTINGS_LIGHT_THEME_NAME",
                                     comment: "Name indicating that the light theme is enabled.")
        case .system:
            return OWSLocalizedString("APPEARANCE_SETTINGS_SYSTEM_THEME_NAME",
                                     comment: "Name indicating that the system theme is enabled.")
        }
    }

    @objc
    func didToggleAvatarPreference(_ sender: UISwitch) {
        Logger.info("Avatar preference toggled: \(sender.isOn)")
        SDSDatabaseStorage.shared.asyncWrite { writeTx in
            SSKPreferences.setPreferContactAvatars(sender.isOn, transaction: writeTx)
        }
    }
}
