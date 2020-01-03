//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class AppearanceSettingsTableViewController: OWSTableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_APPEARANCE_TITLE", comment: "The title for the appearance settings.")

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let themeSection = OWSTableSection()
        themeSection.headerTitle = NSLocalizedString("SETTINGS_APPEARANCE_THEME_TITLE",
                                                     comment: "The title for the theme section in the appearance settings.")

        themeSection.add(appearanceItem(.system))
        themeSection.add(appearanceItem(.light))
        themeSection.add(appearanceItem(.dark))

        contents.addSection(themeSection)

        // TODO iOS 13 – maybe expose the preferred language settings here to match android
        // It not longer seems to exist in iOS 13.1 so not sure if Apple got rid of it
        // or it has just temporarily been disabled.

        self.contents = contents
    }

    func appearanceItem(_ mode: ThemeMode) -> OWSTableItem {
        return OWSTableItem(
            text: nameForTheme(mode),
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

    var currentThemeName: String {
        return nameForTheme(Theme.getOrFetchCurrentTheme())
    }

    func nameForTheme(_ mode: ThemeMode) -> String {
        switch mode {
        case .dark:
            return NSLocalizedString("APPEARANCE_SETTINGS_DARK_THEME_NAME", comment: "Name indicating that the dark theme is enabled.")
        case .light:
            return NSLocalizedString("APPEARANCE_SETTINGS_LIGHT_THEME_NAME", comment: "Name indicating that the light theme is enabled.")
        case .system:
            return NSLocalizedString("APPEARANCE_SETTINGS_SYSTEM_THEME_NAME", comment: "Name indicating that the system theme is enabled.")
        }
    }
}
