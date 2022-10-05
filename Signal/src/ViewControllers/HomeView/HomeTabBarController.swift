//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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
        image: #imageLiteral(resourceName: "message-solid-24"),
        selectedImage: #imageLiteral(resourceName: "message-solid-24")
    )

    lazy var storiesViewController = StoriesViewController()
    lazy var storiesNavController = OWSNavigationController(rootViewController: storiesViewController)
    lazy var storiesTabBarItem = UITabBarItem(
        title: NSLocalizedString("STORIES_TITLE", comment: "Title for the stories view."),
        image: #imageLiteral(resourceName: "stories-solid-24"),
        selectedImage: #imageLiteral(resourceName: "stories-solid-24")
    )

    var selectedTab: Tabs {
        get { Tabs(rawValue: selectedIndex) ?? .chatList }
        set { selectedIndex = newValue.rawValue }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Use our custom tab bar.
        setValue(OWSTabBar(), forKey: "tabBar")

        delegate = self

        // Don't render the tab bar at all if stories isn't enabled.
        guard RemoteConfig.stories else {
            viewControllers = [chatListNavController]
            tabBar.isHidden = true
            return
        }

        NotificationCenter.default.addObserver(self, selector: #selector(storiesEnabledStateDidChange), name: .storiesEnabledStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .ThemeDidChange, object: nil)
        applyTheme()

        databaseStorage.appendDatabaseChangeDelegate(self)

        viewControllers = [chatListNavController, storiesNavController]

        chatListNavController.tabBarItem = chatListTabBarItem
        storiesNavController.tabBarItem = storiesTabBarItem

        updateAllBadges()

        // We read directly from the database here, as the cache may not have been warmed by the time
        // this view is loaded (since it's the very first thing to load). Otherwise, there can be a
        // small window where the tab bar is in the wrong state at app launch.
        let shouldHideTabBar = !databaseStorage.read { StoryManager.areStoriesEnabled(transaction: $0) }
        setTabBarHidden(shouldHideTabBar, animated: false)
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
            setTabBarHidden(true, animated: false)
            if selectedTab == .stories {
                storiesNavController.popToRootViewController(animated: false)
            }
            selectedTab = .chatList
        }
    }

    func updateAllBadges() {
        updateStoriesBadge()
        updateChatListBadge()
    }

    func updateStoriesBadge() {
        guard RemoteConfig.stories else { return }
        let unviewedStoriesCount = databaseStorage.read { transaction in
            StoryFinder.unviewedSenderCount(transaction: transaction)
        }
        storiesTabBarItem.badgeValue = unviewedStoriesCount > 0 ? "\(unviewedStoriesCount)" : nil
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
                completion?($0 == .end)
            })
            animator.startAnimation()
        } else {
            animations()
            self.tabBar.isHidden = hidden
            completion?(true)
        }
    }
}

extension HomeTabBarController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if databaseChanges.didUpdateInteractions || databaseChanges.didUpdateModel(collection: String(describing: ThreadAssociatedData.self)) {
            updateChatListBadge()
        }
        if databaseChanges.didUpdateModel(collection: StoryContextAssociatedData.collection()) {
            updateStoriesBadge()
        }
    }

    func databaseChangesDidUpdateExternally() {
        updateAllBadges()
    }

    func databaseChangesDidReset() {
        updateAllBadges()
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

        applyTheme()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .ThemeDidChange,
                                               object: nil)
    }

    // MARK: Theme

    var tabBarBackgroundColor: UIColor {
        Theme.navbarBackgroundColor
    }

    private func applyTheme() {
        guard respectsTheme else {
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
                if #available(iOS 16, *) { owsFailDebug("Check if this still works on new iOS version.") }

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
