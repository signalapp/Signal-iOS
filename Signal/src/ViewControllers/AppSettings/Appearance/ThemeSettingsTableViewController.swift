//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

class ThemeSettingsTableViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_APPEARANCE_THEME_TITLE",
                                  comment: "The title for the theme section in the appearance settings.")

        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let themeSection = OWSTableSection()
        themeSection.add(appearanceItem(.system))
        themeSection.add(appearanceItem(.light))
        themeSection.add(appearanceItem(.dark))

        contents.add(themeSection)

        self.contents = contents
    }

    private func appearanceItem(_ mode: Theme.Mode) -> OWSTableItem {
        return OWSTableItem(
            text: Self.nameForThemeMode(mode),
            actionBlock: { [weak self] in
                self?.changeThemeMode(mode)
            },
            accessoryType: Theme.getOrFetchCurrentMode() == mode ? .checkmark : .none
        )
    }

    private func changeThemeMode(_ mode: Theme.Mode) {
        Theme.setCurrentMode(mode)
        updateTableContents()
    }

    static var currentThemeName: String {
        return nameForThemeMode(Theme.getOrFetchCurrentMode())
    }

    private static func nameForThemeMode(_ mode: Theme.Mode) -> String {
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
}
