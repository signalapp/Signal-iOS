//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
public import UIKit
import SignalServiceKit
import SignalUI

class HomeTabBarController: UITabBarController {

    private let appReadiness: AppReadinessSetter

    init(appReadiness: AppReadinessSetter) {
        self.appReadiness = appReadiness
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    enum Tabs: Int {
        case chatList = 0
        case calls = 1
        case stories = 2

        var title: String {
            switch self {
            case .chatList:
                return OWSLocalizedString(
                    "CHAT_LIST_TITLE_INBOX",
                    comment: "Title for the chat list's default mode."
                )
            case .calls:
                return OWSLocalizedString(
                    "CALLS_LIST_TITLE",
                    comment: "Title for the calls list view."
                )
            case .stories:
                return OWSLocalizedString(
                    "STORIES_TITLE",
                    comment: "Title for the stories view."
                )
            }
        }

        var image: UIImage? {
            switch self {
            case .chatList:
                return UIImage(imageLiteralResourceName: "tab-chats")
            case .calls:
                return UIImage(named: "tab-calls")
            case .stories:
                return UIImage(named: "tab-stories")
            }
        }

        var selectedImage: UIImage? {
            switch self {
            case .chatList:
                return UIImage(named: "tab-chats")
            case .calls:
                return UIImage(named: "tab-calls")
            case .stories:
                return UIImage(named: "tab-stories")
            }
        }

        var tabBarItem: UITabBarItem {
            return UITabBarItem(
                title: title,
                image: image,
                selectedImage: selectedImage
            )
        }

        var tabIdentifier: String {
            switch self {
            case .chatList:
                return "chats"
            case .calls:
                return "calls"
            case .stories:
                return "stories"
            }
        }
    }

    lazy var chatListViewController = ChatListViewController(chatListMode: .inbox, appReadiness: appReadiness)
    lazy var chatListNavController = OWSNavigationController(rootViewController: chatListViewController)
    lazy var chatListTabBarItem = Tabs.chatList.tabBarItem

    // No need to share spoiler render state across the whole app.
    lazy var storiesViewController = StoriesViewController(
        appReadiness: appReadiness,
        spoilerState: SpoilerRenderState()
    )
    lazy var storiesNavController = OWSNavigationController(rootViewController: storiesViewController)
    lazy var storiesTabBarItem = Tabs.stories.tabBarItem

    lazy var callsListViewController = CallsListViewController(appReadiness: appReadiness)
    lazy var callsListNavController = OWSNavigationController(rootViewController: callsListViewController)
    lazy var callsListTabBarItem = Tabs.calls.tabBarItem

    // There are two things going on here that require this code. The first is a stored property can't
    // conditionally include itself with an @available property, so some type erasing hoops need to be
    // jumped through to persis UITabs in a property.  As for why the need to persit UITabs -
    // UITabs are constructed with a 'viewControllerBuilder' completion that is required to return a
    // fresh UIViewController instance each time a tab is replaced.  This behavior is in conflict with
    // how this view controller manages the same set of child viewcontroller throughout it's lifetime.
    // To avoid having to rebuild the ViewControllers whenever there's a change (e.g. - hiding stories), 
    // build UITabs once and persist them in a type erasing array.
    private var _uiTabs = [String: Any]()
    @available(iOS 18, *)
    func uiTab(for tab: Tabs) -> UITab {
        var uiTab = _uiTabs[tab.tabIdentifier]
        if uiTab == nil {
            let vc = childControllers(for: tab).navigationController
            uiTab = UITab(title: tab.title, image: tab.image, identifier: tab.tabIdentifier) { _ in
                return vc
            }
            _uiTabs[tab.tabIdentifier] = uiTab
        }
        return uiTab as! UITab
    }

    var selectedHomeTab: Tabs {
        get { Tabs(rawValue: selectedIndex) ?? .chatList }
        set { selectedIndex = newValue.rawValue }
    }

    var owsTabBar: OWSTabBar? {
        return tabBar as? OWSTabBar
    }

    private lazy var storyBadgeCountManager = StoryBadgeCountManager()

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(storiesEnabledStateDidChange), name: .storiesEnabledStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterForeground), name: .OWSApplicationWillEnterForeground, object: nil)
        applyTheme()

        // We read directly from the database here, as the cache may not have been warmed by the time
        // this view is loaded (since it's the very first thing to load). Otherwise, there can be a
        // small window where the tab bar is in the wrong state at app launch.
        let areStoriesEnabled = SSKEnvironment.shared.databaseStorageRef.read { StoryManager.areStoriesEnabled(transaction: $0) }

        updateTabBars(areStoriesEnabled: areStoriesEnabled)

        AppEnvironment.shared.badgeManager.addObserver(self)
        storyBadgeCountManager.beginObserving(observer: self)

        setTabBarHidden(false, animated: false)
    }

    @objc
    private func didEnterForeground() {
        if selectedHomeTab == .stories {
            storyBadgeCountManager.markAllStoriesRead()
        }
    }

    @objc
    private func applyTheme() {
        tabBar.tintColor = Theme.primaryTextColor
    }

    private func updateTabBars(areStoriesEnabled: Bool) {
        let newTabs = tabsToShow(areStoriesEnabled: areStoriesEnabled)
        if #available(iOS 18, *), UIDevice.current.isIPad {
            self.tabs = newTabs.map(uiTab(for:))
        } else {
            initializeCustomTabBar(tabs: newTabs)
        }
        applyTheme()
    }

    private func initializeCustomTabBar(tabs: [Tabs]) {
        // Use our custom tab bar.
        setValue(OWSTabBar(), forKey: "tabBar")
        updateCustomTabBar(newTabs: tabs)
    }

    private func updateCustomTabBar(newTabs: [Tabs]) {
        viewControllers = newTabs
            .map(childControllers(for:))
            .map { (navController, tabBarItem) in
                navController.tabBarItem = tabBarItem
                return navController
            }
    }

    private func childControllers(for tab: HomeTabBarController.Tabs) -> (
        navigationController: OWSNavigationController,
        tabBarItem: UITabBarItem
    ) {
        switch tab {
        case .chatList:
            return (chatListNavController, chatListTabBarItem)
        case .calls:
            return (callsListNavController, callsListTabBarItem)
        case .stories:
            return (storiesNavController, storiesTabBarItem)
        }
    }

    private func tabsToShow(areStoriesEnabled: Bool) -> [Tabs] {
        var tabs = [Tabs.chatList, Tabs.calls]
        if areStoriesEnabled {
            tabs.append(Tabs.stories)
        }
        return tabs
    }

    @objc
    private func storiesEnabledStateDidChange() {
        updateTabBars(areStoriesEnabled: StoryManager.areStoriesEnabled)
        if selectedHomeTab == .stories {
            storiesNavController.popToRootViewController(animated: false)
        }

        selectedHomeTab = .chatList
        setTabBarHidden(false, animated: false)
    }

    // MARK: - Hiding the tab bar

    // FIXME: Can this conditionally override UITabBarController.isTabBarHidden on iOS 18?
    private var _isTabBarHidden: Bool = false

    /// Hides or displays the tab bar, resizing the selected view controller to
    /// fill the space remaining.
    public func setTabBarHidden(
        _ hidden: Bool,
        animated: Bool = true,
        duration: TimeInterval = 0.15,
        completion: ((Bool) -> Void)? = nil
    ) {
        defer {
            _isTabBarHidden = hidden
        }

        guard _isTabBarHidden != hidden else {
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

extension HomeTabBarController: BadgeObserver {
    func didUpdateBadgeCount(_ badgeManager: BadgeManager, badgeCount: BadgeCount) {
        func stringify(_ badgeValue: UInt) -> String? {
            return badgeValue > 0 ? "\(badgeValue)" : nil
        }

        if #available(iOS 18, *), UIDevice.current.isIPad {
            uiTab(for: .chatList).badgeValue = stringify(badgeCount.unreadChatCount)
            uiTab(for: .calls).badgeValue = stringify(badgeCount.unreadCallsCount)
        } else {
            chatListTabBarItem.badgeValue = stringify(badgeCount.unreadChatCount)
            callsListTabBarItem.badgeValue = stringify(badgeCount.unreadCallsCount)
        }
    }
}

extension HomeTabBarController: StoryBadgeCountObserver {

    public var isStoriesTabActive: Bool {
        return selectedHomeTab == .stories && CurrentAppContext().isAppForegroundAndActive()
    }

    public func didUpdateStoryBadge(_ badge: String?) {
        if #available(iOS 18, *), UIDevice.current.isIPad {
            uiTab(for: .stories).badgeValue = badge
        } else {
            storiesTabBarItem.badgeValue = badge
        }
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
            switch selectedHomeTab {
            case .chatList:
                tableView = chatListViewController.tableView
            case .stories:
                tableView = storiesViewController.tableView
            case .calls:
                tableView = callsListViewController.tableView
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

public class OWSTabBar: UITabBar {

    public var fullWidth: CGFloat {
        return superview?.frame.width ?? .zero
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public static let backgroundBlurMutingFactor: CGFloat = 0.5
    var blurEffectView: UIVisualEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .themeDidChange,
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
            self.backgroundImage = UIImage.image(color: tabBarBackgroundColor)
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
                self.backgroundImage = UIImage.image(color: color)
            }
        }
    }

    @objc
    private func themeDidChange() {
        applyTheme()
    }

    public var respectsTheme: Bool = true {
        didSet {
            themeDidChange()
        }
    }

    // MARK: Override Theme

    public enum TabBarStyle: Int {
        case `default`
    }

    private var currentStyle: TabBarStyle?

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
