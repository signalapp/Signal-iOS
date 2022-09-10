//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalUI

class StoryPrivacySettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("STORIES_SETTINGS_TITLE", comment: "Title for the story privacy settings view")

        if navigationController?.viewControllers.count == 1 {
            navigationItem.leftBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))
        }

        tableView.register(StoryThreadCell.self, forCellReuseIdentifier: StoryThreadCell.reuseIdentifier)

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing

        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    @objc
    func didTapDone() {
        dismiss(animated: true)
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let myStoriesSection = OWSTableSection()
        myStoriesSection.customHeaderView = NewStoryHeaderView(
            title: NSLocalizedString(
                "STORIES_SETTINGS_MY_STORIES_HEADER",
                comment: "Header for the 'My Stories' section of the stories settings"
            ),
            delegate: self
        )
        myStoriesSection.footerTitle = NSLocalizedString(
            "STORIES_SETTINGS_MY_STORIES_FOOTER",
            comment: "Footer for the 'My Stories' section of the stories settings"
        )
        contents.addSection(myStoriesSection)

        let storyItems = databaseStorage.read { transaction -> [StoryConversationItem] in
            StoryConversationItem
                .allItems(transaction: transaction)
                .sorted { lhs, rhs in
                    if case .privateStory(let item) = lhs.backingItem, item.isMyStory { return true }
                    if case .privateStory(let item) = rhs.backingItem, item.isMyStory { return false }
                    return lhs.title(transaction: transaction).localizedCaseInsensitiveCompare(rhs.title(transaction: transaction)) == .orderedAscending
                }
        }

        for item in storyItems {
            myStoriesSection.add(OWSTableItem(customCellBlock: { [weak self] in
                guard let cell = self?.tableView.dequeueReusableCell(withIdentifier: StoryThreadCell.reuseIdentifier) as? StoryThreadCell else {
                    owsFailDebug("Missing cell.")
                    return UITableViewCell()
                }
                Self.databaseStorage.read { transaction in
                    cell.configure(conversationItem: item, transaction: transaction)
                }
                return cell
            }) { [weak self] in
                self?.showSettings(for: item)
            })
        }
    }

    override func applyTheme() {
        super.applyTheme()
        updateTableContents()
    }

    func showSettings(for item: StoryConversationItem) {
        switch item.backingItem {
        case .groupStory(let groupItem):
            showGroupStorySettings(for: groupItem)
        case .privateStory(let privateStory):
            if privateStory.isMyStory {
                showMyStorySettings()
            } else {
                showPrivateStorySettings(for: privateStory)
            }
        }
    }

    func showMyStorySettings() {
        let vc = MyStorySettingsViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    func showPrivateStorySettings(for item: PrivateStoryConversationItem) {
        guard let storyThread = item.storyThread else {
            return owsFailDebug("Missing thread for private story")
        }
        let vc = PrivateStorySettingsViewController(thread: storyThread)
        navigationController?.pushViewController(vc, animated: true)
    }

    func showGroupStorySettings(for item: GroupConversationItem) {
        guard let groupThread = item.groupThread else {
            return owsFailDebug("Missing thread for group story")
        }
        let vc = GroupStorySettingsViewController(thread: groupThread)
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension StoryPrivacySettingsViewController: NewStoryHeaderDelegate {
    func newStoryHeaderView(_ newStoryHeaderView: NewStoryHeaderView, didCreateNewStoryItems items: [StoryConversationItem]) {
        updateTableContents()
    }
}

private class StoryThreadCell: ContactTableViewCell {
    open override class var reuseIdentifier: String { "StoryThreadCell" }

    // MARK: - ContactTableViewCell

    public func configure(conversationItem: StoryConversationItem, transaction: SDSAnyReadTransaction) {
        let configuration: ContactCellConfiguration
        switch conversationItem.messageRecipient {
        case .contact:
            owsFailDebug("Unexpected recipient for story")
            return
        case .group(let groupThreadId):
            guard let groupThread = TSGroupThread.anyFetchGroupThread(
                uniqueId: groupThreadId,
                transaction: transaction
            ) else {
                owsFailDebug("Failed to find group thread")
                return
            }
            configuration = ContactCellConfiguration(groupThread: groupThread, localUserDisplayMode: .noteToSelf)
        case .privateStory(_, let isMyStory):
            if isMyStory {
                guard let localAddress = tsAccountManager.localAddress else {
                    owsFailDebug("Unexpectedly missing local address")
                    return
                }
                configuration = ContactCellConfiguration(address: localAddress, localUserDisplayMode: .asUser)
                configuration.customName = conversationItem.title(transaction: transaction)
            } else {
                guard let image = conversationItem.image else {
                    owsFailDebug("Unexpectedly missing image for private story")
                    return
                }
                configuration = ContactCellConfiguration(name: conversationItem.title(transaction: transaction), avatar: image)
            }
        }

        configuration.attributedSubtitle = conversationItem.subtitle(transaction: transaction)?.asAttributedString

        super.configure(configuration: configuration, transaction: transaction)

        accessoryType = .disclosureIndicator
    }
}
