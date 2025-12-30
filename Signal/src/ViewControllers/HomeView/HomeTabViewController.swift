//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol HomeTabViewController: UIViewController { }

extension HomeTabViewController {
    var conversationSplitViewController: ConversationSplitViewController? {
        return splitViewController as? ConversationSplitViewController
    }

    /// - Parameter badgeColor
    /// Color for a badge added to the bar button item, if any.
    /// - Parameter onDidDismissContextMenu
    /// Block called when the context menu presented by tapping the bar button
    /// item is dismissed.
    func createSettingsBarButtonItem(
        databaseStorage: SDSDatabaseStorage,
        badgeColor: UIColor? = nil,
        onDidDismissContextMenu: @escaping () -> Void = {},
        buildActions: (_ settingsAction: UIMenuElement) -> [UIMenuElement],
        showAppSettings: @escaping () -> Void,
    ) -> UIBarButtonItem {
        let isInFloatingSidebar = if #available(iOS 26, *) {
            splitViewController?.isCollapsed == false
        } else {
            // Floating sidebar only exists on iOS 26+
            false
        }

        let settingsAction = UIAction(
            title: CommonStrings.openAppSettingsButton,
            image: Theme.iconImage(.contextMenuSettings),
            handler: { _ in showAppSettings() },
        )

        let contextButton = ContextMenuButton(
            actions: buildActions(settingsAction),
            onDidDismissContextMenu: onDidDismissContextMenu,
        )
        contextButton.accessibilityLabel = CommonStrings.openAppSettingsButton

        let sizeClass: ConversationAvatarView.Configuration.SizeClass
        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
            sizeClass = isInFloatingSidebar ? .thirtyTwo : .forty
        } else {
            sizeClass = .twentyEight
        }

        let avatarView = ConversationAvatarView(
            sizeClass: sizeClass,
            localUserDisplayMode: .asUser,
        )
        databaseStorage.read { transaction in
            avatarView.update(transaction) { config in
                guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction) else { return }
                config.dataSource = .address(localIdentifiers.aciAddress)
                config.applyConfigurationSynchronously()
            }
        }
        contextButton.addSubview(avatarView)

        avatarView.autoPinEdgesToSuperviewEdges(with: .init(
            top: 0,
            leading: isInFloatingSidebar ? 2 : 0,
            bottom: 0,
            trailing: 0,
        ))

        let barButtonView: UIView

        if let badgeColor {
            let wrapper = UIView.container()
            wrapper.addSubview(contextButton)
            contextButton.autoPinEdgesToSuperviewEdges()
            wrapper.addCircleBadge(color: badgeColor)
            barButtonView = wrapper
        } else {
            barButtonView = contextButton
        }

        let barButtonItem = UIBarButtonItem(customView: barButtonView)
        barButtonItem.accessibilityLabel = CommonStrings.openAppSettingsButton
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            barButtonItem.hidesSharedBackground = true
        }
#endif
        return barButtonItem
    }
}
