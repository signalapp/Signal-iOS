//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalMessaging
import SignalServiceKit
import SignalUI
import StoreKit

public class ChatListViewController: OWSViewController {

    // MARK: Init

    override init() {
        super.init()

        tableDataSource.viewController = self
        loadCoordinator.viewController = self
        reminderViews.viewController = self
        viewState.configure()
    }

    // MARK: View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        switch chatListMode {
        case .inbox:
            title = NSLocalizedString("CHAT_LIST_TITLE_INBOX", comment: "Title for the chat list's default mode.")
        case .archive:
            title = NSLocalizedString("HOME_VIEW_TITLE_ARCHIVE", comment: "Title for the conversation list's 'archive' mode.")
        }

        if !viewState.multiSelectState.isActive {
            applyDefaultBackButton()
        }

        // Table View
        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()
        tableView.accessibilityIdentifier = "ChatListViewController.tableView"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.allowsSelectionDuringEditing = true
        tableView.allowsMultipleSelectionDuringEditing = true

        // iOS 13 and later:
        // Automatically handled by UITableViewDelegate callbacks
        // -tableView:contextMenuConfigurationForRowAtIndexPath:point:
        // -tableView:willPerformPreviewActionForMenuWithConfiguration:animator:
        if #unavailable(iOS 13) {
            registerForPreviewing(with: self, sourceView: tableView)
        }

        addPullToRefreshIfNeeded()

        // Empty Inbox
        view.addSubview(emptyInboxView)
        emptyInboxView.autoPinWidthToSuperviewMargins()
        emptyInboxView.autoAlignAxis(.horizontal, toSameAxisOf: view, withMultiplier: 0.85)

        // First Conversation Cue
        view.addSubview(firstConversationCueView)
        firstConversationCueView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        // This inset bakes in assumptions about UINavigationBar layout, but I'm not sure
        // there's a better way to do it, since it isn't safe to use iOS auto layout with
        // UINavigationBar contents.
        firstConversationCueView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 6)
        firstConversationCueView.autoPinEdge(toSuperviewEdge: .leading, withInset: 10, relation: .greaterThanOrEqual)
        firstConversationCueView.autoPinEdge(toSuperviewMargin: .bottom, relation: .greaterThanOrEqual)

        // Search
        searchBar.placeholder = NSLocalizedString(
            "HOME_VIEW_CONVERSATION_SEARCHBAR_PLACEHOLDER",
            comment: "Placeholder text for search bar which filters conversations."
        )
        searchBar.delegate = self
        searchBar.accessibilityIdentifier = "ChatListViewController.searchBar"
        searchBar.textField?.accessibilityIdentifier = "ChatListViewController.conversation_search"
        searchBar.sizeToFit()
        searchBar.layoutMargins = .zero
        let searchBarContainer = UIView()
        searchBarContainer.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 0)
        searchBarContainer.frame = searchBar.frame
        searchBarContainer.addSubview(searchBar)
        searchBar.autoPinEdgesToSuperviewMargins()

        // Setting tableHeader calls numberOfSections, which must happen after updateMappings has been called at least once.
        owsAssertDebug(tableView.tableHeaderView == nil)
        tableView.tableHeaderView = searchBarContainer
        // Hide search bar by default.  User can pull down to search.
        tableView.contentOffset = CGPoint(x: 0, y: searchBar.frame.height)

        searchResultsController.delegate = self
        addChild(searchResultsController)
        view.addSubview(searchResultsController.view)
        searchResultsController.view.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        searchResultsController.view.autoPinTopToSuperviewMargin(withInset: 56)
        searchResultsController.view.isHidden = true

        updateReminderViews()
        applyTheme()
        observeNotifications()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        isViewVisible = true

        // Ensure the tabBar is always hidden if stories is disabled or we're in the archive.
        let shouldHideTabBar = !StoryManager.areStoriesEnabled || chatListMode == .archive
        if shouldHideTabBar {
            tabBarController?.tabBar.isHidden = true
            extendedLayoutIncludesOpaqueBars = true
        }

        let isShowingSearchResults = !searchResultsController.view.isHidden
        if isShowingSearchResults {
            owsAssertDebug(!(searchBar.text ?? "").stripped.isEmpty)
            scrollSearchBarToTop()
            searchBar.becomeFirstResponder()
        } else if let lastViewedThread {
            owsAssertDebug((searchBar.text ?? "").stripped.isEmpty)

            // When returning to conversation list, try to ensure that the "last" thread is still
            // visible.  The threads often change ordering while in conversation view due
            // to incoming & outgoing messages.
            if let indexPathOfLastThread = renderState.indexPath(forUniqueId: lastViewedThread.uniqueId) {
                tableView.scrollToRow(at: indexPathOfLastThread, at: .none, animated: false)
            }
        }

        if viewState.multiSelectState.isActive {
            tableView.setEditing(true, animated: false)
            reloadTableData()
            willEnterMultiselectMode()
        } else {
            applyDefaultBackButton()
        }

        searchResultsController.viewWillAppear(animated)
        ensureSearchBarCancelButton()

        updateUnreadPaymentNotificationsCountWithSneakyTransaction()

        // During main app launch, the chat list becomes visible _before_
        // app is foreground and active.  Therefore we need to make an
        // exception and update the view contents; otherwise, the home
        // view will briefly appear empty after launch. But to avoid
        // hurting first launch perf, we only want to make an exception
        // for a single load.
        if !hasEverAppeared {
            loadCoordinator.ensureFirstLoad()
        } else {
            ensureCellAnimations()
        }

        if let selectedIndexPath = tableView.indexPathForSelectedRow {
            // Deselect row when swiping back/returning to chat list.
            tableView.deselectRow(at: selectedIndexPath, animated: false)
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        BenchManager.completeEvent(eventId: "AppStart", logIfAbsent: false)
        InstrumentsMonitor.trackEvent(name: "ChatListViewController.viewDidAppear")
        AppReadiness.setUIIsReady()

        if getStartedBanner == nil && !hasEverPresentedExperienceUpgrade && ExperienceUpgradeManager.presentNext(fromViewController: self) {
            hasEverPresentedExperienceUpgrade = true
        } else if !hasEverAppeared {
            presentGetStartedBannerIfNecessary()
        }

        // Whether or not the theme has changed, always ensure
        // the right theme is applied. The initial collapsed
        // state of the split view controller is determined between
        // `viewWillAppear` and `viewDidAppear`, so this is the soonest
        // we can know the right thing to display.
        applyTheme()

        requestReviewIfAppropriate()

        searchResultsController.viewDidAppear(animated)

        showBadgeExpirationSheetIfNeeded()

        hasEverAppeared = true
        if viewState.multiSelectState.isActive {
            showToolbar()
        } else {
            applyDefaultBackButton()
        }
        tableDataSource.updateAndSetRefreshTimer()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        leaveMultiselectMode()
        tableDataSource.stopRefreshTimer()

        super.viewWillDisappear(animated)

        isViewVisible = false
        searchResultsController.viewWillDisappear(animated)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        InstrumentsMonitor.trackEvent(name: "ChatListViewController.viewDidDisappear")

        super.viewDidDisappear(animated)

        searchResultsController.viewDidDisappear(animated)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        var contentInset = UIEdgeInsets.zero
        if let getStartedBanner, getStartedBanner.isViewLoaded, !getStartedBanner.view.isHidden {
            contentInset.bottom = getStartedBanner.opaqueHeight
        }
        if tableView.contentInset != contentInset {
            UIView.animate(withDuration: 0.25) {
                self.tableView.contentInset = contentInset
            }
        }
    }

    // MARK: Theme

    public override func themeDidChange() {
        super.themeDidChange()

        applyTheme()
        reloadTableDataAndResetCellContentCache()
        applyThemeToContextMenuAndToolbar()
    }

    private func applyTheme() {
        view.backgroundColor = Theme.backgroundColor
        tableView.backgroundColor = Theme.backgroundColor
        updateBarButtonItems()
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        guard isViewLoaded else { return }

        // There is a subtle difference in when the split view controller
        // transitions between collapsed and expanded state on iPad vs
        // when it does on iPhone. We reloadData here in order to ensure
        // the background color of all of our cells is updated to reflect
        // the current state, so it's important that we're only doing this
        // once the state is ready, otherwise there will be a flash of the
        // wrong background color. For iPad, this moment is _before_ the
        // transition occurs. For iPhone, this moment is _during_ the
        // transition. We reload in the right places accordingly.
        if UIDevice.current.isIPad {
            reloadTableDataAndResetCellContentCache()
        }

        coordinator.animate { context in
            self.applyTheme()

            if !UIDevice.current.isIPad {
                self.reloadTableDataAndResetCellContentCache()
            }

            // The Get Started banner will occupy most of the screen in landscape
            // If we're transitioning to landscape, fade out the view (if it exists)
            if let getStartedBanner = self.getStartedBanner, getStartedBanner.isViewLoaded {
                if size.width > size.height {
                    getStartedBanner.view.alpha = 0
                } else {
                    getStartedBanner.view.alpha = 1
                }
            }
        }
    }

    // MARK: UI Components

    private lazy var emptyInboxView: UIView = {
        let emptyInboxLabel = UILabel()
        emptyInboxLabel.text = NSLocalizedString(
            "INBOX_VIEW_EMPTY_INBOX",
            comment: "Message shown in the conversation list when the inbox is empty."
        )
        emptyInboxLabel.font = .dynamicTypeSubheadlineClamped
        emptyInboxLabel.textColor
            = Theme.isDarkThemeEnabled ? Theme.darkThemeSecondaryTextAndIconColor : UIColor.ows_gray45
        emptyInboxLabel.textAlignment = .center
        emptyInboxLabel.numberOfLines = 0
        emptyInboxLabel.lineBreakMode = .byWordWrapping
        emptyInboxLabel.accessibilityIdentifier = "ChatListViewController.emptyInboxView"
        return emptyInboxLabel
    }()

    private lazy var firstConversationLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .dynamicTypeBodyClamped
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.accessibilityIdentifier = "ChatListViewController.firstConversationLabel"
        return label
    }()

    lazy var firstConversationCueView: UIView = {
        let kTailWidth: CGFloat = 16
        let kTailHeight: CGFloat = 8
        let kTailHMargin: CGFloat = 12

        let layerView = OWSLayerView()
        layerView.isUserInteractionEnabled = true
        layerView.accessibilityIdentifier = "ChatListViewController.firstConversationCueView"
        layerView.layoutMargins = UIEdgeInsets(top: 11 + kTailHeight, leading: 16, bottom: 11, trailing: 16)

        let shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = UIColor.ows_accentBlue.cgColor
        layerView.layer.addSublayer(shapeLayer)
        layerView.layoutCallback = { view in
            let bezierPath = UIBezierPath()

            // Bubble
            var bubbleBounds = view.bounds
            bubbleBounds.origin.y += kTailHeight
            bubbleBounds.size.height -= kTailHeight
            bezierPath.append(UIBezierPath(roundedRect: bubbleBounds, cornerRadius: 9))

            // Tail
            var tailTop = CGPoint(x: kTailHMargin + kTailWidth * 0.5, y: 0)
            var tailLeft = CGPoint(x: kTailHMargin, y: kTailHeight)
            var tailRight = CGPoint(x: kTailHMargin + kTailWidth, y: kTailHeight)
            if !CurrentAppContext().isRTL {
                tailTop.x = view.width - tailTop.x
                tailLeft.x = view.width - tailLeft.x
                tailRight.x = view.width - tailRight.x
            }
            bezierPath.move(to: tailTop)
            bezierPath.addLine(to: tailLeft)
            bezierPath.addLine(to: tailRight)
            bezierPath.addLine(to: tailTop)
            shapeLayer.path = bezierPath.cgPath
            shapeLayer.frame = view.bounds
        }

        layerView.addSubview(firstConversationLabel)
        firstConversationLabel.autoPinEdgesToSuperviewMargins()

        layerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(firstConversationCueWasTapped)))

        return layerView
    }()

    private lazy var settingsBarButtonItem: UIBarButtonItem = {
        let contextButton = ContextMenuButton()
        contextButton.showsContextMenuAsPrimaryAction = true
        contextButton.contextMenu = settingsContextMenu()
        contextButton.accessibilityLabel = CommonStrings.openSettingsButton

        let avatarImageView = createAvatarBarButtonViewWithSneakyTransaction()
        contextButton.addSubview(avatarImageView)
        avatarImageView.autoPinEdgesToSuperviewEdges()

        let wrapper = UIView.container()
        wrapper.addSubview(contextButton)
        contextButton.autoPinEdgesToSuperviewEdges()

        if unreadPaymentNotificationsCount > 0 {
            PaymentsViewUtils.addUnreadBadge(toView: wrapper)
        }

        return .init(customView: wrapper)
    }()

    // MARK: Table View

    func reloadTableDataAndResetCellContentCache() {
        AssertIsOnMainThread()

        cellContentCache.clear()
        conversationCellHeightCache = nil
        reloadTableData()
    }

    func reloadTableData() {
        AssertIsOnMainThread()
        InstrumentsMonitor.measure(category: "runtime", parent: "ChatListViewController", name: "reloadTableData") {
            var selectedThreadIds: Set<String> = []
            for indexPath in tableView.indexPathsForSelectedRows ?? [] {
                if let key = tableDataSource.thread(forIndexPath: indexPath, expectsSuccess: false)?.uniqueId {
                    selectedThreadIds.insert(key)
                }
            }

            tableView.reloadData()

            if !selectedThreadIds.isEmpty {
                var threadIdsToBeSelected = selectedThreadIds
                for section in 0..<tableDataSource.numberOfSections(in: tableView) {
                    for row in 0..<tableDataSource.tableView(tableView, numberOfRowsInSection: section) {
                        let indexPath = IndexPath(row: row, section: section)
                        if let key = tableDataSource.thread(forIndexPath: indexPath, expectsSuccess: false)?.uniqueId, threadIdsToBeSelected.contains(key) {
                            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
                            threadIdsToBeSelected.remove(key)
                            if threadIdsToBeSelected.isEmpty {
                                return
                            }
                        }
                    }
                }
            }
        }
    }

    func updateCellVisibility() {
        AssertIsOnMainThread()

        for cell in tableView.visibleCells {
            guard let cell = cell as? ChatListCell else {
                continue
            }
            updateCellVisibility(cell: cell, isCellVisible: true)
        }
    }

    func updateCellVisibility(cell: ChatListCell, isCellVisible: Bool) {
        AssertIsOnMainThread()

        cell.isCellVisible = isViewVisible && isCellVisible
    }

    private func ensureCellAnimations() {
        AssertIsOnMainThread()

        for cell in tableView.visibleCells {
            guard let cell = cell as? ChatListCell else {
                continue
            }
            cell.ensureCellAnimations()
        }
    }

    // MARK: UI Helpers

    private var inviteFlow: InviteFlow?

    private var getStartedBanner: GetStartedBannerViewController?

    private var hasEverPresentedExperienceUpgrade = false

    var lastViewedThread: TSThread?

    @objc
    func updateBarButtonItems() {
        guard chatListMode == .inbox && !viewState.multiSelectState.isActive else { return }

        // Settings button.
        navigationItem.leftBarButtonItem = settingsBarButtonItem
        settingsBarButtonItem.accessibilityLabel = CommonStrings.openSettingsButton
        settingsBarButtonItem.accessibilityIdentifier = "ChatListViewController.settingsButton"

        var rightBarButtonItems = [UIBarButtonItem]()

        let compose = UIBarButtonItem(
            image: Theme.iconImage(.compose24),
            style: .plain,
            target: self,
            action: #selector(showNewConversationView),
            accessibilityIdentifier: "ChatListViewController.compose"
        )
        compose.accessibilityLabel = NSLocalizedString("COMPOSE_BUTTON_LABEL", comment: "Accessibility label from compose button.")
        compose.accessibilityHint = NSLocalizedString(
            "COMPOSE_BUTTON_HINT",
            comment: "Accessibility hint describing what you can do with the compose button"
        )
        rightBarButtonItems.append(compose)

        let camera = UIBarButtonItem(
            image: Theme.iconImage(.cameraButton),
            style: .plain,
            target: self,
            action: #selector(showCameraView),
            accessibilityIdentifier: "ChatListViewController.camera"
        )
        camera.accessibilityLabel = NSLocalizedString("CAMERA_BUTTON_LABEL", comment: "Accessibility label for camera button.")
        camera.accessibilityHint = NSLocalizedString(
            "CAMERA_BUTTON_HINT",
            comment: "Accessibility hint describing what you can do with the camera button"
        )
        rightBarButtonItems.append(camera)

        if SignalProxy.isEnabled {
            let proxyStatusImage: UIImage?
            let tintColor: UIColor
            switch socketManager.socketState(forType: .identified) {
            case .open:
                proxyStatusImage = UIImage(named: "proxy_connected_24")
                tintColor = UIColor.ows_accentGreen

            case .closed:
                proxyStatusImage = UIImage(named: "proxy_failed_24")
                tintColor = UIColor.ows_accentRed

            case .connecting:
                proxyStatusImage = UIImage(named: "proxy_failed_24")
                tintColor = UIColor.ows_middleGray
            }

            let proxy = UIBarButtonItem(
                image: proxyStatusImage,
                style: .plain,
                target: self,
                action: #selector(showAppSettingsInProxyMode)
            )
            proxy.tintColor = tintColor
            rightBarButtonItems.append(proxy)
        }

        navigationItem.rightBarButtonItems = rightBarButtonItems
    }

    @objc
    func showNewConversationView() {
        AssertIsOnMainThread()

        Logger.info("")

        // Dismiss any message actions if they're presented
        conversationSplitViewController?.selectedConversationViewController?.dismissMessageContextMenu(animated: true)

        let viewController = ComposeViewController()
        contactsManagerImpl.requestSystemContactsOnce { error in
            if let error {
                Logger.error("Error when requesting contacts: \(error)")
            }

            // Even if there is an error fetching contacts we proceed to the next screen.
            // As the compose view will present the proper thing depending on contact access.
            //
            // We just want to make sure contact access is *complete* before showing the compose
            // screen to avoid flicker.
            let modal = OWSNavigationController(rootViewController: viewController)
            self.navigationController?.presentFormSheet(modal, animated: true)
        }
    }

    func showNewGroupView() {
        AssertIsOnMainThread()

        Logger.info("")

        // Dismiss any message actions if they're presented
        conversationSplitViewController?.selectedConversationViewController?.dismissMessageContextMenu(animated: true)

        let newGroupViewController = NewGroupMembersViewController()
        contactsManagerImpl.requestSystemContactsOnce { error in
            if let error {
                Logger.error("Error when requesting contacts: \(error)")
            }

            // Even if there is an error fetching contacts we proceed to the next screen.
            // As the compose view will present the proper thing depending on contact access.
            //
            // We just want to make sure contact access is *complete* before showing the compose
            // screen to avoid flicker.
            let modal = OWSNavigationController(rootViewController: newGroupViewController)
            self.navigationController?.presentFormSheet(modal, animated: true)
        }
    }

    @objc
    private func firstConversationCueWasTapped(_ gestureRecognizer: UITapGestureRecognizer) {
        Logger.info("")

        showNewConversationView()
    }

    private func addPullToRefreshIfNeeded() {
        if tsAccountManager.isPrimaryDevice {
            return
        }

        let pullToRefreshView = UIRefreshControl()
        pullToRefreshView.tintColor = .gray
        pullToRefreshView.addTarget(self, action: #selector(pullToRefreshPerformed), for: .valueChanged)
        pullToRefreshView.accessibilityIdentifier = "ChatListViewController.pullToRefreshView"
        tableView.refreshControl = pullToRefreshView
    }

    @objc
    private func pullToRefreshPerformed(_ refreshControl: UIRefreshControl) {
        AssertIsOnMainThread()
        owsAssert(!tsAccountManager.isPrimaryDevice)

        syncManager.sendAllSyncRequestMessages(timeout: 20).ensure {
            refreshControl.endRefreshing()
        }.cauterize()
    }

    private func applyDefaultBackButton() {
        AssertIsOnMainThread()

        // We don't show any text for the back button, so there's no need to localize it. But because we left align the
        // conversation title view, we add a little tappable padding after the back button, by having a title of spaces.
        // Admittedly this is kind of a hack and not super fine grained, but it's simple and results in the interactive pop
        // gesture animating our title view nicely vs. creating our own back button bar item with custom padding, which does
        // not properly animate with the "swipe to go back" or "swipe left for info" gestures.
        let paddingLength: Int = 3
        let paddingString = "".padding(toLength: paddingLength, withPad: " ", startingAt: 0)

        navigationItem.backBarButtonItem = UIBarButtonItem(title: paddingString,
                                                           style: .plain,
                                                           target: nil,
                                                           action: nil,
                                                           accessibilityIdentifier: "back")
    }

    // We want to delay asking for a review until an opportune time.
    // If the user has *just* launched Signal they intend to do something, we don't want to interrupt them.

    private static var callCount: UInt = 0
    private static var reviewRequested = false

    func requestReviewIfAppropriate() {
        Self.callCount += 1

        if hasEverAppeared && Self.callCount > 25 {
            Logger.debug("requesting review")
            // In Debug this pops up *every* time, which is helpful, but annoying.
            // In Production this will pop up at most 3 times per 365 days.
    #if !DEBUG
            if !Self.reviewRequested {
                // Despite `SKStoreReviewController` docs, some people have reported seeing the "request review" prompt
                // repeatedly after first installation. Let's make sure it only happens at most once per launch.
                SKStoreReviewController.requestReview()
                Self.reviewRequested = true
            }
    #endif
        } else {
            Logger.debug("not requesting review")
        }
    }

    // MARK: View State

    let viewState = CLVViewState()

    private func shouldShowFirstConversationCue() -> Bool {
        let hasSavedThread = databaseStorage.read { transaction in
            return SSKPreferences.hasSavedThread(transaction: transaction)
        }
        return shouldShowEmptyInboxView && !hasSavedThread
    }

    private var shouldShowEmptyInboxView: Bool {
        return chatListMode == .inbox && numberOfInboxThreads == 0 && numberOfArchivedThreads == 0
    }

    func updateViewState() {
        if shouldShowEmptyInboxView {
            tableView.isHidden = true
            emptyInboxView.isHidden = false
            if shouldShowFirstConversationCue() {
                firstConversationCueView.isHidden = false
                updateFirstConversationLabel()
            } else {
                firstConversationCueView.isHidden = true
            }
        } else {
            tableView.isHidden = false
            emptyInboxView.isHidden = true
            firstConversationCueView.isHidden = true
        }
    }

    // MARK: Badge Expiration

    private var hasShownBadgeExpiration = false

    func showBadgeExpirationSheetIfNeeded() {
        Logger.info("[Donations] Checking whether we should show badge expiration sheet...")

        guard !hasShownBadgeExpiration else { // Do this once per launch
            Logger.info("[Donations] Not showing badge expiration sheet, because we've already done so")
            return
        }

        let (
            expiredBadgeID,
            shouldShowExpirySheet,
            mostRecentSubscriptionBadgeChargeFailure,
            mostRecentSubscriptionPaymentMethod,
            hasCurrentSubscription
        ) = databaseStorage.read { transaction in (
            SubscriptionManagerImpl.mostRecentlyExpiredBadgeID(transaction: transaction),
            SubscriptionManagerImpl.showExpirySheetOnHomeScreenKey(transaction: transaction),
            SubscriptionManagerImpl.getMostRecentSubscriptionBadgeChargeFailure(transaction: transaction),
            SubscriptionManagerImpl.getMostRecentSubscriptionPaymentMethod(transaction: transaction),
            subscriptionManager.hasCurrentSubscription(transaction: transaction)
        )}

        guard let expiredBadgeID = expiredBadgeID else {
            Logger.info("[Donations] No expired badge ID, not showing sheet")
            return
        }

        guard shouldShowExpirySheet else {
            Logger.info("[Donations] Not showing badge expiration sheet because the flag is off")
            return
        }

        Logger.info("[Donations] showing expiry sheet for expired badge \(expiredBadgeID)")

        if BoostBadgeIds.contains(expiredBadgeID) {
            firstly {
                SubscriptionManagerImpl.getBoostBadge()
            }.done(on: DispatchQueue.global()) { boostBadge in
                firstly {
                    self.profileManager.badgeStore.populateAssetsOnBadge(boostBadge)
                }.done(on: DispatchQueue.main) {
                    // Make sure we're still the active VC
                    guard UIApplication.shared.frontmostViewController == self.conversationSplitViewController,
                          self.conversationSplitViewController?.selectedThread == nil else { return }

                    let badgeSheet = BadgeExpirationSheet(badge: boostBadge,
                                                          mode: .boostExpired(hasCurrentSubscription: hasCurrentSubscription))
                    badgeSheet.delegate = self
                    self.present(badgeSheet, animated: true)
                    self.hasShownBadgeExpiration = true
                    self.databaseStorage.write { transaction in
                        SubscriptionManagerImpl.setShowExpirySheetOnHomeScreenKey(show: false, transaction: transaction)
                    }
                }.catch { error in
                    owsFailDebug("Failed to fetch boost badge assets for expiry \(error)")
                }
            }.catch { error in
                owsFailDebug("Failed to fetch boost badge for expiry \(error)")
            }
        } else if SubscriptionBadgeIds.contains(expiredBadgeID) {
            // Fetch current subscriptions, required to populate badge assets
            firstly { () -> Promise<SubscriptionManagerImpl.DonationConfiguration> in
                SubscriptionManagerImpl.fetchDonationConfiguration()
            }.map(on: DispatchQueue.global()) { donationConfiguration -> [SubscriptionLevel] in
                donationConfiguration.subscription.levels
            }.done(on: DispatchQueue.global()) { (subscriptions: [SubscriptionLevel]) in
                let subscriptionLevel = subscriptions.first { $0.badge.id == expiredBadgeID }
                guard let subscriptionLevel = subscriptionLevel else {
                    owsFailDebug("Unable to find matching subscription level for expired badge")
                    return
                }

                firstly {
                    self.profileManager.badgeStore.populateAssetsOnBadge(subscriptionLevel.badge)
                }.done(on: DispatchQueue.main) {
                    // Make sure we're still the active VC
                    guard UIApplication.shared.frontmostViewController == self.conversationSplitViewController,
                          self.conversationSplitViewController?.selectedThread == nil else { return }

                    let mode: BadgeExpirationSheetState.Mode
                    if let mostRecentSubscriptionBadgeChargeFailure = mostRecentSubscriptionBadgeChargeFailure {
                        mode = .subscriptionExpiredBecauseOfChargeFailure(
                            chargeFailure: mostRecentSubscriptionBadgeChargeFailure,
                            paymentMethod: mostRecentSubscriptionPaymentMethod
                        )
                    } else {
                        mode = .subscriptionExpiredBecauseNotRenewed
                    }
                    let badgeSheet = BadgeExpirationSheet(badge: subscriptionLevel.badge, mode: mode)
                    badgeSheet.delegate = self
                    self.present(badgeSheet, animated: true)
                    self.hasShownBadgeExpiration = true
                    self.databaseStorage.write { transaction in
                        SubscriptionManagerImpl.setShowExpirySheetOnHomeScreenKey(show: false, transaction: transaction)
                    }
                }.catch { error in
                    owsFailDebug("Failed to fetch subscription badge assets for expiry \(error)")
                }

            }.catch { error in
                owsFailDebug("Failed to fetch subscriptions for expiry \(error)")
            }
        }
    }

    // MARK: Payments

    func configureUnreadPaymentsBannerSingle(_ paymentsReminderView: UIView,
                                             paymentModel: TSPaymentModel,
                                             transaction: SDSAnyReadTransaction) {

        guard paymentModel.isIncoming,
              !paymentModel.isUnidentified,
              let address = paymentModel.address,
              let paymentAmount = paymentModel.paymentAmount,
              paymentAmount.isValid else {
            configureUnreadPaymentsBannerMultiple(paymentsReminderView, unreadCount: 1)
            return
        }
        guard nil != TSContactThread.getWithContactAddress(address, transaction: transaction) else {
            configureUnreadPaymentsBannerMultiple(paymentsReminderView, unreadCount: 1)
            return
        }

        let userName = contactsManager.shortDisplayName(for: address, transaction: transaction)
        let formattedAmount = PaymentsFormat.format(paymentAmount: paymentAmount,
                                                    isShortForm: true,
                                                    withCurrencyCode: true,
                                                    withSpace: true)
        let format = OWSLocalizedString("PAYMENTS_NOTIFICATION_BANNER_1_WITH_DETAILS_FORMAT",
                                       comment: "Format for the payments notification banner for a single payment notification with details. Embeds: {{ %1$@ the name of the user who sent you the payment, %2$@ the amount of the payment }}.")
        let title = String(format: format, userName, formattedAmount)

        let avatarView = ConversationAvatarView(sizeClass: .customDiameter(Self.paymentsBannerAvatarSize), localUserDisplayMode: .asUser)
        avatarView.update(transaction) { config in
            config.dataSource = .address(address)
        }

        let paymentsHistoryItem = PaymentsHistoryItem(paymentModel: paymentModel,
                                                      displayName: userName)

        configureUnreadPaymentsBanner(paymentsReminderView,
                                      title: title,
                                      avatarView: avatarView) { [weak self] in
            self?.showAppSettings(mode: .payment(paymentsHistoryItem: paymentsHistoryItem))
        }
    }

    func configureUnreadPaymentsBannerMultiple(_ paymentsReminderView: UIView,
                                               unreadCount: UInt) {
        let title: String
        if unreadCount == 1 {
            title = OWSLocalizedString("PAYMENTS_NOTIFICATION_BANNER_1",
                                      comment: "Label for the payments notification banner for a single payment notification.")
        } else {
            let format = OWSLocalizedString("PAYMENTS_NOTIFICATION_BANNER_N_FORMAT",
                                           comment: "Format for the payments notification banner for multiple payment notifications. Embeds: {{ the number of unread payment notifications }}.")
            title = String(format: format, OWSFormat.formatUInt(unreadCount))
        }

        let iconView = UIImageView.withTemplateImageName(Theme.iconName(.paymentNotification),
                                                         tintColor: (Theme.isDarkThemeEnabled
                                                                        ? .ows_gray15
                                                                        : .ows_white))
        iconView.autoSetDimensions(to: .square(24))
        let iconCircleView = OWSLayerView.circleView(size: CGFloat(Self.paymentsBannerAvatarSize))
        iconCircleView.backgroundColor = (Theme.isDarkThemeEnabled
                                            ? .ows_gray80
                                            : .ows_gray95)
        iconCircleView.addSubview(iconView)
        iconView.autoCenterInSuperview()

        configureUnreadPaymentsBanner(paymentsReminderView,
                                      title: title,
                                      avatarView: iconCircleView) { [weak self] in
            self?.showAppSettings(mode: .payments)
        }
    }

    private static let paymentsBannerAvatarSize: UInt = 40

    private class PaymentsBannerView: UIView {
        let block: () -> Void

        required init(block: @escaping () -> Void) {
            self.block = block

            super.init(frame: .zero)

            isUserInteractionEnabled = true
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc
        func didTap() {
            block()
        }
    }

    private func configureUnreadPaymentsBanner(_ paymentsReminderView: UIView,
                                               title: String,
                                               avatarView: UIView,
                                               block: @escaping () -> Void) {
        paymentsReminderView.removeAllSubviews()

        let paymentsBannerView = PaymentsBannerView(block: block)
        paymentsReminderView.addSubview(paymentsBannerView)
        paymentsBannerView.autoPinEdgesToSuperviewEdges()

        if UIDevice.current.isIPad {
            paymentsReminderView.backgroundColor = (Theme.isDarkThemeEnabled
                                                        ? .ows_gray75
                                                        : .ows_gray05)
        } else {
            paymentsReminderView.backgroundColor = (Theme.isDarkThemeEnabled
                                                        ? .ows_gray90
                                                        : .ows_gray02)
        }

        avatarView.setCompressionResistanceHigh()
        avatarView.setContentHuggingHigh()

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = UIFont.dynamicTypeSubheadlineClamped.semibold()

        let viewLabel = UILabel()
        viewLabel.text = CommonStrings.viewButton
        viewLabel.textColor = Theme.accentBlueColor
        viewLabel.font = UIFont.dynamicTypeSubheadlineClamped

        let textStack = UIStackView(arrangedSubviews: [ titleLabel, viewLabel ])
        textStack.axis = .vertical
        textStack.alignment = .leading

        let dismissButton = OWSLayerView.circleView(size: 20)
        dismissButton.backgroundColor = (Theme.isDarkThemeEnabled
                                            ? .ows_gray65
                                            : .ows_gray05)
        dismissButton.setCompressionResistanceHigh()
        dismissButton.setContentHuggingHigh()

        let dismissIcon = UIImageView.withTemplateImageName("x-16",
                                                            tintColor: (Theme.isDarkThemeEnabled
                                                                            ? .ows_white
                                                                            : .ows_gray60))
        dismissIcon.autoSetDimensions(to: .square(16))
        dismissButton.addSubview(dismissIcon)
        dismissIcon.autoCenterInSuperview()

        let stack = UIStackView(arrangedSubviews: [ avatarView,
                                                    textStack,
                                                    dismissButton ])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.layoutMargins = UIEdgeInsets(
            top: OWSTableViewController2.cellVInnerMargin,
            left: OWSTableViewController2.cellHOuterLeftMargin(in: view),
            bottom: OWSTableViewController2.cellVInnerMargin,
            right: OWSTableViewController2.cellHOuterRightMargin(in: view)
        )
        stack.isLayoutMarginsRelativeArrangement = true
        paymentsBannerView.addSubview(stack)
        stack.autoPinEdgesToSuperviewEdges()
    }
}

// MARK: Settings Button

extension ChatListViewController {

    enum ShowAppSettingsMode {
        case none
        case payments
        case payment(paymentsHistoryItem: PaymentsHistoryItem)
        case paymentsTransferIn
        case appearance
        case avatarBuilder
        case donate(donateMode: DonateViewController.DonateMode)
        case proxy
    }

    func createAvatarBarButtonViewWithSneakyTransaction() -> UIView {
        let avatarView = ConversationAvatarView(sizeClass: .twentyEight, localUserDisplayMode: .asUser)
        databaseStorage.read { readTx in
            avatarView.update(readTx) { config in
                if let address = tsAccountManager.localAddress(with: readTx) {
                    config.dataSource = .address(address)
                    config.applyConfigurationSynchronously()
                }
            }
        }
        return avatarView
    }

    func settingsContextMenu() -> ContextMenu {
        var contextMenuActions: [ContextMenuAction] = []
        if renderState.inboxCount > 0 {
            contextMenuActions.append(
                ContextMenuAction(
                    title: OWSLocalizedString("HOME_VIEW_TITLE_SELECT_CHATS", comment: "Title for the 'Select Chats' option in the ChatList."),
                    image: Theme.isDarkThemeEnabled ? UIImage(named: "check-circle-solid-24")?.tintedImage(color: .white) : UIImage(named: "check-circle-outline-24"),
                    attributes: [],
                    handler: { [weak self] (_) in
                        self?.willEnterMultiselectMode()
                    }))
        }
        contextMenuActions.append(
            ContextMenuAction(
                title: CommonStrings.openSettingsButton,
                image: Theme.isDarkThemeEnabled ? UIImage(named: "settings-solid-24")?.tintedImage(color: .white) : UIImage(named: "settings-outline-24"),
                attributes: [],
                handler: { [weak self] (_) in
                        self?.showAppSettings(mode: .none)
            }))
        if renderState.archiveCount > 0 {
            contextMenuActions.append(
                ContextMenuAction(
                    title: OWSLocalizedString("HOME_VIEW_TITLE_ARCHIVE", comment: "Title for the conversation list's 'archive' mode."),
                    image: Theme.isDarkThemeEnabled ? UIImage(named: "archive-solid-24")?.tintedImage(color: .white) : UIImage(named: "archive-outline-24"),
                    attributes: [],
                    handler: { [weak self] (_) in
                        self?.showArchivedConversations(offerMultiSelectMode: true)
                }))
        }
        return .init(contextMenuActions)
    }

    func showAppSettings() {
        showAppSettings(mode: .none)
    }

    func showAppSettingsInAppearanceMode() {
        showAppSettings(mode: .appearance)
    }

    @objc
    func showAppSettingsInProxyMode() {
        showAppSettings(mode: .proxy)
    }

    func showAppSettingsInAvatarBuilderMode() {
        showAppSettings(mode: .avatarBuilder)
    }

    func showAppSettings(mode: ShowAppSettingsMode) {
        AssertIsOnMainThread()

        Logger.info("")

        // Dismiss any message actions if they're presented
            conversationSplitViewController?.selectedConversationViewController?.dismissMessageContextMenu(animated: true)

        let navigationController = AppSettingsViewController.inModalNavigationController()

        var completion: (() -> Void)?

        var viewControllers = navigationController.viewControllers
        switch mode {
        case .none:
            break
        case .payments:
            let paymentsSettings = PaymentsSettingsViewController(mode: .inAppSettings)
            viewControllers += [ paymentsSettings ]
        case .payment(let paymentsHistoryItem):
            let paymentsSettings = PaymentsSettingsViewController(mode: .inAppSettings)
            let paymentsDetail = PaymentsDetailViewController(paymentItem: paymentsHistoryItem)
            viewControllers += [ paymentsSettings, paymentsDetail ]
        case .paymentsTransferIn:
            let paymentsSettings = PaymentsSettingsViewController(mode: .inAppSettings)
            let paymentsTransferIn = PaymentsTransferInViewController()
            viewControllers += [ paymentsSettings, paymentsTransferIn ]
        case .appearance:
            let appearance = AppearanceSettingsTableViewController()
            viewControllers += [ appearance ]
        case .avatarBuilder:
            let profile = ProfileSettingsViewController()
            viewControllers += [ profile ]
            completion = { profile.presentAvatarSettingsView() }
        case let .donate(donateMode):
            guard DonationUtilities.canDonate(
                inMode: donateMode.asDonationMode,
                localNumber: tsAccountManager.localNumber
            ) else {
                DonationViewsUtil.openDonateWebsite()
                return
            }

            let donate = DonateViewController(preferredDonateMode: donateMode) { [weak self] finishResult in
                switch finishResult {
                case let .completedDonation(donateSheet, thanksSheet):
                    donateSheet.dismiss(animated: true) { [weak self] in
                        self?.present(thanksSheet, animated: true)
                    }
                case let .monthlySubscriptionCancelled(donateSheet, toastText):
                    donateSheet.dismiss(animated: true) { [weak self] in
                        guard let self = self else { return }
                        self.view.presentToast(text: toastText, fromViewController: self)
                    }
                }
            }
            viewControllers += [donate]
        case .proxy:
            viewControllers += [ PrivacySettingsViewController(), AdvancedPrivacySettingsViewController(), ProxySettingsViewController() ]
        }
        navigationController.setViewControllers(viewControllers, animated: false)
        presentFormSheet(navigationController, animated: true, completion: completion)
    }
}

extension ChatListViewController: BadgeExpirationSheetDelegate {

    func badgeExpirationSheetActionTapped(_ action: BadgeExpirationSheetAction) {
        switch action {
        case .dismiss:
            break
        case .openDonationView:
            showAppSettings(mode: .donate(donateMode: .oneTime))
        }
    }
}

extension ChatListViewController: ThreadSwipeHandler {

    func updateUIAfterSwipeAction() {
        updateViewState()
    }
}

extension ChatListViewController: GetStartedBannerViewControllerDelegate {

    func presentGetStartedBannerIfNecessary() {
        guard getStartedBanner == nil && chatListMode == .inbox else { return }

        let getStartedVC = GetStartedBannerViewController(delegate: self)
        if getStartedVC.hasIncompleteCards {
            getStartedBanner = getStartedVC

            addChild(getStartedVC)
            view.addSubview(getStartedVC.view)
            getStartedVC.view.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)

            // If we're in landscape, the banner covers most of the screen
            // Hide it until we transition to portrait
            if view.bounds.width > view.bounds.height {
                getStartedVC.view.alpha = 0
            }
        }
    }

    func getStartedBannerDidTapInviteFriends(_ banner: GetStartedBannerViewController) {
        inviteFlow = InviteFlow(presentingViewController: self)
        inviteFlow?.present(isAnimated: true, completion: nil)
    }

    func getStartedBannerDidTapCreateGroup(_ banner: GetStartedBannerViewController) {
        showNewGroupView()
    }

    func getStartedBannerDidTapAppearance(_ banner: GetStartedBannerViewController) {
        showAppSettingsInAppearanceMode()
    }

    func getStartedBannerDidDismissAllCards(_ banner: GetStartedBannerViewController, animated: Bool) {
        let dismissBlock = {
            banner.view.removeFromSuperview()
            banner.removeFromParent()
            self.getStartedBanner = nil
        }

        if animated {
            banner.view.setIsHidden(true, withAnimationDuration: 0.5) { _ in
                dismissBlock()
            }
        } else {
            dismissBlock()
        }
    }

    func getStartedBannerDidTapAvatarBuilder(_ banner: GetStartedBannerViewController) {
        showAppSettingsInAvatarBuilderMode()
    }
}

// MARK: - First conversation label

extension ChatListViewController {

    func updateFirstConversationLabel() {
        let signalAccounts = suggestedAccountsForFirstContact(maxCount: 3)

        var contactNames = databaseStorage.read { transaction in
            signalAccounts.map { account in
                self.contactsManager.displayName(for: account.recipientAddress, transaction: transaction)
            }
        }

        let formatString = { () -> String in
            switch contactNames.count {
            case 0:
                return OWSLocalizedString(
                    "HOME_VIEW_FIRST_CONVERSATION_OFFER_NO_CONTACTS",
                    comment: "A label offering to start a new conversation with your contacts, if you have no Signal contacts."
                )
            case 1:
                return OWSLocalizedString(
                    "HOME_VIEW_FIRST_CONVERSATION_OFFER_1_CONTACT_FORMAT",
                    comment: "Format string for a label offering to start a new conversation with your contacts, if you have 1 Signal contact.  Embeds {{The name of 1 of your Signal contacts}}."
                )
            case 2:
                return OWSLocalizedString(
                    "HOME_VIEW_FIRST_CONVERSATION_OFFER_2_CONTACTS_FORMAT",
                    comment: "Format string for a label offering to start a new conversation with your contacts, if you have 2 Signal contacts.  Embeds {{The names of 2 of your Signal contacts}}."
                )
            case 3:
                break
            default:
                owsFailDebug("Unexpectedly had \(contactNames.count) names, expected at most 3!")
                contactNames = Array(contactNames.prefix(3))
            }

            return OWSLocalizedString(
                "HOME_VIEW_FIRST_CONVERSATION_OFFER_3_CONTACTS_FORMAT",
                comment: "Format string for a label offering to start a new conversation with your contacts, if you have at least 3 Signal contacts.  Embeds {{The names of 3 of your Signal contacts}}."
            )
        }()

        let attributedString = NSAttributedString.make(
            fromFormat: formatString,
            attributedFormatArgs: contactNames.map { name in
                return .string(name, attributes: [.font: firstConversationLabel.font.semibold()])
            }
        )

        firstConversationLabel.attributedText = attributedString
    }

    private func suggestedAccountsForFirstContact(maxCount: Int) -> [SignalAccount] {
        return Array(contactsViewHelper.signalAccounts(includingLocalUser: false).prefix(maxCount))
    }
}
