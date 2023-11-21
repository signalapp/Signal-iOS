//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit
import SignalUI

protocol ChatListSettingsButtonDelegate: AnyObject {
    func didUpdateButton(_ settingsButtonCreator: ChatListSettingsButtonCreator)
    func didTapMultiSelect(_ settingsButtonCreator: ChatListSettingsButtonCreator)
    func didTapAppSettings(_ settingsButtonCreator: ChatListSettingsButtonCreator)
    func didTapArchived(_ settingsButtonCreator: ChatListSettingsButtonCreator)
}

final class ChatListSettingsButtonCreator {
    private var hasInboxChats: Bool = false
    private var hasArchivedChats: Bool = false
    private var hasUnreadPaymentNotification: Bool = false

    weak var delegate: ChatListSettingsButtonDelegate?

    func updateState(
        hasInboxChats: Bool? = nil,
        hasArchivedChats: Bool? = nil,
        hasUnreadPaymentNotification: Bool? = nil
    ) {
        var didUpdate = false
        if let hasInboxChats {
            didUpdate = didUpdate || self.hasInboxChats != hasInboxChats
            self.hasInboxChats = hasInboxChats
        }
        if let hasArchivedChats {
            didUpdate = didUpdate || self.hasArchivedChats != hasArchivedChats
            self.hasArchivedChats = hasArchivedChats
        }
        if let hasUnreadPaymentNotification {
            didUpdate = didUpdate || self.hasUnreadPaymentNotification != hasUnreadPaymentNotification
            self.hasUnreadPaymentNotification = hasUnreadPaymentNotification
        }
        if didUpdate {
            delegate?.didUpdateButton(self)
        }
    }

    func buildButtonWithSneakyTransaction(db: DB) -> UIBarButtonItem {
        let contextButton = ContextMenuButton()
        contextButton.showsContextMenuAsPrimaryAction = true
        contextButton.contextMenu = settingsContextMenu()
        contextButton.accessibilityLabel = CommonStrings.openSettingsButton

        let avatarImageView = createAvatarBarButtonViewWithSneakyTransaction(db: db)
        contextButton.addSubview(avatarImageView)
        avatarImageView.autoPinEdgesToSuperviewEdges()

        let wrapper = UIView.container()
        wrapper.addSubview(contextButton)
        contextButton.autoPinEdgesToSuperviewEdges()

        if hasUnreadPaymentNotification {
            PaymentsViewUtils.addUnreadBadge(toView: wrapper)
        }

        let barButtonItem = UIBarButtonItem(customView: wrapper)
        barButtonItem.accessibilityLabel = CommonStrings.openSettingsButton
        barButtonItem.accessibilityIdentifier = "ChatListViewController.settingsButton"
        return barButtonItem
    }

    private func createAvatarBarButtonViewWithSneakyTransaction(db: DB) -> UIView {
        let avatarView = ConversationAvatarView(sizeClass: .twentyEight, localUserDisplayMode: .asUser)
        db.read { tx in
            avatarView.update(SDSDB.shimOnlyBridge(tx)) { config in
                if let address = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aciAddress {
                    config.dataSource = .address(address)
                    config.applyConfigurationSynchronously()
                }
            }
        }
        return avatarView
    }

    private func settingsContextMenu() -> ContextMenu {
        var contextMenuActions: [ContextMenuAction] = []
        if hasInboxChats {
            contextMenuActions.append(
                ContextMenuAction(
                    title: OWSLocalizedString("HOME_VIEW_TITLE_SELECT_CHATS", comment: "Title for the 'Select Chats' option in the ChatList."),
                    image: Theme.iconImage(.contextMenuSelect),
                    attributes: [],
                    handler: { [weak self] (_) in
                        guard let self else { return }
                        self.delegate?.didTapMultiSelect(self)
                    }
                ))
        }
        contextMenuActions.append(
            ContextMenuAction(
                title: CommonStrings.openSettingsButton,
                image: Theme.iconImage(.contextMenuSettings),
                attributes: [],
                handler: { [weak self] (_) in
                    guard let self else { return }
                    self.delegate?.didTapAppSettings(self)
                }
            ))
        if hasArchivedChats {
            contextMenuActions.append(
                ContextMenuAction(
                    title: OWSLocalizedString("HOME_VIEW_TITLE_ARCHIVE", comment: "Title for the conversation list's 'archive' mode."),
                    image: Theme.iconImage(.contextMenuArchive),
                    attributes: [],
                    handler: { [weak self] (_) in
                        guard let self else { return }
                        self.delegate?.didTapArchived(self)
                    }
                ))
        }
        return .init(contextMenuActions)
    }
}
