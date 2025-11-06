//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ImageQualitySettingsViewController: OWSTableViewController2 {
    private let thread: TSThread
    private let imageQualitySettingStore: ImageQualitySettingStore
    private let completion: () -> Void

    private var initialSetting: ImageQualitySetting!
    private var currentSetting: ImageQualitySetting!

    init(thread: TSThread,
         imageQualitySettingStore: ImageQualitySettingStore = ImageQualitySettingStore(),
         completion: @escaping () -> Void) {
        self.thread = thread
        self.imageQualitySettingStore = imageQualitySettingStore
        self.completion = completion
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "IMAGE_QUALITY_SETTING_TITLE",
            comment: "The title for the image quality settings screen"
        )
        OWSTableViewController2.removeBackButtonText(viewController: self)

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            let setting = imageQualitySettingStore.fetchSetting(for: thread, tx: tx)
            initialSetting = setting
            currentSetting = setting
        }

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let section = OWSTableSection()

        // Add toggle switch for Full Size
        section.add(OWSTableItem(
            customCellBlock: { [weak self] in
                guard let self = self else {
                    return OWSTableItem.newCell()
                }

                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none

                let label = UILabel()
                label.text = OWSLocalizedString(
                    "IMAGE_QUALITY_ORIGINAL_TOGGLE",
                    comment: "Toggle label for sending original quality images"
                )
                label.font = .dynamicTypeBody
                label.textColor = Theme.primaryTextColor

                let switchControl = UISwitch()
                switchControl.isOn = (self.currentSetting == .original)
                switchControl.addTarget(self, action: #selector(self.didToggleOriginal(_:)), for: .valueChanged)

                let stackView = UIStackView(arrangedSubviews: [label, switchControl])
                stackView.axis = .horizontal
                stackView.alignment = .center
                stackView.spacing = 12

                cell.contentView.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewMargins()

                return cell
            }
        ))

        section.footerTitle = OWSLocalizedString(
            "IMAGE_QUALITY_ORIGINAL_WARNING",
            comment: "Warning message about original quality images preserving metadata and location"
        )

        contents.add(section)
    }

    @objc
    private func didToggleOriginal(_ sender: UISwitch) {
        let newSetting: ImageQualitySetting = sender.isOn ? .original : .default
        if newSetting != currentSetting {
            currentSetting = newSetting
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                self.imageQualitySettingStore.setSetting(newSetting, for: self.thread, tx: tx)
            }
            completion()
        }
    }
}

