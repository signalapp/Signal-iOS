//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalServiceKit
import SignalUI

class HomeTabBarController: UITabBarController {
    enum Tabs: Int {
        case chatList = 0
        case stories = 1
    }

    lazy var chatListViewController = ChatListViewController()
    lazy var chatListNavController = OWSNavigationController(rootViewController: chatListViewController)
    lazy var chatListTabBarItem = UITabBarItem(
        title: NSLocalizedString("CHAT_LIST_TITLE_INBOX", comment: "Title for the chat list's default mode."),
        image: UIImage(named: "chats-tab-bar"),
        selectedImage: UIImage(named: "chats-tab-bar")
    )

    lazy var storiesViewController = StoriesViewController()
    lazy var storiesNavController = OWSNavigationController(rootViewController: storiesViewController)
    lazy var storiesTabBarItem = UITabBarItem(
        title: NSLocalizedString("STORIES_TITLE", comment: "Title for the stories view."),
        image: UIImage(named: "stories-tab-bar"),
        selectedImage: UIImage(named: "stories-tab-bar")
    )

    var selectedTab: Tabs {
        get { Tabs(rawValue: selectedIndex) ?? .chatList }
        set { selectedIndex = newValue.rawValue }
    }

    var owsTabBar: OWSTabBar? {
        return tabBar as? OWSTabBar
    }

    private lazy var storyBadgeCountManager = StoryBadgeCountManager()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Use our custom tab bar.
        setValue(OWSTabBar(), forKey: "tabBar")

        delegate = self

        // Don't render the tab bar at all if stories isn't enabled.
        guard RemoteConfig.stories else {
            viewControllers = [chatListNavController]
            self.setTabBarHidden(true, animated: false)
            return
        }

        NotificationCenter.default.addObserver(self, selector: #selector(storiesEnabledStateDidChange), name: .storiesEnabledStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .ThemeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterForeground), name: .OWSApplicationWillEnterForeground, object: nil)
        applyTheme()

        databaseStorage.appendDatabaseChangeDelegate(self)

        viewControllers = [chatListNavController, storiesNavController]

        chatListNavController.tabBarItem = chatListTabBarItem
        storiesNavController.tabBarItem = storiesTabBarItem

        updateChatListBadge()
        storyBadgeCountManager.beginObserving(observer: self)

        // We read directly from the database here, as the cache may not have been warmed by the time
        // this view is loaded (since it's the very first thing to load). Otherwise, there can be a
        // small window where the tab bar is in the wrong state at app launch.
        let shouldHideTabBar = !databaseStorage.read { StoryManager.areStoriesEnabled(transaction: $0) }
        setTabBarHidden(shouldHideTabBar, animated: false)
    }

    @objc
    func didEnterForeground() {
        if selectedTab == .stories {
            storyBadgeCountManager.markAllStoriesRead()
        }
    }

    @objc
    func applyTheme() {
        tabBar.tintColor = Theme.primaryTextColor
    }

    @objc
    func storiesEnabledStateDidChange() {
        if StoryManager.areStoriesEnabled {
            setTabBarHidden(false, animated: false)
        } else {
            if selectedTab == .stories {
                storiesNavController.popToRootViewController(animated: false)
            }
            selectedTab = .chatList
            setTabBarHidden(true, animated: false)
        }
    }

    func updateChatListBadge() {
        guard RemoteConfig.stories else { return }
        let unreadMessageCount = databaseStorage.read { transaction in
            InteractionFinder.unreadCountInAllThreads(transaction: transaction.unwrapGrdbRead)
        }
        chatListTabBarItem.badgeValue = unreadMessageCount > 0 ? "\(unreadMessageCount)" : nil
    }

    // MARK: - Hiding the tab bar

    private var isTabBarHidden: Bool = false

    /// Hides or displays the tab bar, resizing `selectedViewController` to fill the space remaining.
    public func setTabBarHidden(
        _ hidden: Bool,
        animated: Bool = true,
        duration: TimeInterval = 0.15,
        completion: ((Bool) -> Void)? = nil
    ) {
        defer {
            isTabBarHidden = hidden
        }

        guard isTabBarHidden != hidden else {
            tabBar.isHidden = hidden
            owsTabBar?.applyTheme()
            completion?(true)
            return
        }

        let oldFrame = self.tabBar.frame
        let containerHeight = tabBar.superview?.bounds.height ?? 0
        let newMinY = hidden ? containerHeight : containerHeight - oldFrame.height
        let additionalSafeArea = hidden
            ? (-oldFrame.height + view.safeAreaInsets.bottom)
            : (oldFrame.height - view.safeAreaInsets.bottom)

        let animations = {
            self.tabBar.frame = self.tabBar.frame.offsetBy(dx: 0, dy: newMinY - oldFrame.y)
            if let vc = self.selectedViewController {
                var additionalSafeAreaInsets = vc.additionalSafeAreaInsets
                additionalSafeAreaInsets.bottom += additionalSafeArea
                vc.additionalSafeAreaInsets = additionalSafeAreaInsets
            }

            self.view.setNeedsDisplay()
            self.view.layoutIfNeeded()
        }

        if animated {
            // Unhide for animations.
            self.tabBar.isHidden = false
            let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
                animations()
            }
            animator.addCompletion({
                self.tabBar.isHidden = hidden
                self.owsTabBar?.applyTheme()
                completion?($0 == .end)
            })
            animator.startAnimation()
        } else {
            animations()
            self.tabBar.isHidden = hidden
            owsTabBar?.applyTheme()
            completion?(true)
        }
    }
}

extension HomeTabBarController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if databaseChanges.didUpdateInteractions || databaseChanges.didUpdateModel(collection: String(describing: ThreadAssociatedData.self)) {
            updateChatListBadge()
        }
    }

    func databaseChangesDidUpdateExternally() {
        updateChatListBadge()
    }

    func databaseChangesDidReset() {
        updateChatListBadge()
    }
}

extension HomeTabBarController: StoryBadgeCountObserver {

    public var isStoriesTabActive: Bool {
        return selectedTab == .stories && CurrentAppContext().isAppForegroundAndActive()
    }

    public func didUpdateStoryBadge(_ badge: String?) {
        storiesTabBarItem.badgeValue = badge
        var views: [UIView] = [tabBar]
        var badgeViews = [UIView]()
        while let view = views.popLast() {
            if NSStringFromClass(view.classForCoder) == "_UIBadgeView" {
                badgeViews.append(view)
            }
            views = view.subviews + views
        }
        let sortedBadgeViews = badgeViews.sorted { lhs, rhs in
            let lhsX = view.convert(CGPoint.zero, from: lhs).x
            let rhsX = view.convert(CGPoint.zero, from: rhs).x
            if CurrentAppContext().isRTL {
                return lhsX > rhsX
            } else {
                return lhsX < rhsX
            }
        }
        let badgeView = sortedBadgeViews[safe: Tabs.stories.rawValue]
        badgeView?.layer.transform = CATransform3DIdentity
        let xOffset: CGFloat = CurrentAppContext().isRTL ? 0 : -5
        badgeView?.layer.transform = CATransform3DMakeTranslation(xOffset, 1, 1)
    }
}

extension HomeTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        // If we re-select the active tab, scroll to the top.
        if selectedViewController == viewController {
            let tableView: UITableView
            switch selectedTab {
            case .chatList:
                tableView = chatListViewController.tableView
            case .stories:
                tableView = storiesViewController.tableView
            }

            tableView.setContentOffset(CGPoint(x: 0, y: -tableView.safeAreaInsets.top), animated: true)
        }

        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if isStoriesTabActive {
            storyBadgeCountManager.markAllStoriesRead()
        }
    }
}

@objc
public class OWSTabBar: UITabBar {

    @objc
    public var fullWidth: CGFloat {
        return superview?.frame.width ?? .zero
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public static let backgroundBlurMutingFactor: CGFloat = 0.5
    var blurEffectView: UIVisualEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .ThemeDidChange,
                                               object: nil)
    }

    public override var isHidden: Bool {
        didSet {
            if !isHidden {
                applyTheme()
            }
        }
    }

    // MARK: Theme

    var tabBarBackgroundColor: UIColor {
        Theme.navbarBackgroundColor
    }

    fileprivate func applyTheme() {
        guard respectsTheme, !self.isHidden else {
            return
        }

        if UIAccessibility.isReduceTransparencyEnabled {
            blurEffectView?.isHidden = true
            self.backgroundImage = UIImage(color: tabBarBackgroundColor)
        } else {
            let blurEffect = Theme.barBlurEffect

            let blurEffectView: UIVisualEffectView = {
                if let existingBlurEffectView = self.blurEffectView {
                    existingBlurEffectView.isHidden = false
                    return existingBlurEffectView
                }

                let blurEffectView = UIVisualEffectView()
                blurEffectView.isUserInteractionEnabled = false

                self.blurEffectView = blurEffectView
                self.insertSubview(blurEffectView, at: 0)
                blurEffectView.autoPinEdgesToSuperviewEdges()

                return blurEffectView
            }()

            blurEffectView.effect = blurEffect

            // remove hairline below bar.
            self.shadowImage = UIImage()

            // Alter the visual effect view's tint to match our background color
            // so the tabbar, when over a solid color background matching tabBarBackgroundColor,
            // exactly matches the background color. This is brittle, but there is no way to get
            // this behavior from UIVisualEffectView otherwise.
            if let tintingView = blurEffectView.subviews.first(where: {
                String(describing: type(of: $0)) == "_UIVisualEffectSubview"
            }) {
                tintingView.backgroundColor = tabBarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)
                self.backgroundImage = UIImage()
            } else {
                if #available(iOS 17, *) { owsFailDebug("Check if this still works on new iOS version.") }

                owsFailDebug("Unexpectedly missing visual effect subview")
                // If we can't find the tinting subview (e.g. a new iOS version changed the behavior)
                // We'll make the tabBar more translucent by setting a background color.
                let color = tabBarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)
                self.backgroundImage = UIImage(color: color)
            }
        }
    }

    @objc
    public func themeDidChange() {
        applyTheme()
    }

    @objc
    public var respectsTheme: Bool = true {
        didSet {
            themeDidChange()
        }
    }

    // MARK: Override Theme

    @objc
    public enum TabBarStyle: Int {
        case `default`
    }

    private var currentStyle: TabBarStyle?

    @objc
    public func switchToStyle(_ style: TabBarStyle, animated: Bool = false) {
        AssertIsOnMainThread()

        guard currentStyle != style else { return }

        if animated {
            let animation = CATransition()
            animation.duration = 0.35
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.type = .fade
            layer.add(animation, forKey: "ows_fade")
        } else {
            layer.removeAnimation(forKey: "ows_fade")
        }

        currentStyle = style

        switch style {
        case .default:
            respectsTheme = true
            applyTheme()
        }
    }
}
