//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
class AppearanceSettingsTableViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_APPEARANCE_TITLE", comment: "The title for the appearance settings.")

        updateTableContents()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let firstSection = OWSTableSection()
        firstSection.add(OWSTableItem.disclosureItem(
            withText: OWSLocalizedString("SETTINGS_APPEARANCE_THEME_TITLE",
                                        comment: "The title for the theme section in the appearance settings."),
            detailText: ThemeSettingsTableViewController.currentThemeName,
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "theme")
        ) { [weak self] in
            guard let self = self else { return }
            let vc = ThemeSettingsTableViewController()
            self.navigationController?.pushViewController(vc, animated: true)
        })
        firstSection.add(OWSTableItem.disclosureItem(
            withText: OWSLocalizedString("SETTINGS_ITEM_COLOR_AND_WALLPAPER",
                                        comment: "Label for settings view that allows user to change the chat color and wallpaper."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "color_and_wallpaper")
        ) { [weak self] in
            guard let self = self else { return }
            let vc = ColorAndWallpaperSettingsViewController()
            self.navigationController?.pushViewController(vc, animated: true)
        })

        contents.addSection(firstSection)

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
            return OWSLocalizedString("APPEARANCE_SETTINGS_DARK_THEME_NAME", comment: "Name indicating that the dark theme is enabled.")
        case .light:
            return OWSLocalizedString("APPEARANCE_SETTINGS_LIGHT_THEME_NAME", comment: "Name indicating that the light theme is enabled.")
        case .system:
            return OWSLocalizedString("APPEARANCE_SETTINGS_SYSTEM_THEME_NAME", comment: "Name indicating that the system theme is enabled.")
        }
    }
}
