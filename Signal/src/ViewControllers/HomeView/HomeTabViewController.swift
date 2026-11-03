//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol HomeTabViewController: UIViewController {
    var tableView: UITableView { get }

    // Split view controller will call this method whenever it transitions
    // in and out of collapsed state so that view controller could
    // update appearance for the navigation bar's settings button.
    func updateSettingsBarButtonItem()
}

extension HomeTabViewController {

    var homeTabBarController: HomeTabBarController? {
        tabBarController as? HomeTabBarController
    }

    func scrollToTop(animated: Bool) {
        let targetContentOffsetY = -tableView.adjustedContentInset.top
        tableView.setContentOffset(
            CGPoint(
                x: tableView.contentOffset.x,
                y: targetContentOffsetY,
            ),
            animated: animated,
        )
    }

    // Settings navigation bar button item has a fixed appearance on legacy iOS versions.
    // This property is how split view controller checks if reload of the Settings button
    // is necessary when transitioning between expanded and collapsed states.
    var isSettingsButtonAppearanceFixed: Bool {
        // Use different sizes and offsets in iOS 26.x only,
        // where side bar in expanded split view controller is a bit odd.
        if #available(iOS 27, *) { return true }
        if #available(iOS 26, *) { return false }
        return true
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

        let avatarSizeClass: ConversationAvatarView.Configuration.SizeClass
        let avatarLeadingMargin: CGFloat

        if #available(iOS 27, *) {
            avatarSizeClass = .forty
            avatarLeadingMargin = 0
        } else if #available(iOS 26, *) {
            // Floating sidebar only exists on iOS 26.x
            let isInFloatingSidebar = (splitViewController?.isCollapsed == false)
            avatarSizeClass = isInFloatingSidebar ? .thirtyTwo : .forty
            avatarLeadingMargin = isInFloatingSidebar ? 8 : 0
        } else {
            avatarSizeClass = .twentyEight
            avatarLeadingMargin = 2
        }

        let settingsAction = UIAction(
            title: CommonStrings.openAppSettingsButton,
            image: Theme.iconImage(.contextMenuSettings),
            handler: { _ in showAppSettings() },
        )

        let donateAction = UIAction(
            title: OWSLocalizedString(
                "HOME_VIEW_TITLE_DONATE",
                comment: "Title for the 'donate' action in the context menu of the settings button on home view tabs.",
            ),
            image: Theme.iconImage(.settingsDonate),
            handler: { [weak self] _ in
                self?.homeTabBarController?.showAppSettingsWithMode(
                    .donate(donateMode: .oneTime),
                )
            },
        )

        let contextButton = ContextMenuButton(
            actions: buildActions(settingsAction) + [donateAction],
            onDidDismissContextMenu: onDidDismissContextMenu,
        )
        contextButton.accessibilityLabel = CommonStrings.openAppSettingsButton

        let avatarView = ConversationAvatarView(
            sizeClass: avatarSizeClass,
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
            leading: avatarLeadingMargin,
            bottom: 0,
            trailing: 0,
        ))

        let barButtonView: UIView

        if let badgeColor {
            let wrapper = UIView.container()
            wrapper.addSubview(contextButton)
            contextButton.autoPinEdgesToSuperviewEdges()
            wrapper.addCircleBadge(
                color: badgeColor,
                onCircleView: avatarView,
                circleDiameter: CGFloat(avatarSizeClass.diameter),
            )
            barButtonView = wrapper
        } else {
            barButtonView = contextButton
        }

        let barButtonItem = UIBarButtonItem(customView: barButtonView)
        barButtonItem.accessibilityLabel = CommonStrings.openAppSettingsButton
        if #available(iOS 26.0, *) {
            barButtonItem.hidesSharedBackground = true
        }
        return barButtonItem
    }
}
