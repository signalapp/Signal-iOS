//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalMessaging

protocol HomeTabViewController: UIViewController { }

extension HomeTabViewController {
    var conversationSplitViewController: ConversationSplitViewController? {
        return splitViewController as? ConversationSplitViewController
    }

    func createSettingsBarButtonItem(
        databaseStorage: SDSDatabaseStorage,
        shouldShowUnreadPaymentBadge: Bool = false,
        actions: (_ settingsAction: ContextMenuAction) -> [ContextMenuAction],
        showAppSettings: @escaping () -> Void
    ) -> UIBarButtonItem {
        let contextButton = ContextMenuButton()
        contextButton.showsContextMenuAsPrimaryAction = true
        contextButton.accessibilityLabel = CommonStrings.openSettingsButton

        let settingsAction = ContextMenuAction(
            title: CommonStrings.openSettingsButton,
            image: Theme.iconImage(.contextMenuSettings),
            handler: { _ in
                showAppSettings()
            }
        )
        contextButton.contextMenu = .init(actions(settingsAction))

        let avatarView = ConversationAvatarView(
            sizeClass: .twentyEight,
            localUserDisplayMode: .asUser
        )
        databaseStorage.read { transaction in
            avatarView.update(transaction) { config in
                guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else { return }
                config.dataSource = .address(localIdentifiers.aciAddress)
                config.applyConfigurationSynchronously()
            }
        }
        contextButton.addSubview(avatarView)
        avatarView.autoPinEdgesToSuperviewEdges()

        let barButtonView: UIView

        if shouldShowUnreadPaymentBadge {
            let wrapper = UIView.container()
            wrapper.addSubview(contextButton)
            contextButton.autoPinEdgesToSuperviewEdges()
            PaymentsViewUtils.addUnreadBadge(toView: wrapper)
            barButtonView = wrapper
        } else {
            barButtonView = contextButton
        }

        let barButtonItem = UIBarButtonItem(customView: barButtonView)
        barButtonItem.accessibilityLabel = CommonStrings.openSettingsButton
        return barButtonItem
    }
}
