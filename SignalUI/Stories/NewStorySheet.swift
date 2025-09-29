//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

final public class NewStorySheet: OWSTableSheetViewController {
    let selectItemsInParent: (([StoryConversationItem]) -> Void)?
    public init(selectItemsInParent: (([StoryConversationItem]) -> Void)?) {
        self.selectItemsInParent = selectItemsInParent

        super.init()

        tableViewController.defaultSeparatorInsetLeading =
            OWSTableViewController2.cellHInnerMargin + 48 + OWSTableItem.iconSpacing
    }

    public override func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }

        let headerSection = OWSTableSection()
        headerSection.customHeaderHeight = 2
        headerSection.hasBackground = false
        contents.add(headerSection)
        headerSection.add(.init(customCellBlock: {
            let label = UILabel()
            label.font = UIFont.dynamicTypeHeadlineClamped
            label.textColor = Theme.primaryTextColor
            label.text = OWSLocalizedString("NEW_STORY_SHEET_TITLE", comment: "Title for the new story sheet")
            label.textAlignment = .center

            let cell = OWSTableItem.newCell()
            cell.contentView.addSubview(label)
            label.autoPinEdgesToSuperviewEdges()

            return cell
        }))

        let optionsSection = OWSTableSection()
        optionsSection.customHeaderHeight = 28
        contents.add(optionsSection)
        optionsSection.add(buildOptionItem(
            icon: .genericStories,
            title: OWSLocalizedString("NEW_STORY_SHEET_CUSTOM_STORY_TITLE",
                                     comment: "Title for create custom story row on the 'new story sheet'"),
            subtitle: OWSLocalizedString("NEW_STORY_SHEET_CUSTOM_STORY_SUBTITLE",
                                        comment: "Subtitle for create custom story row on the 'new story sheet'"),
            action: { [weak self] in
                guard let self = self else { return }
                let presentingViewController = self.presentingViewController
                self.dismiss(animated: true) {
                    let vc = NewPrivateStoryRecipientsViewController(selectItemsInParent: self.selectItemsInParent)
                    presentingViewController?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
                }
            }))

        optionsSection.add(buildOptionItem(
            icon: .genericGroup,
            title: OWSLocalizedString("NEW_STORY_SHEET_GROUP_STORY_TITLE",
                                     comment: "Title for create group story row on the 'new story sheet'"),
            subtitle: OWSLocalizedString("NEW_STORY_SHEET_GROUP_STORY_SUBTITLE",
                                        comment: "Subtitle for create group story row on the 'new story sheet'"),
            action: { [weak self] in
                guard let self = self else { return }
                let presentingViewController = self.presentingViewController
                self.dismiss(animated: true) {
                    let vc = NewGroupStoryViewController(selectItemsInParent: self.selectItemsInParent)
                    presentingViewController?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
                }
            }))
    }

    func buildOptionItem(icon: ThemeIcon, title: String, subtitle: String, action: @escaping () -> Void) -> OWSTableItem {
        .init {
            let cell = OWSTableItem.newCell()
            cell.preservesSuperviewLayoutMargins = true
            cell.contentView.preservesSuperviewLayoutMargins = true

            let iconView = OWSTableItem.buildIconInCircleView(
                icon: icon,
                iconSize: AvatarBuilder.standardAvatarSizePoints,
                innerIconSize: 24,
                iconTintColor: Theme.primaryTextColor
            )

            let rowTitleLabel = UILabel()
            rowTitleLabel.text = title
            rowTitleLabel.textColor = Theme.primaryTextColor
            rowTitleLabel.font = .dynamicTypeBodyClamped
            rowTitleLabel.numberOfLines = 0

            let rowSubtitleLabel = UILabel()
            rowSubtitleLabel.text = subtitle
            rowSubtitleLabel.textColor = Theme.secondaryTextAndIconColor
            rowSubtitleLabel.font = .dynamicTypeSubheadlineClamped
            rowSubtitleLabel.numberOfLines = 0

            let titleStack = UIStackView(arrangedSubviews: [ rowTitleLabel, rowSubtitleLabel ])
            titleStack.axis = .vertical
            titleStack.alignment = .leading

            let contentRow = UIStackView(arrangedSubviews: [ iconView, titleStack ])
            contentRow.spacing = ContactCellView.avatarTextHSpacing
            contentRow.alignment = .center

            cell.contentView.addSubview(contentRow)
            contentRow.autoPinWidthToSuperviewMargins()
            contentRow.autoPinHeightToSuperview(withMargin: 7)

            return cell
        } actionBlock: { action() }
    }
}
