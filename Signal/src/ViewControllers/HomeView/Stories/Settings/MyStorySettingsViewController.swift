//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalMessaging

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
            "STORY_SETTINGS_WHO_CAN_VIEW_THIS_HEADER",
            comment: "Section header for the 'viewers' section on the 'story settings' view"
        )
        // TODO: Add 'learn more' sheet button
        visibilitySection.footerTitle = NSLocalizedString(
            "STORY_SETTINGS_WHO_CAN_VIEW_THIS_FOOTER",
            comment: "Section footer for the 'viewers' section on the 'story settings' view"
        )
        contents.addSection(visibilitySection)

        do {
            let isSelected = myStoryThread.storyViewMode == .blockList && myStoryThread.addresses.isEmpty
            visibilitySection.add(buildVisibilityItem(
                title: NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_TITLE",
                    comment: "Title for the visibility option"),
                isSelected: isSelected,
                showDisclosureIndicator: false
            ) { [weak self] in
                Self.databaseStorage.write { transaction in
                    myStoryThread.updateWithStoryViewMode(
                        .blockList,
                        addresses: [],
                        updateStorageService: true,
                        transaction: transaction
                    )
                }
                self?.updateTableContents()
            })
        }

        do {
            let isSelected = myStoryThread.storyViewMode == .blockList && myStoryThread.addresses.count > 0
            let detailText: String?
            if isSelected {
                let formatString = NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_EXCEPT_SUBTITLE_%d",
                    tableName: "PluralAware",
                    comment: "Subtitle for the visibility option. Embeds number of excluded members")
                detailText = String.localizedStringWithFormat(formatString, myStoryThread.addresses.count)
            } else {
                detailText = nil
            }
            visibilitySection.add(buildVisibilityItem(
                title: NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_EXCEPT_TITLE",
                    comment: "Title for the visibility option"),
                detailText: detailText,
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
            let detailText: String?
            if isSelected {
                let formatString = NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ONLY_SHARE_WITH_SUBTITLE_%d",
                    tableName: "PluralAware",
                    comment: "Subtitle for the visibility option. Embeds number of allowed members")
                detailText = String.localizedStringWithFormat(formatString, myStoryThread.addresses.count)
            } else {
                detailText = nil
            }
            visibilitySection.add(buildVisibilityItem(
                title: NSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ONLY_SHARE_WITH_TITLE",
                    comment: "Title for the visibility option"),
                detailText: detailText,
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
        repliesSection.headerTitle = StoryStrings.repliesAndReactionsHeader
        repliesSection.footerTitle = StoryStrings.repliesAndReactionsFooter
        contents.addSection(repliesSection)

        repliesSection.add(.switch(
            withText: StoryStrings.repliesAndReactionsToggle,
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
            myStoryThread.updateWithAllowsReplies(toggle.isOn, updateStorageService: true, transaction: transaction)
        }
    }

    func buildVisibilityItem(
        title: String,
        detailText: String? = nil,
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

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.numberOfLines = 0
            titleLabel.font = .ows_dynamicTypeBody
            titleLabel.textColor = Theme.primaryTextColor
            hStack.addArrangedSubview(titleLabel)

            if let detailText = detailText {
                let detailLabel = UILabel()
                detailLabel.setContentHuggingHorizontalHigh()
                detailLabel.text = detailText
                detailLabel.numberOfLines = 0
                detailLabel.font = .ows_dynamicTypeBody
                detailLabel.textColor = Theme.secondaryTextAndIconColor
                hStack.addArrangedSubview(detailLabel)
            }

            if showDisclosureIndicator {
                cell.accessoryType = .disclosureIndicator
            }

            return cell
        } actionBlock: { action() }
    }
}
