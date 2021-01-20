//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class WallpaperSettingsViewController: OWSTableViewController {
    let thread: TSThread?
    public init(thread: TSThread? = nil) {
        self.thread = thread
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: Wallpaper.wallpaperDidChangeNotification,
            object: nil
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("WALLPAPER_SETTINGS_TITLE", comment: "Title for the wallpaper settings view.")
        useThemeBackgroundColors = true
        updateTableContents()
    }

    @objc
    func updateTableContents() {
        let contents = OWSTableContents()

        let previewSection = OWSTableSection()
        previewSection.headerTitle = NSLocalizedString("WALLPAPER_SETTINGS_PREVIEW",
                                                       comment: "Title for the wallpaper settings preview section.")

        contents.addSection(previewSection)

        let setSection = OWSTableSection()
        setSection.customHeaderHeight = 14

        let setWallpaperItem = OWSTableItem.disclosureItem(
            withText: NSLocalizedString("WALLPAPER_SETTINGS_SET_WALLPAPER",
                                        comment: "Set wallpaper action in wallpaper settings view."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "set_wallpaper")
        ) { [weak self] in
            guard let self = self else { return }
            let vc = SetWallpaperViewController(thread: self.thread)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        setSection.add(setWallpaperItem)

        let dimWallpaperItem = OWSTableItem.switch(
            withText: NSLocalizedString("WALLPAPER_SETTINGS_DIM_WALLPAPER",
                                        comment: "Dim wallpaper action in wallpaper settings view."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "dim_wallpaper"),
            isOn: { () -> Bool in
                self.databaseStorage.read { Wallpaper.dimInDarkMode(for: self.thread, transaction: $0) }
            },
            isEnabledBlock: {
                self.databaseStorage.read { Wallpaper.exists(for: self.thread, transaction: $0) }
            },
            target: self,
            selector: #selector(updateWallpaperDimming)
        )
        setSection.add(dimWallpaperItem)

        contents.addSection(setSection)

        let resetSection = OWSTableSection()
        resetSection.customHeaderHeight = 14

        let clearWallpaperItem = OWSTableItem.actionItem(
            name: NSLocalizedString("WALLPAPER_SETTINGS_CLEAR_WALLPAPER",
                                    comment: "Clear wallpaper action in wallpaper settings view."),
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "clear_wallpaper")
        ) { [weak self] in
            guard let self = self else { return }
            self.databaseStorage.asyncWrite { transaction in
                do {
                    try Wallpaper.clear(for: self.thread, transaction: transaction)
                } catch {
                    owsFailDebug("Failed to clear wallpaper with error: \(error)")
                    DispatchQueue.main.async {
                        OWSActionSheets.showErrorAlert(
                            message: NSLocalizedString("WALLPAPER_SETTINGS_FAILED_TO_CLEAR",
                                                       comment: "An error indicating to the user that we failed to clear the wallpaper.")
                        )
                    }
                }
            }
        }
        resetSection.add(clearWallpaperItem)

        if thread == nil {
            let resetAllWallpapersItem = OWSTableItem.actionItem(
                name: NSLocalizedString("WALLPAPER_SETTINGS_RESET_ALL",
                                        comment: "Reset all wallpapers action in wallpaper settings view."),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "reset_all_wallpapers")
            ) { [weak self] in
                guard let self = self else { return }
                self.databaseStorage.asyncWrite { transaction in
                    do {
                        try Wallpaper.resetAll(transaction: transaction)
                    } catch {
                        owsFailDebug("Failed to reset all wallpapers with error: \(error)")
                        DispatchQueue.main.async {
                            OWSActionSheets.showErrorAlert(
                                message: NSLocalizedString("WALLPAPER_SETTINGS_FAILED_TO_RESET",
                                                           comment: "An error indicating to the user that we failed to reset all wallpapers.")
                            )
                        }
                    }
                }
            }
            resetSection.add(resetAllWallpapersItem)
        }

        contents.addSection(resetSection)

        self.contents = contents
    }

    @objc
    func updateWallpaperDimming(_ sender: UISwitch) {
        databaseStorage.asyncWrite { transaction in
            do {
                try Wallpaper.setDimInDarkMode(sender.isOn, for: self.thread, transaction: transaction)
            } catch {
                owsFailDebug("Failed to set dim in dark mode \(error)")
            }
        }
    }
}
