//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

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

    private func updateTableContents() {
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
        firstSection.add(
            OWSTableItem(
                customCellBlock: { [weak self] in
                    OWSTableItem.buildCell(
                        itemName: OWSLocalizedString(
                            "SETTINGS_APPEARANCE_APP_ICON",
                            comment: "The title for the app icon section in the appearance settings."
                        ),
                        accessoryType: .disclosureIndicator,
                        accessoryContentView: self?.buildCurrentAppIconView())
                },
                actionBlock: { [weak self] in
                    guard let self else { return }
                    let vc = AppIconSettingsTableViewController()
                    vc.iconDelegate = self
                    self.navigationController?.pushViewController(vc, animated: true)
                }
            )
        )

        contents.add(firstSection)

        // TODO iOS 13 – maybe expose the preferred language settings here to match android
        // It not longer seems to exist in iOS 13.1 so not sure if Apple got rid of it
        // or it has just temporarily been disabled.

        self.contents = contents
    }

    private func buildCurrentAppIconView() -> UIView {
        let image = UIImage(named: CustomAppIcon.currentIconImageName)
        let imageView = UIImageView(image: image)
        imageView.autoSetDimensions(to: .square(24))
        // 60x60 icons have corner radius 12
        // 12 * (24/60) = 4.8
        imageView.layer.cornerRadius = 4.8
        imageView.clipsToBounds = true
        return imageView
    }
}

extension AppearanceSettingsTableViewController: AppIconSettingsTableViewControllerDelegate {
    func didChangeIcon() {
        updateTableContents()
    }
}
