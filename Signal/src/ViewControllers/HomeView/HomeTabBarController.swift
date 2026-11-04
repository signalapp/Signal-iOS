//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import SignalServiceKit
import SignalUI
public import UIKit

class HomeTabBarController: UITabBarController, UINavigationControllerDelegate, UITabBarControllerDelegate,
    BadgeObserver, StoryBadgeCountObserver, ConversationSplit
{

    init() {
        super.init(nibName: nil, bundle: nil)
    }

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
                    comment: "Title for the chat list's default mode.",
                )
            case .calls:
                return OWSLocalizedString(
                    "CALLS_LIST_TITLE",
                    comment: "Title for the calls list view.",
                )
            case .stories:
                return OWSLocalizedString(
                    "STORIES_TITLE",
                    comment: "Title for the stories view.",
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
                selectedImage: selectedImage,
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

        // MARK: Detail Placeholder

        fileprivate var detailPlaceholderTitle: NSAttributedString {
            let symbol: SignalSymbol = switch self {
            case .chatList: .message
            case .calls: .phone
            case .stories: .stories
            }
            return symbol.attributedString(staticFontSize: 64)
        }

        fileprivate var detailPlaceholderBody: NSAttributedString {
            let baseAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.dynamicTypeBody]
            switch self {
            case .chatList:
                let newChatIcon = SignalSymbol.compose.attributedString(for: .body)
                return .nonPluralLocalizedStringWithFormat(
                    OWSLocalizedString(
                        "HOME_CHATS_TAB_PLACEHOLDER",
                        comment: "Displayed on Chats tab when the screen is large (eg iPad) and is split into two columns and no chat is selected.",
                    ),
                    newChatIcon,
                    baseAttributes: baseAttributes,
                )

            case .calls:
                let callIcon = SignalSymbol.phonePlus.attributedString(for: .body)
                return .nonPluralLocalizedStringWithFormat(
                    OWSLocalizedString(
                        "HOME_CALLS_TAB_PLACEHOLDER",
                        comment: "Displayed on Calls tab when the screen is large (eg iPad) and is split into two columns and nothing is selected.",
                    ),
                    callIcon,
                    baseAttributes: baseAttributes,
                )

            case .stories:
                return NSAttributedString(
                    string: OWSLocalizedString(
                        "HOME_STORIES_TAB_PLACEHOLDER",
                        comment: "Displayed on Stories tab when screen is large (eg iPad) and is split into two columns.",
                    ),
                    attributes: baseAttributes,
                )
            }
        }

        fileprivate var detailPlaceholderViewContentConfiguration: SplitViewDetailPlaceholderViewController.ContentConfiguration {
            .init(title: detailPlaceholderTitle, body: detailPlaceholderBody)
        }
    }

    func makeSplit(
        primary: UIViewController,
        placeholder: UIViewController,
    ) -> HomeTabSplitViewController {
        let splitVC = HomeTabSplitViewController(
            primary: primary,
            placeholder: placeholder,
        )
        splitVC.preferredDisplayMode = .oneBesideSecondary
        splitVC.preferredSplitBehavior = .tile
        splitVC.presentsWithGesture = false // makes primary column always visible
        splitVC.displayModeButtonVisibility = .never
        splitVC.minimumPrimaryColumnWidth = 280
        splitVC.maximumPrimaryColumnWidth = 400
        splitVC.preferredPrimaryColumnWidthFraction = 0.42
        return splitVC
    }

    lazy var chatListViewController = ChatListViewController(chatListMode: .inbox)
    lazy var chatsSplitViewController = makeSplit(
        primary: chatListViewController,
        placeholder: SplitViewDetailPlaceholderViewController(
            contentConfiguration: Tabs.chatList.detailPlaceholderViewContentConfiguration,
        ),
    )
    lazy var chatListTabBarItem = Tabs.chatList.tabBarItem

    lazy var callsListViewController = CallsListViewController()
    lazy var callsSplitViewController = makeSplit(
        primary: callsListViewController,
        placeholder: SplitViewDetailPlaceholderViewController(
            contentConfiguration: Tabs.calls.detailPlaceholderViewContentConfiguration,
        ),
    )
    lazy var callsListTabBarItem = Tabs.calls.tabBarItem

    // No need to share spoiler render state across the whole app.
    lazy var storiesViewController = StoriesViewController(spoilerState: SpoilerRenderState())
    lazy var storiesSplitViewController = makeSplit(
        primary: storiesViewController,
        placeholder: SplitViewDetailPlaceholderViewController(
            contentConfiguration: Tabs.stories.detailPlaceholderViewContentConfiguration,
        ),
    )
    lazy var storiesTabBarItem = Tabs.stories.tabBarItem

    /// - returns: Currently selected split view controller.
    /// - warning: Use this property instead of `selectedViewController` because
    /// `selectedViewController` will not return a `UISplitViewController` on iOS 15-16.
    fileprivate var selectedSplitViewController: HomeTabSplitViewController? {
        guard let selectedViewController else { return nil }

        // Unwrap UISplitViewController from HomeTabSplitContainerViewController
        if #unavailable(iOS 26), let splitContainerVC = selectedViewController as? HomeTabSplitContainerViewController {
            return splitContainerVC.splitVC
        }
        return selectedViewController as? HomeTabSplitViewController
    }

    // There are two things going on here that require this code. The first is a stored property can't
    // conditionally include itself with an @available property, so some type erasing hoops need to be
    // jumped through to persis UITabs in a property.  As for why the need to persist UITabs -
    // UITabs are constructed with a 'viewControllerBuilder' completion that is required to return a
    // fresh UIViewController instance each time a tab is replaced.  This behavior is in conflict with
    // how this view controller manages the same set of child viewcontroller throughout it's lifetime.
    // To avoid having to rebuild the ViewControllers whenever there's a change (e.g. - hiding stories),
    // build UITabs once and persist them in a type erasing array.
    private var _uiTabs = [String: Any]()
    @available(iOS 18, *)
    private func uiTab(for tab: Tabs) -> UITab {
        var uiTab = _uiTabs[tab.tabIdentifier]
        if uiTab == nil {
            let vc = childControllers(for: tab).viewController
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

    private lazy var storyBadgeCountManager = StoryBadgeCountManager()

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        view.tintColor = .Signal.label

        NotificationCenter.default.addObserver(self, selector: #selector(storiesEnabledStateDidChange), name: .storiesEnabledStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterForeground), name: .OWSApplicationWillEnterForeground, object: nil)

        // We read directly from the database here, as the cache may not have been warmed by the time
        // this view is loaded (since it's the very first thing to load). Otherwise, there can be a
        // small window where the tab bar is in the wrong state at app launch.
        let areStoriesEnabled = SSKEnvironment.shared.databaseStorageRef.read { StoryManager.areStoriesEnabled(transaction: $0) }

        updateTabBars(areStoriesEnabled: areStoriesEnabled)

        AppEnvironment.shared.badgeManager.addObserver(self)
        storyBadgeCountManager.beginObserving(observer: self)
    }

    @objc
    private func didEnterForeground() {
        if selectedHomeTab == .stories {
            storyBadgeCountManager.markAllStoriesRead()
        }
    }

    private func updateTabBars(areStoriesEnabled: Bool) {
        let newTabs = tabsToShow(areStoriesEnabled: areStoriesEnabled)
        if #available(iOS 18, *) {
            self.tabs = newTabs.map(uiTab(for:))
        } else {
            initializeCustomTabBar(tabs: newTabs)
        }
        tabBar.tintColor = .Signal.label
    }

    @available(iOS, deprecated: 18)
    private func initializeCustomTabBar(tabs: [Tabs]) {
        // Use our custom tab bar.
        setValue(OWSTabBar(), forKey: "tabBar")

        viewControllers = tabs
            .map(childControllers(for:))
            .map { viewController, tabBarItem in
                viewController.tabBarItem = tabBarItem
                return viewController
            }
    }

    private func childControllers(for tab: HomeTabBarController.Tabs) -> (
        viewController: UIViewController,
        tabBarItem: UITabBarItem,
    ) {
        func wrapIfNecessary(_ splitVC: HomeTabSplitViewController) -> UIViewController {
            guard #unavailable(iOS 26) else { return splitVC }
            return HomeTabSplitContainerViewController(splitViewController: splitVC)
        }
        switch tab {
        case .chatList:
            return (wrapIfNecessary(chatsSplitViewController), chatListTabBarItem)
        case .calls:
            return (wrapIfNecessary(callsSplitViewController), callsListTabBarItem)
        case .stories:
            return (wrapIfNecessary(storiesSplitViewController), storiesTabBarItem)
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
            storiesSplitViewController.resetSecondaryViewController()
        }

        selectedHomeTab = .chatList
        setTabBar(hidden: false, animated: false)
    }

    // MARK: - Hiding the tab bar

    // FIXME: Can this conditionally override UITabBarController.isTabBarHidden on iOS 18?
    private var _isTabBarHidden: Bool = false

    /// Hides or displays the tab bar, resizing the selected view controller to fill the space remaining.
    @available(iOS, deprecated: 18, message: "Use UITabBarController.setTabBarHidden(:animated:).")
    func setTabBar(
        hidden: Bool,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil,
    ) {
        defer {
            _isTabBarHidden = hidden
        }

        guard _isTabBarHidden != hidden else {
            tabBar.isHidden = hidden
            completion?(true)
            return
        }

        let oldFrame = tabBar.frame
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
            tabBar.isHidden = false
            let animator = UIViewPropertyAnimator(duration: 0.1, curve: .easeOut) {
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

    // MARK: - BadgeObserver

    func didUpdateBadgeCount(_ badgeManager: BadgeManager, badgeCount: BadgeCount) {
        func stringify(_ badgeValue: UInt) -> String? {
            return badgeValue > 0 ? badgeValue.formatted() : nil
        }

        if #available(iOS 18, *) {
            uiTab(for: .chatList).badgeValue = stringify(badgeCount.unreadChatCount)
            uiTab(for: .chatList).accessibilityValue = stringify(badgeCount.unreadChatCount)
            uiTab(for: .calls).badgeValue = stringify(badgeCount.unreadCallsCount)
            uiTab(for: .calls).accessibilityValue = stringify(badgeCount.unreadCallsCount)
        } else {
            chatListTabBarItem.badgeValue = stringify(badgeCount.unreadChatCount)
            chatListTabBarItem.accessibilityValue = stringify(badgeCount.unreadChatCount)
            callsListTabBarItem.badgeValue = stringify(badgeCount.unreadCallsCount)
            callsListTabBarItem.accessibilityValue = stringify(badgeCount.unreadCallsCount)
        }
    }

    // MARK: - StoryBadgeCountObserver

    var isStoriesTabActive: Bool {
        return selectedHomeTab == .stories && CurrentAppContext().isAppForegroundAndActive()
    }

    func didUpdateStoryBadge(_ badge: String?) {
        if #available(iOS 18, *) {
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

    // MARK: - Selected Chat

    var selectedConversationViewController: ConversationViewController? {
        guard selectedHomeTab == .chatList else { return nil }

        var navigationController: UINavigationController
        if chatsSplitViewController.isCollapsed {
            guard
                let primaryNavigationController = chatsSplitViewController.primaryNavigationController,
                primaryNavigationController.viewControllers.count > 1
            else { return nil }

            navigationController = primaryNavigationController
        } else {
            guard let secondaryNavigationController = chatsSplitViewController.secondaryNavigationController
            else { return nil }

            navigationController = secondaryNavigationController
        }

        if let conversationVC = navigationController.findViewController(ofType: ConversationViewController.self) {
            return conversationVC
        }
        return nil
    }

    /// The thread, if any, that is currently presented in the view hieararchy. It may be currently
    /// covered by a modal presentation or a pushed view controller.
    var selectedThread: TSThread? {
        guard selectedHomeTab == .chatList else { return nil }
        return selectedConversationViewController?.thread
    }

    /// - Returns: currently selected thread if its conversation view is visible on the screen, otherwise `nil`.
    var visibleThread: TSThread? {
        guard view.window?.isKeyWindow == true else { return nil }
        guard selectedConversationViewController?.isViewVisible == true else { return nil }
        return selectedThread
    }

    func presentThread(
        threadUniqueId: String,
        action: ConversationViewAction,
        focusMessageId: String?,
        animated: Bool,
    ) {
        if selectedHomeTab != .chatList {
            guard presentedViewController == nil else {
                dismiss(animated: true) {
                    self.presentThread(
                        threadUniqueId: threadUniqueId,
                        action: action,
                        focusMessageId: focusMessageId,
                        animated: animated,
                    )
                }
                return
            }

            // Ensure the tab bar is on the chat list.
            selectedHomeTab = .chatList
        }

        if
            let selectedConversationVC = selectedConversationViewController,
            selectedConversationVC.thread.uniqueId == threadUniqueId,
            let navigationController = selectedConversationVC.navigationController
        {
            // This thread is already selected, so pop to it.
            navigationController.popToViewController(selectedConversationVC, animated: animated)

            if let focusMessageId {
                selectedConversationVC.ensureInteractionLoadedThenScrollToInteraction(
                    focusMessageId,
                    alignment: .centerIfNotEntirelyOnScreen,
                    isAnimated: animated,
                )
            }

            return
        }

        // Update the last viewed thread on the conversation list so it
        // can maintain its scroll position when navigating back.
        chatListViewController.updateLastViewedThreadUniqueId(
            threadUniqueId,
            animated: animated,
        )

        let conversationViewController = SSKEnvironment.shared.databaseStorageRef.read { tx in
            ConversationViewController.load(
                threadViewModel: ThreadViewModel(
                    threadUniqueId: threadUniqueId,
                    forChatList: false,
                    transaction: tx,
                ),
                action: action,
                focusMessageId: focusMessageId,
                tx: tx,
            )
        }
        conversationViewController.threadActionProviderDelegate = chatListViewController

        chatsSplitViewController.showDetailViewController(conversationViewController, sender: self)
    }

    func closeSelectedConversation(animated: Bool) {
        guard let selectedConversationViewController else { return }

        if chatsSplitViewController.isCollapsed {
            // If we're currently displaying the conversation in the primary nav controller, remove it
            // and everything it pushed to the navigation stack from the nav controller. We don't want
            // to just pop to root as we might have opened this conversation from the archive.
            guard let primaryNavigationController = chatsSplitViewController.primaryNavigationController else {
                owsFailBeta("No primaryNavigationController")
                return
            }
            // Conversation VC might also be wrapped into a separate navigation controller.
            var selectedConversationIndex: Int? = nil
            if let index = primaryNavigationController.viewControllers.firstIndex(of: selectedConversationViewController) {
                selectedConversationIndex = index
            } else if
                let nc = selectedConversationViewController.navigationController,
                let index = primaryNavigationController.viewControllers.firstIndex(of: nc)
            {
                selectedConversationIndex = index
            }
            guard let selectedConversationIndex else {
                owsFailBeta("Could not unwind.")
                return
            }

            let targetViewController = primaryNavigationController.viewControllers[max(0, selectedConversationIndex - 1)]
            primaryNavigationController.popToViewController(targetViewController, animated: animated)
        } else {
            chatsSplitViewController.resetSecondaryViewController()
        }
    }

    // MARK: - App-wide actions

    enum ShowAppSettingsMode {
        enum BackupSettingsPage {
            case landingPage
            case remote(onAppearAction: BackupSettingsViewController.OnAppearAction? = nil)
            case local
        }

        case payments
        case payment(paymentsHistoryItem: PaymentsHistoryItem)
        case paymentsTransferIn
        case appearance
        case avatarBuilder
        case backups(
            page: BackupSettingsPage = BuildFlags.LocalFileBackups.settingsUI ? .landingPage : .remote(),
        )
        case corruptedUsernameResolution
        case corruptedUsernameLinkResolution
        case donate(donateMode: DonateViewController.DonateMode)
        case linkedDevices
        case proxy
        case accountSettings
    }

    func showAppSettingsWithMode(_ mode: ShowAppSettingsMode? = nil, completion: (() -> Void)? = nil) {
        Logger.info("")

        let navigationController = OWSNavigationController()
        let appSettingsViewController = AppSettingsViewController()

        var internalCompletion: (() -> Void)?
        var viewControllers: [UIViewController] = [appSettingsViewController]

        switch mode {
        case nil:
            break

        case .payments:
            let paymentsSettings = PaymentsSettingsViewController(mode: .inAppSettings)
            viewControllers += [paymentsSettings]

        case .payment(let paymentsHistoryItem):
            let paymentsSettings = PaymentsSettingsViewController(mode: .inAppSettings)
            let paymentsDetail = PaymentsDetailViewController(paymentItem: paymentsHistoryItem)
            viewControllers += [paymentsSettings, paymentsDetail]

        case .paymentsTransferIn:
            let paymentsSettings = PaymentsSettingsViewController(mode: .inAppSettings)
            let paymentsTransferIn = PaymentsTransferInViewController()
            viewControllers += [paymentsSettings, paymentsTransferIn]

        case .appearance:
            let appearance = AppearanceSettingsTableViewController()
            viewControllers += [appearance]

        case .avatarBuilder:
            let profile = ProfileSettingsViewController(
                usernameChangeDelegate: appSettingsViewController,
                usernameLinkScanDelegate: appSettingsViewController,
            )
            viewControllers += [profile]
            internalCompletion = { profile.presentAvatarSettingsView() }

        case .backups(let page):
            let backupSettingsVC: UIViewController
            switch page {
            case .landingPage:
                backupSettingsVC = BackupSettingsLandingPageViewController()
            case .remote(let onAppearAction):
                let shouldSkipOnboarding = DependenciesBridge.shared.db.read { tx in
                    if BackupSettingsStore().shouldOverrideShowBackupsOnboarding(tx: tx) {
                        return false
                    }
                    return BackupSettingsStore().haveBackupsEverBeenEnabled(tx: tx)
                }

                backupSettingsVC = BackupOnboardingCoordinator(
                    backupType: .remote,
                ).prepareForPresentation(
                    inNavController: navigationController,
                    onAppearAction: onAppearAction,
                    shouldSkipOnboarding: shouldSkipOnboarding,
                )
            case .local:
                let shouldSkipOnboarding = DependenciesBridge.shared.db.read { tx in
                    if LocalFileBackupStore().shouldOverrideShowLocalBackupsOnboarding(tx: tx) {
                        return false
                    }
                    return LocalFileBackupStore().localBackupsEnabled(tx: tx)
                }

                backupSettingsVC = BackupOnboardingCoordinator(
                    backupType: .local,
                ).prepareForPresentation(
                    inNavController: navigationController,
                    shouldSkipOnboarding: shouldSkipOnboarding,
                )
            }

            viewControllers += [
                backupSettingsVC,
            ]

        case .corruptedUsernameResolution:
            let profile = ProfileSettingsViewController(
                usernameChangeDelegate: appSettingsViewController,
                usernameLinkScanDelegate: appSettingsViewController,
            )
            viewControllers += [profile]
            internalCompletion = { profile.presentUsernameCorruptedResolution() }

        case .corruptedUsernameLinkResolution:
            let profile = ProfileSettingsViewController(
                usernameChangeDelegate: appSettingsViewController,
                usernameLinkScanDelegate: appSettingsViewController,
            )
            viewControllers += [profile]
            internalCompletion = { profile.presentUsernameLinkCorruptedResolution() }

        case let .donate(donateMode):
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard
                let registeredState = try? tsAccountManager.registeredStateWithMaybeSneakyTransaction(),
                let donationAllowedToken = DonationAllowedToken(registeredState: registeredState, remoteConfig: .current),
                donationAllowedToken.canDonate(inMode: donateMode.asDonationMode)
            else {
                DonationViewsUtil.openDonateWebsite()
                return
            }
            let donate = DonateViewController(preferredDonateMode: donateMode, donationAllowedToken: donationAllowedToken) { [weak self] finishResult in
                switch finishResult {
                case let .completedDonation(donateSheet, receiptCredentialSuccessMode):
                    donateSheet.dismiss(animated: true) { [weak self] in
                        guard
                            let self,
                            let badgeThanksSheetPresenter = BadgeThanksSheetPresenter.fromGlobalsWithSneakyTransaction(
                                successMode: receiptCredentialSuccessMode,
                            )
                        else { return }

                        Task {
                            await badgeThanksSheetPresenter.presentAndRecordBadgeThanks(
                                fromViewController: self,
                            )
                        }
                    }
                case let .monthlySubscriptionCancelled(donateSheet, toastText):
                    donateSheet.dismiss(animated: true) { [weak self] in
                        guard let self else { return }
                        self.view.presentToast(text: toastText, fromViewController: self)
                    }
                }
            }
            viewControllers += [donate]

        case .linkedDevices:
            viewControllers += [LinkedDevicesHostingController()]

        case .proxy:
            viewControllers += [PrivacySettingsViewController(), AdvancedPrivacySettingsViewController(), ProxySettingsViewController()]

        case .accountSettings:
            viewControllers += [AccountSettingsViewController()]
        }

        navigationController.setViewControllers(viewControllers, animated: false)
        DispatchQueue.main.async { [weak self] in
            self?.presentFormSheet(navigationController, animated: true) {
                completion?()
                internalCompletion?()
            }
        }
    }

    func showMyStoriesController(animated: Bool) {
        if selectedHomeTab != .stories {
            guard presentedViewController == nil else {
                dismiss(animated: true) {
                    self.showMyStoriesController(animated: animated)
                }
                return
            }
            selectedHomeTab = .stories
        }

        storiesViewController.showMyStories(animated: animated)
    }

    // MARK: - Keyboard Shortcuts

    override var canBecomeFirstResponder: Bool {
        return true
    }

    let appWideKeyCommands = [
        UIKeyCommand(
            action: #selector(showAppSettings),
            input: ",",
            modifierFlags: .command,
            discoverabilityTitle: CommonStrings.openAppSettingsButton,
        ),
    ]

    let chatListKeyCommands = [
        UIKeyCommand(
            action: #selector(showNewConversationView),
            input: "n",
            modifierFlags: .command,
            discoverabilityTitle: OWSLocalizedString(
                "KEY_COMMAND_NEW_MESSAGE",
                comment: "A keyboard command to present the new message dialog.",
            ),
        ),
        UIKeyCommand(
            action: #selector(showNewGroupView),
            input: "g",
            modifierFlags: .command,
            discoverabilityTitle: OWSLocalizedString(
                "KEY_COMMAND_NEW_GROUP",
                comment: "A keyboard command to present the new group dialog.",
            ),
        ),
        UIKeyCommand(
            action: #selector(focusSearch),
            input: "f",
            modifierFlags: .command,
            discoverabilityTitle: OWSLocalizedString(
                "KEY_COMMAND_SEARCH",
                comment: "A keyboard command to begin a search on the conversation list.",
            ),
        ),
        UIKeyCommand(
            action: #selector(selectPreviousConversation),
            input: UIKeyCommand.inputUpArrow,
            modifierFlags: .alternate,
            discoverabilityTitle: OWSLocalizedString(
                "KEY_COMMAND_PREVIOUS_CONVERSATION",
                comment: "A keyboard command to jump to the previous conversation in the list.",
            ),
        ),
        UIKeyCommand(
            action: #selector(selectNextConversation),
            input: UIKeyCommand.inputDownArrow,
            modifierFlags: .alternate,
            discoverabilityTitle: OWSLocalizedString(
                "KEY_COMMAND_NEXT_CONVERSATION",
                comment: "A keyboard command to jump to the next conversation in the list.",
            ),
        ),
    ] + [
        UIKeyCommand(
            action: #selector(selectPreviousConversation),
            input: "\t",
            modifierFlags: [.control, .shift],
            discoverabilityTitle: OWSLocalizedString(
                "KEY_COMMAND_PREVIOUS_CONVERSATION",
                comment: "A keyboard command to jump to the previous conversation in the list.",
            ),
        ),
        UIKeyCommand(
            action: #selector(selectNextConversation),
            input: "\t",
            modifierFlags: .control,
            discoverabilityTitle: OWSLocalizedString(
                "KEY_COMMAND_NEXT_CONVERSATION",
                comment: "A keyboard command to jump to the next conversation in the list.",
            ),
        ),
    ].map {
        $0.wantsPriorityOverSystemBehavior = true
        return $0
    }

    var selectedConversationKeyCommands: [UIKeyCommand] {
        return [
            UIKeyCommand(
                action: #selector(openConversationSettings),
                input: "i",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_CONVERSATION_INFO",
                    comment: "A keyboard command to open the current conversation's settings.",
                ),
            ),
            UIKeyCommand(
                action: #selector(openAllMedia),
                input: "m",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_ALL_MEDIA",
                    comment: "A keyboard command to open the current conversation's all media view.",
                ),
            ),
            UIKeyCommand(
                action: #selector(openGifSearch),
                input: "g",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_GIF_SEARCH",
                    comment: "A keyboard command to open the current conversations GIF picker.",
                ),
            ),
            UIKeyCommand(
                action: #selector(openAttachmentKeyboard),
                input: "u",
                modifierFlags: .command,
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_ATTACHMENTS",
                    comment: "A keyboard command to open the current conversation's attachment picker.",
                ),
            ),
            UIKeyCommand(
                action: #selector(openStickerKeyboard),
                input: "s",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_STICKERS",
                    comment: "A keyboard command to open the current conversation's sticker picker.",
                ),
            ),
            UIKeyCommand(
                action: #selector(archiveSelectedConversation),
                input: "a",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_ARCHIVE",
                    comment: "A keyboard command to archive the current conversation.",
                ),
            ),
            UIKeyCommand(
                action: #selector(unarchiveSelectedConversation),
                input: "u",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_UNARCHIVE",
                    comment: "A keyboard command to unarchive the current conversation.",
                ),
            ),
            UIKeyCommand(
                action: #selector(focusInputToolbar),
                input: "t",
                modifierFlags: [.command, .shift],
                discoverabilityTitle: OWSLocalizedString(
                    "KEY_COMMAND_FOCUS_COMPOSER",
                    comment: "A keyboard command to focus the current conversation's input field.",
                ),
            ),
        ]
    }

    override var keyCommands: [UIKeyCommand]? {
        // If there is a modal presented over us, or another window above us, don't respond to keyboard commands.
        guard presentedViewController == nil || view.window?.isKeyWindow != true else { return nil }

        // Don't allow keyboard commands while presenting context menu.
        guard selectedConversationViewController?.isPresentingContextMenu != true else { return nil }

        var keyCommands = appWideKeyCommands
        if selectedThread != nil {
            keyCommands += selectedConversationKeyCommands
        }
        if selectedHomeTab == .chatList {
            keyCommands += chatListKeyCommands
        }
        return keyCommands
    }

    @objc
    func showNewConversationView() {
        chatListViewController.showNewConversationView()
    }

    @objc
    func showNewGroupView() {
        chatListViewController.showNewGroupView()
    }

    @objc
    func showAppSettings() {
        showAppSettingsWithMode()
    }

    func showCameraView(completion: ((UINavigationController) -> Void)? = nil) {
        selectedHomeTab = .chatList
        chatListViewController.presentCameraView(completion: completion)
    }

    @objc
    func focusSearch() {
        chatListViewController.focusSearch()
    }

    @objc
    func selectPreviousConversation() {
        chatListViewController.selectPreviousConversation()
    }

    @objc
    func selectNextConversation() {
        chatListViewController.selectNextConversation()
    }

    @objc
    func archiveSelectedConversation() {
        chatListViewController.archiveSelectedConversation()
    }

    @objc
    func unarchiveSelectedConversation() {
        chatListViewController.unarchiveSelectedConversation()
    }

    @objc
    func openConversationSettings() {
        guard let selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }
        selectedConversationViewController.showConversationSettings()
    }

    @objc
    func focusInputToolbar() {
        guard let selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }
        selectedConversationViewController.focusInputToolbar()
    }

    @objc
    func openAllMedia() {
        guard let selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }
        selectedConversationViewController.openAllMedia()
    }

    @objc
    func openStickerKeyboard() {
        guard let selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }
        selectedConversationViewController.openStickerKeyboard()
    }

    @objc
    func openAttachmentKeyboard() {
        guard let selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }
        selectedConversationViewController.openAttachmentKeyboard()
    }

    @objc
    func openGifSearch() {
        guard let selectedConversationViewController else {
            return owsFailDebug("unexpectedly missing selected conversation")
        }
        selectedConversationViewController.openGifSearch()
    }

    // MARK: - UITabBarControllerDelegate

    @available(iOS 18, *)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        // Scroll primary to top when user taps on the currently selected tab.
        if
            tab == tabBarController.selectedTab,
            let homeTabBarController = tabBarController as? HomeTabBarController,
            let homeTabSplitViewController = homeTabBarController.selectedSplitViewController
        {
            homeTabSplitViewController.scrollPrimaryViewControllerToTop(animated: true)
        }

        return true
    }

    @available(iOS, deprecated: 18)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        // Scroll primary to top when user taps on the currently selected tab.
        if
            selectedViewController === viewController,
            let homeTabBarController = tabBarController as? HomeTabBarController,
            let homeTabSplitViewController = homeTabBarController.selectedSplitViewController
        {
            homeTabSplitViewController.scrollPrimaryViewControllerToTop(animated: true)
        }

        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if isStoriesTabActive {
            storyBadgeCountManager.markAllStoriesRead()
        }
    }

    // MARK: - UINavigationControllerDelegate

    weak var navigationTransitionDelegate: UINavigationControllerDelegate?

    func navigationController(
        _ navigationController: UINavigationController,
        interactionControllerFor animationController: UIViewControllerAnimatedTransitioning,
    ) -> UIViewControllerInteractiveTransitioning? {
        navigationTransitionDelegate?.navigationController?(
            navigationController,
            interactionControllerFor: animationController,
        )
    }

    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController,
    ) -> UIViewControllerAnimatedTransitioning? {
        navigationTransitionDelegate?.navigationController?(
            navigationController,
            animationControllerFor: operation,
            from: fromVC,
            to: toVC,
        )
    }
}

@available(iOS, deprecated: 18)
public class OWSTabBar: UITabBar {

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public static let backgroundBlurMutingFactor: CGFloat = 0.5
    var blurEffectView: UIVisualEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil,
        )
    }

    override public var isHidden: Bool {
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
        guard isHidden == false else { return }

        guard UIAccessibility.isReduceTransparencyEnabled == false else {
            blurEffectView?.isHidden = true
            self.backgroundImage = UIImage.image(color: tabBarBackgroundColor)
            return
        }

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
        if
            let tintingView = blurEffectView.subviews.first(where: {
                String(describing: type(of: $0)) == "_UIVisualEffectSubview"
            })
        {
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

    @objc
    private func themeDidChange() {
        applyTheme()
    }
}

private class SplitViewDetailPlaceholderViewController: OWSViewController {

    struct ContentConfiguration {
        let title: NSAttributedString
        let body: NSAttributedString
    }

    private let contentConfiguration: ContentConfiguration

    init(contentConfiguration: ContentConfiguration) {
        self.contentConfiguration = contentConfiguration
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.Signal.background

        let titleLabel = UILabel()
        titleLabel.attributedText = contentConfiguration.title
            .styled(with: .color(.Signal.secondaryLabel))
        titleLabel.isAccessibilityElement = false

        let bodyLabel = UILabel()
        bodyLabel.attributedText = contentConfiguration.body
            .styled(with: .color(.Signal.secondaryLabel))

        let stackView = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(greaterThanOrEqualTo: contentLayoutGuide.topAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentLayoutGuide.leadingAnchor),
            stackView.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
        ])
    }
}

class HomeTabSplitViewController: UISplitViewController, UISplitViewControllerDelegate, UINavigationControllerDelegate {

    private let placeholderViewController: UIViewController

    fileprivate init(primary: UIViewController, placeholder: UIViewController) {
        placeholderViewController = placeholder

        super.init(style: .doubleColumn)

        delegate = self
        setViewController(primary, for: .primary)
        setViewController(placeholder, for: .secondary)

        // On iOS 26 and later, when navigating between chat list and conversation screen,
        // collapsed UISplitViewController will call `splitViewController(_:willShow:)` and
        // `splitViewController(_:willHide:)` for both columns as one would expect.
        // However, those delegate callbacks are not called for the collapsed split view
        // controller on iOS 15-18. To handle the change from the root view (eg chat list)
        // to detail view (eg convesation view) and back, and update visibility
        // of the tab bar accordingly, we need to monitor UINavigationController
        // for the `primary` column. That navigation controller is the one that responsible
        // for presenting anything that's pushed on top of the root in a collapsed split view.
        if #unavailable(iOS 26) {
            primaryNavigationController?.delegate = self
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Controller management

    fileprivate var primaryNavigationController: UINavigationController? {
        let vc = viewController(for: .primary)
        return (vc as? UINavigationController) ?? vc?.navigationController
    }

    fileprivate var secondaryNavigationController: UINavigationController? {
        let vc = viewController(for: .secondary)
        return (vc as? UINavigationController) ?? vc?.navigationController
    }

    /// - returns: When collapsed: top view controller in the primary column's navigation stack.
    /// When expanded: top view controller in the secondary column's navigation stack, falling back to primary column
    /// if secondary is empty.
    var topViewController: UIViewController? {
        if isCollapsed {
            var top: UIViewController? = primaryNavigationController
            // The collapsed detail can arrive as a nested navigation controller
            while let nc = top as? UINavigationController { top = nc.topViewController }
            return top
        }
        return secondaryNavigationController?.topViewController ?? primaryNavigationController?.topViewController
    }

    private var homeTabBarController: HomeTabBarController? {
        tabBarController as? HomeTabBarController
    }

    /// - returns: Root view controller for the primary column as `HomeTabViewController`.
    private var homeTabViewController: HomeTabViewController? {
        primaryNavigationController?.viewControllers.first as? HomeTabViewController
    }

    private func updateTabBar(displayMode mode: DisplayMode? = nil, animated: Bool = false) {
        guard
            let homeTabBarController,
            homeTabBarController.selectedSplitViewController === self
        else { return }

        let isPrimaryVisible: Bool
        if isCollapsed {
            // Collapsed: primary is "showing" when only its root is on the merged stack
            isPrimaryVisible = (primaryNavigationController?.viewControllers.count ?? 1) <= 1
        } else {
            isPrimaryVisible = (mode ?? displayMode) != .secondaryOnly
        }
        if #available(iOS 18, *) {
            homeTabBarController.setTabBarHidden(!isPrimaryVisible, animated: animated)
        } else {
            homeTabBarController.setTabBar(hidden: !isPrimaryVisible, animated: animated)
        }
    }

    fileprivate func scrollPrimaryViewControllerToTop(animated: Bool) {
        guard let homeTabViewController else {
            owsFailDebug("Could not find homeTabViewController")
            return
        }
        homeTabViewController.scrollToTop(animated: animated)
    }

    fileprivate func resetSecondaryViewController() {
        // This is used primarily to to unload `ConversationViewController`
        // once user navigates back from a conversation view back to the chat list
        // in a collapsed split view controller.
        // While there's no memory leak if we don't do this - keeping an active
        // chat view around might lead to an unwanted behavior if `ConversationViewController`
        // isn't careful about what it is doing while being loaded but not visible on the screen.
        setViewController(placeholderViewController, for: .secondary)
    }

    // MARK: - UISptilViewController overrides

    override func setViewController(_ vc: UIViewController?, for column: UISplitViewController.Column) {
        guard #unavailable(iOS 26) else {
            super.setViewController(vc, for: column)
            return
        }
        guard let vc else {
            super.setViewController(vc, for: column)
            return
        }
        // For proper functioning on pre-iOS 26 devices it is necessary to wrap
        // each view controller in a navigation controller.
        if vc is UINavigationController {
            super.setViewController(vc, for: column)
        } else {
            super.setViewController(UINavigationController(rootViewController: vc), for: column)
        }
    }

    override func showDetailViewController(_ vc: UIViewController, sender: Any?) {
        guard #unavailable(iOS 26) else {
            super.showDetailViewController(vc, sender: sender)
            return
        }
        // For proper functioning on pre-iOS 26 devices it is necessary to wrap
        // each view controller in a navigation controller.
        if vc is UINavigationController {
            super.showDetailViewController(vc, sender: sender)
        } else {
            super.showDetailViewController(UINavigationController(rootViewController: vc), sender: sender)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateTabBar(animated: animated) // covers tab switches
    }

    // MARK: - UISplitViewControllerDelegate

    func splitViewController(
        _ svc: UISplitViewController,
        topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column,
    ) -> UISplitViewController.Column {
        var topColumn = UISplitViewController.Column.primary
        // If there is a conversation selected in expanded state, keep the chat visible by collapsing into the secondary column.
        if
            proposedTopColumn == .secondary,
            let homeTabBarController,
            svc === homeTabBarController.chatsSplitViewController,
            homeTabBarController.selectedConversationViewController != nil
        {
            topColumn = proposedTopColumn
        }
        return topColumn
    }

    func splitViewController(_ svc: UISplitViewController, willShow column: UISplitViewController.Column) {
        guard column == .primary, homeTabBarController?.selectedSplitViewController === svc else { return }

        if let transitionCoordinator = svc.transitionCoordinator {
            transitionCoordinator.animate { _ in self.updateTabBar() }
        } else {
            updateTabBar()
        }
    }

    func splitViewController(_ svc: UISplitViewController, willHide column: UISplitViewController.Column) {
        guard homeTabBarController?.selectedSplitViewController === svc else { return }

        if let transitionCoordinator = svc.transitionCoordinator {
            transitionCoordinator.animate(
                alongsideTransition: { _ in
                    if column == .primary {
                        self.updateTabBar()
                    }
                },
                completion: { context in
                    // Unload secondary at the end of transition that wasn't canceled.
                    if column == .secondary, context.isCancelled == false {
                        self.resetSecondaryViewController()
                    }
                },
            )
        } else {
            if column == .primary {
                updateTabBar()
            }
        }
    }

    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        // Update appearance of the Settings button on iOS 26 and later.
        // Update because appearance depends on whether the split view controller is expanded or collapsed.
        if
            let homeSplitViewController = svc as? HomeTabSplitViewController,
            let homeTabViewController = homeSplitViewController.homeTabViewController,
            homeTabViewController.isSettingsButtonAppearanceFixed == false
        {
            homeTabViewController.updateSettingsBarButtonItem()
        }

        // Tab bar is not always visible in a collapsed split view controller.
        if homeTabBarController?.selectedSplitViewController === svc {
            updateTabBar()
        }
    }

    func splitViewControllerDidExpand(_ svc: UISplitViewController) {
        // Update appearance of the Settings button on iOS 26 and later.
        // Update because appearance depends on whether the split view controller is expanded or collapsed.
        if
            let homeSplitViewController = svc as? HomeTabSplitViewController,
            let homeTabViewController = homeSplitViewController.homeTabViewController,
            homeTabViewController.isSettingsButtonAppearanceFixed == false
        {
            homeTabViewController.updateSettingsBarButtonItem()
        }

        // Tab bar is always visible in expanded split view controller.
        if homeTabBarController?.selectedSplitViewController === svc {
            updateTabBar()
        }
    }

    func splitViewController(_ svc: UISplitViewController, willChangeTo displayMode: UISplitViewController.DisplayMode) {
        guard homeTabBarController?.selectedSplitViewController === svc else { return }

        if let transitionCoordinator = svc.transitionCoordinator {
            transitionCoordinator.animate { _ in self.updateTabBar(displayMode: displayMode) }
        } else {
            updateTabBar(displayMode: displayMode)
        }
    }

    // MARK: UINavigationController

    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool,
    ) {
        // iOS 26 and later tracks view changes in a collapsed split view controller
        // via `splitViewController(_:willShow:)` and `splitViewController(_:willHide:)`.
        // Please see the comment in `init` for more info.
        guard #unavailable(iOS 26), isCollapsed else { return }

        // Show hide navigation bar as user navigates between root view in the split view controller
        // and whatever is pushed on top of the root.
        if let transitionCoordinator = navigationController.transitionCoordinator {
            transitionCoordinator.animate(
                alongsideTransition: { _ in self.updateTabBar() },
                completion: { _ in self.updateTabBar() }, // re-check if a swipe is cancelled
            )
        } else {
            updateTabBar()
        }
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool,
    ) {
        // iOS 26 and later tracks view changes in a collapsed split view controller
        // via `splitViewController(_:willShow:)` and `splitViewController(_:willHide:)`.
        // Please see the comment in `init` for more info.
        guard #unavailable(iOS 26), isCollapsed else { return }

        // User navigated back to root - reset secondary column to the placeholder.
        // See comment in `resetSecondaryViewController()` about why we do this.
        if viewController is HomeTabViewController {
            resetSecondaryViewController()
        }
    }
}

/**
 * UIKit on iOS 15-18 has this bug when UISplitViewController, when put into a UITabBarController,
 * will not receive proper size class traits and will forever stay in horizontal compact environment,
 * which means the split will not expand into two columns when it should.
 * The workaround is to wrap UISplitViewController into a simple UIViewController and pass that
 * to the tab bar controller.
 */
@available(iOS, deprecated: 26, message: "It is not necessary to wrap UISplitViewController on iOS 26 and newer.")
private class HomeTabSplitContainerViewController: UIViewController {

    fileprivate let splitVC: HomeTabSplitViewController

    init(splitViewController: HomeTabSplitViewController) {
        splitVC = splitViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(splitVC)
        splitVC.view.frame = view.bounds
        splitVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(splitVC.view)
        splitVC.didMove(toParent: self)
    }
}

extension ConversationViewController {
    var homeTabBarController: HomeTabBarController? {
        return tabBarController as? HomeTabBarController
    }
}

private extension UINavigationController {
    /// - returns: First child or a grandchild that is an instance of a provided class.
    ///
    /// Method searches within immediate children, as well as within immediate children of child navigation controllers.
    func findViewController<T: UIViewController>(ofType type: T.Type) -> T? {
        for vc in viewControllers {
            // No recursion, go just one level deep.
            if
                let nc = vc as? UINavigationController,
                let result = nc.viewControllers.first(where: { $0 is T }) as? T
            {
                return result
            } else if let result = vc as? T {
                return result
            }
        }
        return nil
    }
}
