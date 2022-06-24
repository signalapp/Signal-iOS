//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

class MyStorySettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("MY_STORY_SETTINGS_TITLE", comment: "Title for the my story settings view")

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let myStoryThread: TSPrivateStoryThread! = databaseStorage.read {
            TSPrivateStoryThread.getMyStory(transaction: $0)
        }

        let visibilitySection = OWSTableSection()
        visibilitySection.separatorInsetLeading = NSNumber(value: Self.cellHInnerMargin + 32)
        visibilitySection.headerTitle = NSLocalizedString(
            "MY_STORIES_SETTINGS_VISIBILITY_HEADER",
            comment: "Header for the 'visibility' section of the my stories settings")
        visibilitySection.footerTitle = NSLocalizedString(
            "MY_STORIES_SETTINGS_VISIBILITY_FOOTER",
            comment: "Footer for the 'visibility' section of the my stories settings")
        contents.addSection(visibilitySection)

        do {
            let isSelected = myStoryThread.storyViewMode == .blockList && myStoryThread.addresses.isEmpty
            visibilitySection.add(buildVisibilityItem(
                title: NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_TITLE",
                    comment: "Title for the visibility option"),
                subtitle: NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_SUBTITLE",
                    comment: "Subtitle for the visibility option"),
                isSelected: isSelected,
                showDisclosureIndicator: false
            ) { [weak self] in
                Self.databaseStorage.write { transaction in
                    myStoryThread.updateWithStoryViewMode(.blockList, addresses: [], transaction: transaction)
                }
                self?.updateTableContents()
            })
        }

        do {
            let isSelected = myStoryThread.storyViewMode == .blockList && myStoryThread.addresses.count > 0
            let subtitle: String
            if isSelected {
                let formatString = NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_EXCEPT_SUBTITLE_%d",
                    tableName: "PluralAware",
                    comment: "Subtitle for the visibility option. Embeds number of excluded members")
                subtitle = String.localizedStringWithFormat(formatString, myStoryThread.addresses.count)
            } else {
                subtitle = NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_EXCEPT_SUBTITLE",
                    comment: "Subtitle for the visibility option")
            }
            visibilitySection.add(buildVisibilityItem(
                title: NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_EXCEPT_TITLE",
                    comment: "Title for the visibility option"),
                subtitle: subtitle,
                isSelected: isSelected,
                showDisclosureIndicator: true
            ) { [weak self] in
                let vc = SelectMyStoryRecipientsViewController(thread: myStoryThread, mode: .blockList) {
                    self?.updateTableContents()
                }
                self?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            })
        }

        do {
            let isSelected = myStoryThread.storyViewMode == .explicit
            let subtitle: String
            if isSelected {
                let formatString = NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ONLY_SHARE_WITH_SUBTITLE_%d",
                    tableName: "PluralAware",
                    comment: "Subtitle for the visibility option. Embeds number of allowed members")
                subtitle = String.localizedStringWithFormat(formatString, myStoryThread.addresses.count)
            } else {
                subtitle = NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ONLY_SHARE_WITH_SUBTITLE",
                    comment: "Subtitle for the visibility option")
            }
            visibilitySection.add(buildVisibilityItem(
                title: NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ONLY_SHARE_WITH_TITLE",
                    comment: "Title for the visibility option"),
                subtitle: subtitle,
                isSelected: isSelected,
                showDisclosureIndicator: true
            ) { [weak self] in
                let vc = SelectMyStoryRecipientsViewController(thread: myStoryThread, mode: .explicit) {
                    self?.updateTableContents()
                }
                self?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            })
        }

        let repliesSection = OWSTableSection()
        repliesSection.headerTitle = NSLocalizedString(
            "MY_STORIES_SETTINGS_REPLIES_HEADER",
            comment: "Header for the 'replies' section of the my stories settings")
        repliesSection.footerTitle = NSLocalizedString(
            "MY_STORIES_SETTINGS_REPLIES_FOOTER",
            comment: "Footer for the 'replies' section of the my stories settings")
        contents.addSection(repliesSection)

        repliesSection.add(.switch(
            withText: NSLocalizedString(
                "MY_STORIES_SETTINGS_REPLIES_SWITCH_TITLE",
                comment: "Title for the replies switch"),
            isOn: { myStoryThread.allowsReplies },
            target: self,
            selector: #selector(didToggleReplies(_:))
        ))
    }

    @objc
    func didToggleReplies(_ toggle: UISwitch) {
        let myStoryThread: TSPrivateStoryThread! = databaseStorage.read { TSPrivateStoryThread.getMyStory(transaction: $0) }
        guard myStoryThread.allowsReplies != toggle.isOn else { return }
        databaseStorage.write { transaction in
            myStoryThread.updateWithAllowsReplies(toggle.isOn, transaction: transaction)
        }
    }

    func buildVisibilityItem(
        title: String,
        subtitle: String,
        isSelected: Bool,
        showDisclosureIndicator: Bool,
        action: @escaping () -> Void
    ) -> OWSTableItem {
        OWSTableItem {
            let cell = OWSTableItem.newCell()

            let hStack = UIStackView()
            hStack.axis = .horizontal
            hStack.spacing = 9
            cell.contentView.addSubview(hStack)
            hStack.autoPinEdgesToSuperviewMargins()

            if isSelected {
                let imageView = UIImageView()
                imageView.contentMode = .center
                imageView.autoSetDimension(.width, toSize: 22)
                imageView.setThemeIcon(.accessoryCheckmark, tintColor: Theme.primaryIconColor)
                hStack.addArrangedSubview(imageView)
            } else {
                hStack.addArrangedSubview(.spacer(withWidth: 22))
            }

            let vStack = UIStackView()
            vStack.axis = .vertical
            vStack.spacing = 2
            hStack.addArrangedSubview(vStack)

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.numberOfLines = 0
            titleLabel.font = .ows_dynamicTypeBody
            titleLabel.textColor = Theme.primaryTextColor
            vStack.addArrangedSubview(titleLabel)

            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.numberOfLines = 0
            subtitleLabel.font = .ows_dynamicTypeFootnote
            subtitleLabel.textColor = Theme.secondaryTextAndIconColor
            vStack.addArrangedSubview(subtitleLabel)

            if showDisclosureIndicator {
                cell.accessoryType = .disclosureIndicator
            }

            return cell
        } actionBlock: { action() }
    }
}
