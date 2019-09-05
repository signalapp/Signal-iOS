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

        let section = OWSTableSection()

        let themeItem = OWSTableItem.disclosureItem(withText: "Theme", detailText: currentThemeName) { [weak self] in
            self?.showThemeChoices()
        }
        section.add(themeItem)

        // TODO iOS 13 – maybe expose the preferred language settings here to match android
        // It not longer seems to exist in iOS 13.1 so not sure if Apple got rid of it
        // or it has just temporarily been disabled.

        contents.addSection(section)

        self.contents = contents
    }

    func showThemeChoices() {
        let vc = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let systemButton = UIAlertAction(title: nameForTheme(.system), style: .default) { [weak self] _ in
            self?.changeTheme(.system)
        }
        vc.addAction(systemButton)

        let lightButton = UIAlertAction(title: nameForTheme(.light), style: .default) { [weak self] _ in
            self?.changeTheme(.light)
        }
        vc.addAction(lightButton)

        let darkButton = UIAlertAction(title: nameForTheme(.dark), style: .default) { [weak self] _ in
            self?.changeTheme(.dark)
        }
        vc.addAction(darkButton)

        vc.addAction(OWSAlerts.cancelAction)

        presentFullScreen(vc, animated: true)
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
