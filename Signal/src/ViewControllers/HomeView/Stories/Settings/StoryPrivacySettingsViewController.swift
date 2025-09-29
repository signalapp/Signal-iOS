//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

final class StoryPrivacySettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self, selector: #selector(storiesEnabledStateDidChange), name: .storiesEnabledStateDidChange, object: nil)

        if navigationController?.viewControllers.count == 1 {
            title = OWSLocalizedString("STORY_PRIVACY_TITLE", comment: "Title for the story privacy settings view")
            navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)
        } else {
            title = OWSLocalizedString(
                "STORY_SETTINGS_TITLE",
                comment: "Label for the stories section of the settings view"
            )
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
    private func storiesEnabledStateDidChange() {
        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        guard StoryManager.areStoriesEnabled else {
            let turnOnSection = OWSTableSection()
            turnOnSection.footerTitle = OWSLocalizedString(
                "STORIES_SETTINGS_TURN_ON_FOOTER",
                comment: "Footer for the 'turn on' section of the stories settings"
            )
            contents.add(turnOnSection)
            turnOnSection.add(.actionItem(
                withText: OWSLocalizedString(
                    "STORIES_SETTINGS_TURN_ON_STORIES_BUTTON",
                    comment: "Button to turn on stories on the story privacy settings view"
                ),
                actionBlock: {
                    SSKEnvironment.shared.databaseStorageRef.write { transaction in
                        StoryManager.setAreStoriesEnabled(true, transaction: transaction)
                    }
                }))

            return
        }

        let myStoriesSection = OWSTableSection()
        myStoriesSection.customHeaderView = NewStoryHeaderView(
            title: OWSLocalizedString(
                "STORIES_SETTINGS_STORIES_HEADER",
                comment: "Header for the 'Stories' section of the stories settings"
            ),
            delegate: self
        )
        myStoriesSection.footerTitle = OWSLocalizedString(
            "STORIES_SETTINGS_STORIES_FOOTER",
            comment: "Footer for the 'Stories' section of the stories settings"
        )
        contents.add(myStoriesSection)

        let storyItems = SSKEnvironment.shared.databaseStorageRef.read { transaction -> [StoryConversationItem] in
            StoryConversationItem
                .allItems(
                    includeImplicitGroupThreads: false,
                    excludeHiddenContexts: false,
                    blockingManager: SSKEnvironment.shared.blockingManagerRef,
                    transaction: transaction
                )
                .lazy
                .map { (item: $0, title: $0.title(transaction: transaction)) }
                .sorted { lhs, rhs in
                    if case .privateStory(let item) = lhs.item.backingItem, item.isMyStory { return true }
                    if case .privateStory(let item) = rhs.item.backingItem, item.isMyStory { return false }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                .map { $0.item }
        }

        for item in storyItems {
            myStoriesSection.add(OWSTableItem(
                customCellBlock: { [weak self] in
                    guard let cell = self?.tableView.dequeueReusableCell(withIdentifier: StoryThreadCell.reuseIdentifier) as? StoryThreadCell else {
                        owsFailDebug("Missing cell.")
                        return UITableViewCell()
                    }
                    SSKEnvironment.shared.databaseStorageRef.read { transaction in
                        cell.configure(conversationItem: item, transaction: transaction)
                    }
                    return cell
                },
                actionBlock: { [weak self] in
                    self?.showSettings(for: item)
                }
            ))
        }

        let viewReceiptsSection = OWSTableSection()
        viewReceiptsSection.footerTitle = OWSLocalizedString(
            "STORIES_SETTINGS_VIEW_RECEIPTS_FOOTER",
            comment: "Footer for the 'view receipts' section of the stories settings"
        )
        viewReceiptsSection.add(.switch(
            withText: OWSLocalizedString("STORIES_SETTINGS_VIEW_RECEIPTS", comment: "Title for the 'view receipts' setting in stories settings"),
            isOn: { StoryManager.areViewReceiptsEnabled },
            target: self,
            selector: #selector(didToggleViewReceipts)
        ))
        contents.add(viewReceiptsSection)

        let turnOffStoriesSection = OWSTableSection()
        turnOffStoriesSection.footerTitle = OWSLocalizedString(
            "STORIES_SETTINGS_TURN_OFF_FOOTER",
            comment: "Footer for the 'turn off' section of the stories settings"
        )
        contents.add(turnOffStoriesSection)
        turnOffStoriesSection.add(.item(
            name: OWSLocalizedString(
                "STORIES_SETTINGS_TURN_OFF_STORIES_BUTTON",
                comment: "Button to turn off stories on the story privacy settings view"
            ),
            textColor: .ows_accentRed,
            accessibilityIdentifier: nil,
            actionBlock: { [weak self] in
                self?.turnOffStoriesConfirmation()
            }))
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    private func showSettings(for item: StoryConversationItem) {
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
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let storyThread = databaseStorage.read { tx in item.fetchThread(tx: tx) }
        guard let storyThread else {
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

    func turnOffStoriesConfirmation() {
        let actionSheet = ActionSheetController(
            message: OWSLocalizedString(
                "STORIES_SETTINGS_TURN_OFF_ACTION_SHEET_MESSAGE",
                comment: "Title for the action sheet confirming you want to turn off and delete all stories"
            )
        )
        actionSheet.addAction(OWSActionSheets.cancelAction)
        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "STORIES_SETTINGS_TURN_OFF_AND_DELETE_STORIES_BUTTON",
                comment: "Button to turn off and delete stories on the story privacy settings view"
            ),
            style: .destructive,
            handler: { [weak self] _ in
                self?.turnOffStories()
            }))
        presentActionSheet(actionSheet)
    }

    func turnOffStories() {
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modal in
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
                StoryFinder.enumerateOutgoingStories(transaction: transaction) { storyMessage, _ in
                    storyMessage.remotelyDeleteForAllRecipients(transaction: transaction)
                }

                StoryManager.setAreStoriesEnabled(false, transaction: transaction)

                transaction.addSyncCompletion {
                    Task { @MainActor in
                        modal.dismiss()
                    }
                }
            }
        }
    }

    @objc
    private func didToggleViewReceipts(_ sender: UISwitch) {
        SSKEnvironment.shared.databaseStorageRef.write {
            StoryManager.setAreViewReceiptsEnabled(sender.isOn, transaction: $0)
        }
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

    public func configure(conversationItem: StoryConversationItem, transaction: DBReadTransaction) {
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
                guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress else {
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
