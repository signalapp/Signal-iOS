//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

class StoryPrivacySettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("STORIES_SETTINGS_TITLE", comment: "Title for the story privacy settings view")
        navigationItem.leftBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing

        updateTableContents()
    }

    @objc
    func didTapDone() {
        dismiss(animated: true)
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let myStorySection = OWSTableSection()
        contents.addSection(myStorySection)
        myStorySection.add(OWSTableItem(customCellBlock: { [weak self] in
            guard let self = self else {
                owsFailDebug("Missing self")
                return OWSTableItem.newCell()
            }
            guard let cell = self.tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                owsFailDebug("Missing cell.")
                return OWSTableItem.newCell()
            }

            let configuration = ContactCellConfiguration(address: self.tsAccountManager.localAddress!, localUserDisplayMode: .asLocalUser)
            configuration.customName = NSLocalizedString(
                "MY_STORY_NAME",
                comment: "Name for the 'My Story' default story that sends to all the user's contacts."
            )

            self.databaseStorage.read { transaction in
                cell.configure(configuration: configuration, transaction: transaction)
            }

            cell.accessoryType = .disclosureIndicator

            return cell
            }) { [weak self] in
                                    // TODO:
        })

        let privateStoriesSection = OWSTableSection()
        privateStoriesSection.headerTitle = NSLocalizedString(
            "STORIES_SETTINGS_PRIVATE_STORIES_HEADER",
            comment: "Header for the 'Private Stories' section of the stories settings")
        privateStoriesSection.footerTitle = NSLocalizedString(
            "STORIES_SETTINGS_PRIVATE_STORIES_FOOTER",
            comment: "Footer for the 'Private Stories' section of the stories settings")
        contents.addSection(privateStoriesSection)

        privateStoriesSection.add(OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.preservesSuperviewLayoutMargins = true
            cell.contentView.preservesSuperviewLayoutMargins = true

            let iconView = OWSTableItem.buildIconInCircleView(icon: .settingsAddMembers,
                                                              iconSize: AvatarBuilder.smallAvatarSizePoints,
                                                              innerIconSize: 24,
                                                              iconTintColor: Theme.primaryTextColor)

            let rowLabel = UILabel()
            rowLabel.text = NSLocalizedString(
                "STORIES_SETTINGS_NEW_STORY",
                comment: "Label for 'new private story' button in story settings view.")
            rowLabel.textColor = Theme.primaryTextColor
            rowLabel.font = OWSTableItem.primaryLabelFont
            rowLabel.lineBreakMode = .byTruncatingTail

            let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
            contentRow.spacing = ContactCellView.avatarTextHSpacing

            cell.contentView.addSubview(contentRow)
            contentRow.autoPinWidthToSuperviewMargins()
            contentRow.autoPinHeightToSuperview(withMargin: 7)

            return cell
        }) { [weak self] in
            self?.showNewPrivateStoryView()
        })

        let storyThreads = databaseStorage.read { AnyThreadFinder().privateStoryThreads(transaction: $0) }
            .lazy
            .filter { !$0.isMyStory }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        for thread in storyThreads {
            privateStoriesSection.add(OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.accessoryType = .disclosureIndicator
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true

                let iconView = OWSTableItem.buildIconInCircleView(icon: .settingsPrivateStory,
                                                                  iconSize: AvatarBuilder.smallAvatarSizePoints,
                                                                  innerIconSize: 24,
                                                                  iconTintColor: Theme.primaryTextColor)

                let rowLabel = UILabel()
                rowLabel.text = thread.name
                rowLabel.textColor = Theme.primaryTextColor
                rowLabel.font = OWSTableItem.primaryLabelFont
                rowLabel.lineBreakMode = .byTruncatingTail

                let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
                contentRow.spacing = ContactCellView.avatarTextHSpacing

                cell.contentView.addSubview(contentRow)
                contentRow.autoPinWidthToSuperviewMargins()
                contentRow.autoPinHeightToSuperview(withMargin: 7)

                return cell
            }) { [weak self] in
                self?.showPrivateStoryView(for: thread)
            })
        }
    }

    func showNewPrivateStoryView() {

    }

    func showPrivateStoryView(for thread: TSPrivateStoryThread) {

    }
}
