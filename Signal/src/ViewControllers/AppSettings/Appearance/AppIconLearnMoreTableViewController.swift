//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class AppIconLearnMoreTableViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()

        navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let topSection = OWSTableSection()
        topSection.headerAttributedTitle = NSAttributedString(
            string: OWSLocalizedString(
                "SETTINGS_APP_ICON_EDUCATION_APP_NAME",
                comment: "Information on sheet about changing the app icon - first line"
            )
        )
        .styled(
            with: .font(.dynamicTypeSubheadlineClamped),
            .color(Theme.secondaryTextAndIconColor)
        )
        topSection.add(.init(customCellBlock: { [weak self] in
            let homescreenImageName = UIDevice.current.isIPad ? "homescreen_ipados" : "homescreen_ios"
            return self?.createCell(
                with: homescreenImageName,
                insets: .init(hMargin: 48, vMargin: 24)
            ) ?? UITableViewCell()
        }))
        topSection.shouldDisableCellSelection = true

        let bottomSection = OWSTableSection()
        bottomSection.headerAttributedTitle = NSAttributedString(
            string: OWSLocalizedString(
                "SETTINGS_APP_ICON_EDUCATION_HOME_SCREEN_DOCK",
                comment: "Information on sheet about changing the app icon - second line"
            )
        )
        .styled(
            with: .font(.dynamicTypeSubheadlineClamped),
            .color(Theme.secondaryTextAndIconColor)
        )
        bottomSection.add(.init(customCellBlock: { [weak self] in
            let dockImageName = UIDevice.current.isIPad ? "dock_ipados" : "dock_ios"
            return self?.createCell(
                with: dockImageName,
                insets: .init(top: 0, leading: 16, bottom: 29, trailing: 16)
            ) ?? UITableViewCell()
        }))
        bottomSection.shouldDisableCellSelection = true

        contents.add(sections: [topSection, bottomSection])
        self.contents = contents
    }

    private func createCell(
        with image: String,
        insets: UIEdgeInsets
    ) -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        let image = UIImage(named: image)
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        cell.contentView.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges(with: insets)
        return cell
    }
}
