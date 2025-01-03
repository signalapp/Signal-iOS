//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI
import StoreKit

public class ChatListViewController: OWSViewController, HomeTabViewController {
    let appReadiness: AppReadinessSetter

    init(
        chatListMode: ChatListMode,
        appReadiness: AppReadinessSetter
    ) {
        self.appReadiness = appReadiness
        self.viewState = CLVViewState(chatListMode: chatListMode, inboxFilter: nil)

        super.init()

        tableDataSource.scrollViewDelegate = self
        tableDataSource.viewController = self
        loadCoordinator.viewController = self
        reminderViews.chatListViewController = self
        viewState.settingsButtonCreator.delegate = self
        viewState.proxyButtonCreator.delegate = self
        viewState.configure()
    }

    public override var canBecomeFirstResponder: Bool {
        true
    }

    // MARK: View Lifecycle

    public override func loadView() {
        view = containerView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        keyboardObservationBehavior = .never

        switch viewState.chatListMode {
        case .inbox:
            title = NSLocalizedString("CHAT_LIST_TITLE_INBOX", comment: "Title for the chat list's default mode.")
        case .archive:
            title = NSLocalizedString("HOME_VIEW_TITLE_ARCHIVE", comment: "Title for the conversation list's 'archive' mode.")
        }

        if !viewState.multiSelectState.isActive {
            applyDefaultBackButton()
        }

        // Table View
        tableView.accessibilityIdentifier = "ChatListViewController.tableView"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.allowsSelectionDuringEditing = true
        tableView.allowsMultipleSelectionDuringEditing = true

        if let filterControl {
            filterControl.clearAction = .disableChatListFilter(target: self)
            filterControl.delegate = self
        }

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
        navigationItem.searchController = viewState.searchController
        viewState.searchController.searchResultsUpdater = self
        searchResultsController.delegate = self

        updateBarButtonItems()
        updateReminderViews()
        applyTheme()
        observeNotifications()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        defer {
            loadCoordinator.loadIfNecessary(suppressAnimations: true)
        }

        isViewVisible = true

        // Ensure the tabBar is always hidden if we're in the archive.
        let shouldHideTabBar = viewState.chatListMode == .archive
        if shouldHideTabBar {
            tabBarController?.tabBar.isHidden = true
            extendedLayoutIncludesOpaqueBars = true
        }

        if isSearching {
            scrollSearchBarToTop(animated: false)
        } else if let lastViewedThread {
            owsAssertDebug((searchBar.text ?? "").stripped.isEmpty)

            // When returning to conversation list, try to ensure that the "last" thread is still
            // visible.  The threads often change ordering while in conversation view due
            // to incoming & outgoing messages. Reload to ensure we have this latest ordering
            // before we find the index path we want to scroll to.
            loadCoordinator.loadIfNecessary(suppressAnimations: true, shouldForceLoad: true)
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

        viewState.searchResultsController.viewWillAppear(animated)

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

        let isCollapsed = splitViewController?.isCollapsed ?? true
        if let selectedIndexPath = tableView.indexPathForSelectedRow, let selectedThread = renderState.thread(forIndexPath: selectedIndexPath) {
            if viewState.lastSelectedThreadId != selectedThread.uniqueId {
                owsFailDebug("viewState.lastSelectedThreadId out of sync with table view")
                viewState.lastSelectedThreadId = selectedThread.uniqueId
                updateShouldBeUpdatingView()
            }

            if isCollapsed {
                if animated, let transitionCoordinator {
                    transitionCoordinator.animate { [self] _ in
                        tableView.deselectRow(at: selectedIndexPath, animated: true)
                    } completion: { [self] context in
                        if context.isCancelled {
                            tableView.selectRow(at: selectedIndexPath, animated: false, scrollPosition: .none)
                        } else {
                            viewState.lastSelectedThreadId = nil
                            loadCoordinator.scheduleLoad(updatedThreadIds: [selectedThread.uniqueId], animated: true)
                        }
                    }
                } else {
                    // No animated transition, so just update the state immediately.
                    viewState.lastSelectedThreadId = nil
                    tableView.deselectRow(at: selectedIndexPath, animated: false)
                    loadCoordinator.scheduleLoad(updatedThreadIds: [selectedThread.uniqueId], animated: false)
                }
            }
        } else if isCollapsed, let threadId = viewState.lastSelectedThreadId {
            // If there is no currently selected table row, clean up the
            // lastSelectedThreadId viewState and reload that item
            viewState.lastSelectedThreadId = nil
            loadCoordinator.scheduleLoad(updatedThreadIds: [threadId], animated: animated)
        }
    }

    private var hasPresentedBackupErrors = false

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        appReadiness.setUIIsReady()

        if getStartedBanner == nil && !hasEverPresentedExperienceUpgrade && ExperienceUpgradeManager.presentNext(fromViewController: self) {
            hasEverPresentedExperienceUpgrade = true
        } else if !hasEverAppeared {
            presentGetStartedBannerIfNecessary()
        }

        if !hasPresentedBackupErrors {
            hasPresentedBackupErrors = true
            DependenciesBridge.shared.messageBackupErrorPresenter.presentOverTopmostViewController(completion: {})
        }

        // Whether or not the theme has changed, always ensure
        // the right theme is applied. The initial collapsed
        // state of the split view controller is determined between
        // `viewWillAppear` and `viewDidAppear`, so this is the soonest
        // we can know the right thing to display.
        applyTheme()

        requestReviewIfAppropriate()

        viewState.searchResultsController.viewDidAppear(animated)

        if viewState.shouldFocusSearchOnAppear {
            viewState.shouldFocusSearchOnAppear = false
            DispatchQueue.main.async {
                self.focusSearch()
            }
        }

        showBadgeSheetIfNecessary()
        Task { await self.checkForFailedServiceExtensionLaunches() }

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
        super.viewDidDisappear(animated)

        searchResultsController.viewDidDisappear(animated)
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        updateFilterControl(animated: false)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let bottomInset = if let getStartedBanner, getStartedBanner.isViewLoaded, !getStartedBanner.view.isHidden {
            getStartedBanner.opaqueHeight
        } else {
            CGFloat(0.0)
        }

        if tableView.contentInset.bottom != bottomInset {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.tableView.contentInset.bottom = bottomInset
            }
        }
    }

    // MARK: Theme, content size, and layout changes

    public override func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()

        // This is expensive but this event is very rare.
        reloadTableDataAndResetCellContentCache()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        applyTheme()
        reloadTableDataAndResetCellContentCache()
        applyThemeToContextMenuAndToolbar()
    }

    private func applyTheme() {
        view.backgroundColor = Theme.backgroundColor
        tableView.backgroundColor = Theme.backgroundColor
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        guard isViewLoaded else { return }

        containerView.willTransition(to: size, with: coordinator)

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

    private func settingsBarButtonItem() -> UIBarButtonItem {
        let barButtonItem = createSettingsBarButtonItem(
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            shouldShowUnreadPaymentBadge: viewState.settingsButtonCreator.hasUnreadPaymentNotification,
            buildActions: { settingsAction -> [UIAction] in
                var contextMenuActions: [UIAction] = []

                // FIXME: combine viewState.inboxFilter and renderState.viewInfo.inboxFilter to avoid bugs with them getting out of sync
                switch viewState.inboxFilter {
                case .unread:
                    contextMenuActions.append(.disableChatListFilter(target: self))
                case .none?, nil:
                    contextMenuActions.append(.enableChatListFilter(target: self))
                }

                if viewState.settingsButtonCreator.hasInboxChats {
                    contextMenuActions.append(
                        UIAction(
                            title: OWSLocalizedString(
                                "HOME_VIEW_TITLE_SELECT_CHATS",
                                comment: "Title for the 'Select Chats' option in the ChatList."
                            ),
                            image: Theme.iconImage(.contextMenuSelect),
                            handler: { [weak self] _ in
                                self?.willEnterMultiselectMode()
                            }
                        )
                    )
                }

                contextMenuActions.append(settingsAction)

                if viewState.settingsButtonCreator.hasArchivedChats {
                    contextMenuActions.append(
                        UIAction(
                            title: OWSLocalizedString(
                                "HOME_VIEW_TITLE_ARCHIVE",
                                comment: "Title for the conversation list's 'archive' mode."
                            ),
                            image: Theme.iconImage(.contextMenuArchive),
                            handler: { [weak self] _ in
                                self?.showArchivedConversations(offerMultiSelectMode: true)
                            }
                        )
                    )
                }

                return contextMenuActions
            }, showAppSettings: { [weak self] in
                self?.showAppSettings()
            }
        )
        barButtonItem.accessibilityLabel = CommonStrings.openSettingsButton
        barButtonItem.accessibilityIdentifier = "ChatListViewController.settingsButton"
        return barButtonItem
    }

    // MARK: Table View

    func reloadTableDataAndResetThreadViewModelCache() {
        threadViewModelCache.clear()
        reloadTableDataAndResetCellContentCache()
    }

    func reloadTableDataAndResetCellContentCache() {
        AssertIsOnMainThread()

        cellContentCache.clear()
        conversationCellHeightCache = nil
        reloadTableData()
    }

    func reloadTableData(withSelection previousSelection: [TSThread]? = nil) {
        AssertIsOnMainThread()

        let selectedThreadIds: Set<String>
        if let previousSelection {
            selectedThreadIds = Set(previousSelection.lazy.map(\.uniqueId))
        } else {
            selectedThreadIds = []
        }

        tableView.reloadData()

        if !selectedThreadIds.isEmpty {
            var threadIdsToBeSelected = selectedThreadIds
            for section in 0..<tableDataSource.numberOfSections(in: tableView) {
                for row in 0..<tableDataSource.tableView(tableView, numberOfRowsInSection: section) {
                    let indexPath = IndexPath(row: row, section: section)
                    if let key = renderState.thread(forIndexPath: indexPath)?.uniqueId, threadIdsToBeSelected.contains(key) {
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

    func updateBarButtonItems() {
        updateLeftBarButtonItem()
        updateRightBarButtonItems()
    }

    private func updateLeftBarButtonItem() {
        guard viewState.chatListMode == .inbox && !viewState.multiSelectState.isActive else { return }

        // Settings button.
        navigationItem.leftBarButtonItem = settingsBarButtonItem()
    }

    private func updateRightBarButtonItems() {
        guard viewState.chatListMode == .inbox && !viewState.multiSelectState.isActive else { return }

        var rightBarButtonItems = [UIBarButtonItem]()

        let compose = UIBarButtonItem(
            image: Theme.iconImage(.buttonCompose),
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
            image: Theme.iconImage(.buttonCamera),
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

        if let proxyButton = viewState.proxyButtonCreator.buildButton() {
            rightBarButtonItems.append(proxyButton)
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
        SSKEnvironment.shared.contactManagerImplRef.requestSystemContactsOnce { error in
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
        SSKEnvironment.shared.contactManagerImplRef.requestSystemContactsOnce { error in
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

    private static var requestReviewCount = 0
    private static var didRequestReview = false

    private func requestReviewIfAppropriate() {
        Self.requestReviewCount += 1

        // Despite `SKStoreReviewController` docs, some people have reported seeing
        // the "request review" prompt repeatedly after first installation. Let's
        // make sure it only happens at most once per launch.
        if Self.didRequestReview {
            return
        }

        guard hasEverAppeared, Self.requestReviewCount > 25 else {
            return
        }

        guard let windowScene = self.view.window?.windowScene else {
            return
        }

        // In Production this will pop up at most 3 times per 365 days.
        SKStoreReviewController.requestReview(in: windowScene)
        Self.didRequestReview = true
    }

    // MARK: View State

    let viewState: CLVViewState

    private func shouldShowFirstConversationCue() -> Bool {
        return shouldShowEmptyInboxView && !SSKEnvironment.shared.databaseStorageRef.read(block: SSKPreferences.hasSavedThread(transaction:))
    }

    private var shouldShowEmptyInboxView: Bool {
        return viewState.chatListMode == .inbox && renderState.viewInfo.inboxCount == 0 && renderState.viewInfo.archiveCount == 0 && !renderState.hasVisibleReminders
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

    // MARK: Badge Sheets

    private var donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore {
        DependenciesBridge.shared.donationReceiptCredentialResultStore
    }

    @objc
    func showBadgeSheetIfNecessary() {
        guard isChatListTopmostViewController() else {
            return
        }

        let (
            oneTimeBoostDonationReceiptCredentialRedemptionSuccess,
            recurringSubscriptionInitiationDonationReceiptCredentialRedemptionSuccess,

            oneTimeBoostSuccessHasBeenPresented,
            recurringSubscriptionInitiationSuccessHasBeenPresented,

            oneTimeBoostReceiptCredentialRequestError,
            recurringSubscriptionInitiationReceiptCredentialRequestError,
            recurringSubscriptionRenewalReceiptCredentialRequestError,

            oneTimeBoostErrorHasBeenPresented,
            recurringSubscriptionInitiationErrorHasBeenPresented,
            recurringSubscriptionRenewalErrorHasBeenPresented,

            donationSubscriberID,
            expiredBadgeID,
            shouldShowExpirySheet,
            mostRecentSubscriptionPaymentMethod,
            probablyHasCurrentSubscription
        ) = SSKEnvironment.shared.databaseStorageRef.read { transaction in (
            donationReceiptCredentialResultStore.getRedemptionSuccess(successMode: .oneTimeBoost, tx: transaction.asV2Read),
            donationReceiptCredentialResultStore.getRedemptionSuccess(successMode: .recurringSubscriptionInitiation, tx: transaction.asV2Read),

            donationReceiptCredentialResultStore.hasPresentedSuccess(successMode: .oneTimeBoost, tx: transaction.asV2Read),
            donationReceiptCredentialResultStore.hasPresentedSuccess(successMode: .recurringSubscriptionInitiation, tx: transaction.asV2Read),

            donationReceiptCredentialResultStore.getRequestError(errorMode: .oneTimeBoost, tx: transaction.asV2Read),
            donationReceiptCredentialResultStore.getRequestError(errorMode: .recurringSubscriptionInitiation, tx: transaction.asV2Read),
            donationReceiptCredentialResultStore.getRequestError(errorMode: .recurringSubscriptionRenewal, tx: transaction.asV2Read),

            donationReceiptCredentialResultStore.hasPresentedError(errorMode: .oneTimeBoost, tx: transaction.asV2Read),
            donationReceiptCredentialResultStore.hasPresentedError(errorMode: .recurringSubscriptionInitiation, tx: transaction.asV2Read),
            donationReceiptCredentialResultStore.hasPresentedError(errorMode: .recurringSubscriptionRenewal, tx: transaction.asV2Read),

            DonationSubscriptionManager.getSubscriberID(transaction: transaction),
            DonationSubscriptionManager.mostRecentlyExpiredBadgeID(transaction: transaction),
            DonationSubscriptionManager.showExpirySheetOnHomeScreenKey(transaction: transaction),
            DonationSubscriptionManager.getMostRecentSubscriptionPaymentMethod(transaction: transaction),
            DonationSubscriptionManager.probablyHasCurrentSubscription()
        )}

        if
            let oneTimeBoostDonationReceiptCredentialRedemptionSuccess,
            !oneTimeBoostSuccessHasBeenPresented
        {
            BadgeThanksSheetPresenter.load(
                redemptionSuccess: oneTimeBoostDonationReceiptCredentialRedemptionSuccess,
                successMode: .oneTimeBoost
            ).presentBadgeThanksAndClearSuccess(fromViewController: self)
        } else if
            let recurringSubscriptionInitiationDonationReceiptCredentialRedemptionSuccess,
            !recurringSubscriptionInitiationSuccessHasBeenPresented
        {
            BadgeThanksSheetPresenter.load(
                redemptionSuccess: recurringSubscriptionInitiationDonationReceiptCredentialRedemptionSuccess,
                successMode: .recurringSubscriptionInitiation
            ).presentBadgeThanksAndClearSuccess(fromViewController: self)
        } else if
            let oneTimeBoostReceiptCredentialRequestError,
            !oneTimeBoostErrorHasBeenPresented
        {
            showBadgeIssueSheetIfNeeded(
                receiptCredentialRequestError: oneTimeBoostReceiptCredentialRequestError,
                errorMode: .oneTimeBoost
            )
        } else if
            let recurringSubscriptionInitiationReceiptCredentialRequestError,
            !recurringSubscriptionInitiationErrorHasBeenPresented
        {
            showBadgeIssueSheetIfNeeded(
                receiptCredentialRequestError: recurringSubscriptionInitiationReceiptCredentialRequestError,
                errorMode: .recurringSubscriptionInitiation
            )
        } else if
            let recurringSubscriptionRenewalReceiptCredentialRequestError,
            !recurringSubscriptionRenewalErrorHasBeenPresented
        {
            showBadgeIssueSheetIfNeeded(
                receiptCredentialRequestError: recurringSubscriptionRenewalReceiptCredentialRequestError,
                errorMode: .recurringSubscriptionRenewal
            )
        } else {
            showBadgeExpirationSheetIfNeeded(
                donationSubscriberID: donationSubscriberID,
                expiredBadgeID: expiredBadgeID,
                shouldShowExpirySheet: shouldShowExpirySheet,
                mostRecentSubscriptionPaymentMethod: mostRecentSubscriptionPaymentMethod,
                probablyHasCurrentSubscription: probablyHasCurrentSubscription
            )
        }
    }

    /// Show a badge issue sheet if we need to.
    ///
    /// Most payment methods succeed or fail to process quickly, and we're able
    /// to show a blocking spinner in the donation flow until we know the
    /// status, and show the appropriate UI there (so we show nothing here).
    ///
    /// Bank payments, however, are expected to take a long time (on the order
    /// of days) to process. If one eventually fails, and we find ourselves with
    /// an error for a failed bank payment, we should present a sheet for it.
    private func showBadgeIssueSheetIfNeeded(
        receiptCredentialRequestError: DonationReceiptCredentialRequestError,
        errorMode: DonationReceiptCredentialResultStore.Mode
    ) {
        /// Record that we've presented this error. Important to do even for
        /// errors that don't merit presentation – otherwise, as long as this
        /// error is persisted and not-presented, we'll keep attempting and
        /// declining to present it. That'd be bad if it prevented us from
        /// presenting a different error.
        func hasPresentedError() {
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                self.donationReceiptCredentialResultStore.setHasPresentedError(
                    errorMode: errorMode,
                    tx: tx.asV2Write
                )
            }
        }

        guard let badge = receiptCredentialRequestError.badge else {
            owsFailDebug("Missing badge for failed donation! Is this an old error?")
            return hasPresentedError()
        }

        let errorCode = receiptCredentialRequestError.errorCode
        let paymentMethod = receiptCredentialRequestError.paymentMethod
        let chargeFailureCodeIfPaymentFailed = receiptCredentialRequestError.chargeFailureCodeIfPaymentFailed

        switch errorCode {
        case .paymentStillProcessing:
            // Not a terminal error – no reason to show a sheet.
            return hasPresentedError()
        case
                .paymentFailed,
                .localValidationFailed,
                .serverValidationFailed,
                .paymentNotFound,
                .paymentIntentRedeemed:
            break
        }

        switch paymentMethod {
        case nil, .applePay, .creditOrDebitCard, .paypal:
            // Non-SEPA payment methods generally get their errors immediately,
            // and so errors from initiating a donation should have been
            // presented when the user was in the donate view. Consequently, we
            // only want to present renewal errors here.
            switch errorMode {
            case .oneTimeBoost, .recurringSubscriptionInitiation:
                return hasPresentedError()
            case .recurringSubscriptionRenewal:
                break
            }
        case .sepa, .ideal:
            // SEPA donations won't error out immediately upon initiation
            // (they'll spend time processing first), so we should show errors
            // for any variety of donation here.
            break
        }

        let logger = PrefixedLogger(prefix: "[Donations]", suffix: "\(errorMode)")

        Promise.wrapAsync {
            try await SSKEnvironment.shared.profileManagerRef.badgeStore.populateAssetsOnBadge(badge)
        }.done(on: DispatchQueue.main) {
            guard self.isChatListTopmostViewController() else {
                logger.info("Not presenting error – no longer the top view controller.")
                return
            }

            let badgeIssueSheetMode: BadgeIssueSheetState.Mode = {
                switch errorMode {
                case .oneTimeBoost, .recurringSubscriptionInitiation:
                    return .bankPaymentFailed(
                        chargeFailureCode: chargeFailureCodeIfPaymentFailed
                    )
                case .recurringSubscriptionRenewal:
                    return .subscriptionExpiredBecauseOfChargeFailure(
                        chargeFailureCode: chargeFailureCodeIfPaymentFailed,
                        paymentMethod: paymentMethod
                    )
                }
            }()

            let badgeIssueSheet = BadgeIssueSheet(
                badge: badge,
                mode: badgeIssueSheetMode
            )
            badgeIssueSheet.delegate = self

            self.present(badgeIssueSheet, animated: true) {
                hasPresentedError()
            }
        }.catch(on: SyncScheduler()) { _ in
            logger.error("Failed to populate badge assets!")
        }
    }

    private func showBadgeExpirationSheetIfNeeded(
        donationSubscriberID: Data?,
        expiredBadgeID: String?,
        shouldShowExpirySheet: Bool,
        mostRecentSubscriptionPaymentMethod: DonationPaymentMethod?,
        probablyHasCurrentSubscription: Bool
    ) {
        guard let expiredBadgeID else {
            return
        }

        guard shouldShowExpirySheet else {
            return
        }

        Logger.info("[Donations] showing expiry sheet for expired badge \(expiredBadgeID)")

        if BoostBadgeIds.contains(expiredBadgeID) {
            firstly {
                DonationSubscriptionManager.getBoostBadge()
            }.done(on: DispatchQueue.global()) { boostBadge in
                Promise.wrapAsync {
                    try await SSKEnvironment.shared.profileManagerRef.badgeStore.populateAssetsOnBadge(boostBadge)
                }.done(on: DispatchQueue.main) {
                    // Make sure we're still the active VC
                    guard UIApplication.shared.frontmostViewController == self.conversationSplitViewController,
                          self.conversationSplitViewController?.selectedThread == nil else { return }

                    let badgeSheet = BadgeIssueSheet(
                        badge: boostBadge,
                        mode: .boostExpired(hasCurrentSubscription: probablyHasCurrentSubscription)
                    )
                    badgeSheet.delegate = self
                    self.present(badgeSheet, animated: true)
                    SSKEnvironment.shared.databaseStorageRef.write { transaction in
                        DonationSubscriptionManager.setShowExpirySheetOnHomeScreenKey(show: false, transaction: transaction)
                    }
                }.catch { error in
                    owsFailDebug("Failed to fetch boost badge assets for expiry \(error)")
                }
            }.catch { error in
                owsFailDebug("Failed to fetch boost badge for expiry \(error)")
            }
        } else if SubscriptionBadgeIds.contains(expiredBadgeID) {
            /// We expect to show an error sheet when the subscription fails to
            /// renew and we learn about it from the receipt credential
            /// redemption job kicked off by the keep-alive.
            ///
            /// Consequently, we don't need/want to show a sheet for the badge
            /// expiration itself, since we should've already shown a sheet.
            ///
            /// It's possible that the subscription simply "expired" due to
            /// inactivity (the subscription was not kept-alive), in which case
            /// we won't have shown a sheet because there won't have been a
            /// renewal failure. That's ok – we'll let the badge expire
            /// silently.
            ///
            /// We'll still fetch the subscription, but just for logging
            /// purposes.

            firstly(on: DispatchQueue.global()) { () -> Promise<Subscription?> in
                guard let donationSubscriberID else {
                    return .value(nil)
                }

                return DonationSubscriptionManager.getCurrentSubscriptionStatus(
                    for: donationSubscriberID
                )
            }.done(on: DispatchQueue.global()) { currentSubscription in
                defer {
                    SSKEnvironment.shared.databaseStorageRef.write { transaction in
                        DonationSubscriptionManager.setShowExpirySheetOnHomeScreenKey(show: false, transaction: transaction)
                    }
                }

                guard let currentSubscription else {
                    // If the subscription is missing entirely, it presumably
                    // expired due to inactivity.
                    Logger.warn("[Donations] Missing subscription for expired badge. It probably expired due to inactivity and was deleted.")
                    return
                }

                owsAssertDebug(
                    currentSubscription.status == .canceled,
                    "[Donations] Current subscription is not canceled, but the badge expired!"
                )

                if let chargeFailure = currentSubscription.chargeFailure {
                    Logger.warn("[Donations] Badge expired for subscription with charge failure: \(chargeFailure.code ?? "nil")")
                } else {
                    Logger.warn("[Donations] Badge expired for subscription without charge failure. It probably expired due to inactivity, but hasn't yet been deleted.")
                }
            }.catch(on: SyncScheduler()) { _ in
                owsFailDebug("[Donations] Failed to get subscription during badge expiration!")
            }
        }
    }

    private func isChatListTopmostViewController() -> Bool {
        guard
            UIApplication.shared.frontmostViewController == self.conversationSplitViewController,
            conversationSplitViewController?.selectedThread == nil,
            presentedViewController == nil
        else { return false }

        return true
    }

    // MARK: - Payments

    func configureUnreadPaymentsBannerSingle(_ paymentsReminderView: UIView,
                                             paymentModel: TSPaymentModel,
                                             transaction: SDSAnyReadTransaction) {

        guard paymentModel.isIncoming,
              !paymentModel.isUnidentified,
              let senderAci = paymentModel.senderOrRecipientAci?.wrappedAciValue,
              let paymentAmount = paymentModel.paymentAmount,
              paymentAmount.isValid else {
            configureUnreadPaymentsBannerMultiple(paymentsReminderView, unreadCount: 1)
            return
        }
        let address = SignalServiceAddress(senderAci)
        guard nil != TSContactThread.getWithContactAddress(address, transaction: transaction) else {
            configureUnreadPaymentsBannerMultiple(paymentsReminderView, unreadCount: 1)
            return
        }

        let shortName = SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: transaction).resolvedValue(useShortNameIfAvailable: true)
        let formattedAmount = PaymentsFormat.format(paymentAmount: paymentAmount,
                                                    isShortForm: true,
                                                    withCurrencyCode: true,
                                                    withSpace: true)
        let format = OWSLocalizedString("PAYMENTS_NOTIFICATION_BANNER_1_WITH_DETAILS_FORMAT",
                                       comment: "Format for the payments notification banner for a single payment notification with details. Embeds: {{ %1$@ the name of the user who sent you the payment, %2$@ the amount of the payment }}.")
        let title = String(format: format, shortName, formattedAmount)

        let avatarView = ConversationAvatarView(sizeClass: .customDiameter(Self.paymentsBannerAvatarSize), localUserDisplayMode: .asUser)
        avatarView.update(transaction) { config in
            config.dataSource = .address(address)
        }

        let paymentsHistoryItem = PaymentsHistoryModelItem(
            paymentModel: paymentModel,
            displayName: shortName
        )

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

        let iconView = UIImageView.withTemplateImageName(
            "payment",
            tintColor: Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_white
        )
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

        init(block: @escaping () -> Void) {
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

        let dismissIcon = UIImageView.withTemplateImageName("x-compact",
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

    // MARK: - Notifications

    func checkForFailedServiceExtensionLaunches() async {
        guard #available(iOS 17.0, *) else {
            return
        }

        guard RemoteConfig.current.shouldCheckForServiceExtensionFailures else {
            return
        }

        await SSKEnvironment.shared.messageProcessorRef.waitForFetchingAndProcessing().awaitable()

        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        guard notificationSettings.authorizationStatus == .authorized else {
            return
        }

        // Has the NSE ever launched with the current version?
        let appVersion = AppVersionImpl.shared
        guard
            let mainAppVersion = appVersion.lastCompletedLaunchMainAppVersion,
            let nseAppVersion = appVersion.lastCompletedLaunchNSEAppVersion,
            let upgradeDate = appVersion.firstMainAppLaunchDateAfterUpdate
        else {
            return
        }
        guard nseAppVersion != mainAppVersion else {
            return
        }

        // Has it been at least an hour since we upgraded?
        guard -upgradeDate.timeIntervalSinceNow > kHourInterval else {
            return
        }

        // Has the user restarted since the most recent update was installed?
        let bootTime: Date? = {
            var timeVal = timeval()
            var timeValSize = MemoryLayout<timeval>.size
            let err = sysctlbyname("kern.boottime", &timeVal, &timeValSize, nil, 0)
            guard err == 0, timeValSize == MemoryLayout<timeval>.size else {
                return nil
            }
            return Date(timeIntervalSince1970: TimeInterval(timeVal.tv_sec))
        }()
        guard let bootTime else {
            return
        }
        guard bootTime < upgradeDate else {
            return
        }

        let keyValueStore = KeyValueStore(collection: "FailedNSELaunches")
        let mostRecentDateKey = "mostRecentPromptDate"
        let promptCountKey = "promptCount"

        let shouldShowPrompt = SSKEnvironment.shared.databaseStorageRef.read { tx in
            // If we've shown the prompt recently, don't show it again.
            let promptCount = keyValueStore.getInt(promptCountKey, defaultValue: 0, transaction: tx.asV2Read)
            let promptBackoff: TimeInterval = {
                switch promptCount {
                case 0:
                    return 0
                case 1, 2:
                    return 24*kHourInterval
                case 3:
                    return 48*kHourInterval
                case 4:
                    return 72*kHourInterval
                default:
                    return 96*kHourInterval
                }
            }()
            let mostRecentDate = keyValueStore.getDate(mostRecentDateKey, transaction: tx.asV2Read)
            if let mostRecentDate, -mostRecentDate.timeIntervalSinceNow < promptBackoff {
                return false
            }

            // If we haven't received a message since upgrading, don't show it.
            guard
                let mostRecentMessage = InteractionFinder.lastInsertedIncomingMessage(transaction: tx),
                Date(millisecondsSince1970: mostRecentMessage.receivedAtTimestamp) > upgradeDate
            else {
                return false
            }
            return true
        }

        guard shouldShowPrompt else {
            return
        }

        guard isChatListTopmostViewController() else {
            return
        }

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "NOTIFICATIONS_ERROR_TITLE",
                comment: "Shown as the title of an alert when notifications can't be shown due to an error."
            ),
            message: String(
                format: OWSLocalizedString(
                    "NOTIFICATIONS_ERROR_MESSAGE",
                    comment: "Shown as the body of an alert when notifications can't be shown due to an error."
                ),
                UIDevice.current.localizedModel
            )
        )
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.contactSupport,
            handler: { [weak self] _ in
                guard let self else { return }
                ContactSupportAlert.presentStep2(emailSupportFilter: "NotLaunchingNSE", fromViewController: self)
            }
        ))
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okButton))

        let promptDate = Date()
        self.present(actionSheet, animated: true)

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            keyValueStore.setDate(promptDate, key: mostRecentDateKey, transaction: tx.asV2Write)
            keyValueStore.setInt(
                keyValueStore.getInt(promptCountKey, defaultValue: 0, transaction: tx.asV2Read) + 1,
                key: promptCountKey,
                transaction: tx.asV2Write
            )
        }
    }
}

// MARK: - ChatListFilterActions

extension ChatListViewController {
    func enableChatListFilter(_ sender: AnyObject?) {
        updateChatListFilter(.unread)
        updateBarButtonItems()

        if filterControl?.isFiltering == true {
            // No need to update the filter control if it's already in the
            // filtering state.
            loadCoordinator.loadIfNecessary()
        } else {
            tableView.performBatchUpdates {
                filterControl?.startFiltering(animated: true)
                loadCoordinator.loadIfNecessary()
            }
        }
    }

    func disableChatListFilter(_ sender: AnyObject?) {
        updateChatListFilter(.none)
        updateBarButtonItems()

        tableView.performBatchUpdates {
            filterControl?.stopFiltering(animated: true)
            loadCoordinator.loadIfNecessary()
        }
    }

    private func updateFilterControl(animated: Bool) {
        guard let filterControl else { return }
        if viewState.inboxFilter == .unread {
            filterControl.startFiltering(animated: animated)
        } else {
            filterControl.stopFiltering(animated: animated)
        }
    }

    private func updateChatListFilter(_ inboxFilter: InboxFilter) {
        viewState.inboxFilter = inboxFilter
        loadCoordinator.saveInboxFilter(inboxFilter)
        updateBarButtonItems()
    }
}

// MARK: - Settings Button

extension ChatListViewController: ChatListSettingsButtonDelegate {
    func didUpdateButton(_ settingsButtonCreator: ChatListSettingsButtonState) {
        updateLeftBarButtonItem()
    }
}

extension ChatListViewController: ChatListProxyButtonDelegate {
    func didUpdateButton(_ proxyButtonCreator: ChatListProxyButtonCreator) {
        updateRightBarButtonItems()
    }

    func didTapButton(_ proxyButtonCreator: ChatListProxyButtonCreator) {
        showAppSettings(mode: .proxy)
    }
}

extension ChatListViewController {
    enum ShowAppSettingsMode {
        case none
        case payments
        case payment(paymentsHistoryItem: PaymentsHistoryItem)
        case paymentsTransferIn
        case appearance
        case avatarBuilder
        case corruptedUsernameResolution
        case corruptedUsernameLinkResolution
        case donate(donateMode: DonateViewController.DonateMode)
        case linkedDevices
        case linkNewDevice(provisioningUrl: DeviceProvisioningURL)
        case proxy
    }

    func showAppSettings() {
        showAppSettings(mode: .none)
    }

    func showAppSettingsInAppearanceMode() {
        showAppSettings(mode: .appearance)
    }

    func showAppSettingsInAvatarBuilderMode() {
        showAppSettings(mode: .avatarBuilder)
    }

    func showAppSettings(mode: ShowAppSettingsMode) {
        AssertIsOnMainThread()

        Logger.info("")

        // Dismiss any message actions if they're presented
        conversationSplitViewController?.selectedConversationViewController?
            .dismissMessageContextMenu(animated: true)

        let appSettingsViewController = AppSettingsViewController(appReadiness: appReadiness)

        var completion: (() -> Void)?
        var viewControllers: [UIViewController] = [ appSettingsViewController ]

        switch mode {
        case .none:
            break
        case .payments:
            let paymentsSettings = PaymentsSettingsViewController(mode: .inAppSettings, appReadiness: appReadiness)
            viewControllers += [ paymentsSettings ]
        case .payment(let paymentsHistoryItem):
            let paymentsSettings = PaymentsSettingsViewController(mode: .inAppSettings, appReadiness: appReadiness)
            let paymentsDetail = PaymentsDetailViewController(paymentItem: paymentsHistoryItem)
            viewControllers += [ paymentsSettings, paymentsDetail ]
        case .paymentsTransferIn:
            let paymentsSettings = PaymentsSettingsViewController(mode: .inAppSettings, appReadiness: appReadiness)
            let paymentsTransferIn = PaymentsTransferInViewController()
            viewControllers += [ paymentsSettings, paymentsTransferIn ]
        case .appearance:
            let appearance = AppearanceSettingsTableViewController()
            viewControllers += [ appearance ]
        case .avatarBuilder:
            let profile = ProfileSettingsViewController(
                usernameChangeDelegate: appSettingsViewController,
                usernameLinkScanDelegate: appSettingsViewController
            )

            viewControllers += [ profile ]
            completion = { profile.presentAvatarSettingsView() }
        case .corruptedUsernameResolution:
            let profile = ProfileSettingsViewController(
                usernameChangeDelegate: appSettingsViewController,
                usernameLinkScanDelegate: appSettingsViewController
            )

            viewControllers += [ profile ]
            completion = { profile.presentUsernameCorruptedResolution() }
        case .corruptedUsernameLinkResolution:
            let profile = ProfileSettingsViewController(
                usernameChangeDelegate: appSettingsViewController,
                usernameLinkScanDelegate: appSettingsViewController
            )

            viewControllers += [ profile ]
            completion = { profile.presentUsernameLinkCorruptedResolution() }
        case let .donate(donateMode):
            guard DonationUtilities.canDonate(
                inMode: donateMode.asDonationMode,
                localNumber: DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber
            ) else {
                DonationViewsUtil.openDonateWebsite()
                return
            }

            let donate = DonateViewController(preferredDonateMode: donateMode) { [weak self] finishResult in
                switch finishResult {
                case let .completedDonation(donateSheet, receiptCredentialSuccessMode):
                    donateSheet.dismiss(animated: true) { [weak self] in
                        guard
                            let self,
                            let badgeThanksSheetPresenter = BadgeThanksSheetPresenter.loadWithSneakyTransaction(
                                successMode: receiptCredentialSuccessMode
                            )
                        else { return }

                        badgeThanksSheetPresenter.presentBadgeThanksAndClearSuccess(
                            fromViewController: self
                        )
                    }
                case let .monthlySubscriptionCancelled(donateSheet, toastText):
                    donateSheet.dismiss(animated: true) { [weak self] in
                        guard let self = self else { return }
                        self.view.presentToast(text: toastText, fromViewController: self)
                    }
                }
            }
            viewControllers += [donate]
        case .linkedDevices:
            viewControllers += [ LinkedDevicesHostingController() ]
        case .linkNewDevice(let provisioningUrl):
            let linkDeviceViewController = LinkedDevicesHostingController(
                presentationOnFirstAppear: .linkNewDevice(preknownProvisioningUrl: provisioningUrl)
            )

            viewControllers += [ linkDeviceViewController ]
        case .proxy:
            viewControllers += [ PrivacySettingsViewController(), AdvancedPrivacySettingsViewController(), ProxySettingsViewController() ]
        }

        let navigationController = OWSNavigationController()
        navigationController.setViewControllers(viewControllers, animated: false)
        presentFormSheet(navigationController, animated: true, completion: completion)
    }
}

extension ChatListViewController: BadgeIssueSheetDelegate {
    func badgeIssueSheetActionTapped(_ action: BadgeIssueSheetAction) {
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
        guard getStartedBanner == nil && viewState.chatListMode == .inbox else { return }

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
        let contactNames = SSKEnvironment.shared.databaseStorageRef.read { tx -> [ComparableDisplayName] in
            let comparableNames = SSKEnvironment.shared.contactManagerRef.sortedComparableNames(
                for: SSKEnvironment.shared.profileManagerRef.allWhitelistedRegisteredAddresses(tx: tx),
                tx: tx
            )
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
                return []
            }
            return Array(
                comparableNames.lazy
                    .filter { !localIdentifiers.contains(address: $0.address) }
                    .prefix(3)
            )
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
                return OWSLocalizedString(
                    "HOME_VIEW_FIRST_CONVERSATION_OFFER_3_CONTACTS_FORMAT",
                    comment: "Format string for a label offering to start a new conversation with your contacts, if you have at least 3 Signal contacts.  Embeds {{The names of 3 of your Signal contacts}}."
                )
            default:
                owsFail("Too many contactNames.")
            }
        }()

        let attributedString = NSAttributedString.make(
            fromFormat: formatString,
            attributedFormatArgs: contactNames.map { comparableName in
                return .string(
                    comparableName.resolvedValue(),
                    attributes: [.font: firstConversationLabel.font.semibold()]
                )
            }
        )

        firstConversationLabel.attributedText = attributedString
    }
}

extension ChatListViewController: UIScrollViewDelegate {
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        filterControl?.draggingWillBegin(in: scrollView)
        cancelSearch()
    }

    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        filterControl?.draggingWillEnd(in: scrollView)
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        filterControl?.draggingDidEnd(in: scrollView)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        filterControl?.scrollingDidStop(in: scrollView)
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        filterControl?.scrollingDidStop(in: scrollView)
    }
}

extension ChatListViewController: ChatListFilterControlDelegate {
    func filterControlWillChangeState(to state: ChatListFilterControl.FilterState) {
        switch state {
        case .on:
            updateChatListFilter(.unread)
        case .off:
            updateChatListFilter(.none)
        }

        // Because this happens in response to an interactive gesture, it feels
        // better to go a little slower than the default animation duration (0.25 sec).
        UIView.animate(withDuration: 0.4) { [self] in
            tableView.performBatchUpdates {
                loadCoordinator.loadIfNecessary()
            }
        }
    }
}
