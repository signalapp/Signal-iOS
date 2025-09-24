//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
public import SignalUI

public enum ConversationUIMode: UInt {
    case normal
    case search
    case selection

    // These two modes are used to select interactions.
    public var hasSelectionUI: Bool {
        switch self {
        case .normal, .search:
            return false
        case .selection:
            return true
        }
    }
}

public enum ConversationViewAction {
    case none
    case compose
    case voiceCall
    case videoCall
    case groupCallLobby
    case newGroupActionSheet
    case updateDraft
}

// MARK: -

public final class ConversationViewController: OWSViewController {

    internal let context: ViewControllerContext

    public let appReadiness: AppReadinessSetter
    public let viewState: CVViewState
    public let loadCoordinator: CVLoadCoordinator
    public let layout: ConversationViewLayout
    public let collectionView: ConversationCollectionView
    public let searchController: ConversationSearchController

    var selectionToolbar: MessageActionsToolbar?

    var otherUsersProfileDidChangeEvent: DebouncedEvent?

    /// See `ConversationViewController+OWS.updateContentInsetsDebounced`
    lazy var updateContentInsetsEvent = DebouncedEvents.build(
        mode: .lastOnly,
        maxFrequencySeconds: 0.01,
        onQueue: .main,
        notifyBlock: { [weak self] in
            self?.updateContentInsets()
        })

    // MARK: -

    public static func load(
        appReadiness: AppReadinessSetter,
        threadViewModel: ThreadViewModel,
        action: ConversationViewAction,
        focusMessageId: String?,
        tx: DBReadTransaction
    ) -> ConversationViewController {
        let thread = threadViewModel.threadRecord

        // We always need to find where the unread divider should be placed, even
        // if we opened the chat by tapping on a search result.
        let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
        let oldestUnreadMessage = try? interactionFinder.oldestUnreadInteraction(transaction: tx)

        let loadAroundMessageId: String?
        let scrollToMessageId: String?

        if let focusMessageId {
            loadAroundMessageId = focusMessageId
            scrollToMessageId = focusMessageId
        } else if let oldestUnreadMessage {
            loadAroundMessageId = oldestUnreadMessage.uniqueId
            // Set this to `nil` so that we scroll to the unread divider.
            scrollToMessageId = nil
        } else {
            // If we're not scrolling to a specific message AND we don't have any
            // unread messages, try to focus on the last visible interaction.
            let lastVisibleMessageId = Self.lastVisibleInteractionId(for: threadViewModel.threadRecord, tx: tx)
            loadAroundMessageId = lastVisibleMessageId
            scrollToMessageId = lastVisibleMessageId
        }

        let chatColor = Self.loadChatColor(for: thread, tx: tx)
        let wallpaperViewBuilder = Self.loadWallpaperViewBuilder(for: thread, tx: tx)

        let conversationStyle = Self.buildInitialConversationStyle(
            for: thread, chatColor: chatColor, wallpaperViewBuilder: wallpaperViewBuilder
        )
        let conversationViewModel = ConversationViewModel.load(for: thread, tx: tx)
        let didAlreadyShowGroupCallTooltipEnoughTimes = SSKEnvironment.shared.preferencesRef.wasGroupCallTooltipShown(withTransaction: tx)

        let cvc = ConversationViewController(
            appReadiness: appReadiness,
            threadViewModel: threadViewModel,
            conversationViewModel: conversationViewModel,
            action: action,
            conversationStyle: conversationStyle,
            didAlreadyShowGroupCallTooltipEnoughTimes: didAlreadyShowGroupCallTooltipEnoughTimes,
            loadAroundMessageId: loadAroundMessageId,
            scrollToMessageId: scrollToMessageId,
            oldestUnreadMessage: oldestUnreadMessage,
            chatColor: chatColor,
            wallpaperViewBuilder: wallpaperViewBuilder
        )

        return cvc
    }

    static func loadChatColor(for thread: TSThread, tx: DBReadTransaction) -> ColorOrGradientSetting {
        return DependenciesBridge.shared.chatColorSettingStore.resolvedChatColor(
            for: thread,
            tx: tx
        )
    }

    static func loadWallpaperViewBuilder(for thread: TSThread, tx: DBReadTransaction) -> WallpaperViewBuilder? {
        return Wallpaper.viewBuilder(for: thread, tx: tx)
    }

    private init(
        appReadiness: AppReadinessSetter,
        threadViewModel: ThreadViewModel,
        conversationViewModel: ConversationViewModel,
        action: ConversationViewAction,
        conversationStyle: ConversationStyle,
        didAlreadyShowGroupCallTooltipEnoughTimes: Bool,
        loadAroundMessageId: String?,
        scrollToMessageId: String?,
        oldestUnreadMessage: TSInteraction?,
        chatColor: ColorOrGradientSetting,
        wallpaperViewBuilder: WallpaperViewBuilder?
    ) {
        AssertIsOnMainThread()

        self.appReadiness = appReadiness
        self.context = ViewControllerContext.shared

        self.viewState = CVViewState(
            threadUniqueId: threadViewModel.threadRecord.uniqueId,
            conversationStyle: conversationStyle,
            didAlreadyShowGroupCallTooltipEnoughTimes: didAlreadyShowGroupCallTooltipEnoughTimes,
            chatColor: chatColor,
            wallpaperViewBuilder: wallpaperViewBuilder
        )
        self.loadCoordinator = CVLoadCoordinator(
            viewState: viewState,
            threadViewModel: threadViewModel,
            conversationViewModel: conversationViewModel,
            oldestUnreadMessageSortId: oldestUnreadMessage?.sortId
        )
        self.layout = ConversationViewLayout(conversationStyle: conversationStyle)
        self.collectionView = ConversationCollectionView(frame: .zero, collectionViewLayout: self.layout)
        self.searchController = ConversationSearchController(thread: threadViewModel.threadRecord)

        super.init()

        self.viewState.delegate = self
        self.viewState.selectionState.delegate = self
        self.hidesBottomBarWhenPushed = true

        self.inputAccessoryPlaceholder.delegate = self

        SUIEnvironment.shared.contactsViewHelperRef.addObserver(self)

        self.actionOnOpen = action

        self.recordInitialScrollState(scrollToMessageId)

        loadCoordinator.configure(
            delegate: self,
            componentDelegate: self,
            focusMessageIdOnOpen: loadAroundMessageId
        )

        searchController.delegate = self

        // because the search bar view is hosted in the navigation bar, it's not in the CVC's responder
        // chain, and thus won't inherit our inputAccessoryView, so we manually set it here.
        searchController.uiSearchController.searchBar.inputAccessoryView = self.inputAccessoryPlaceholder

        self.otherUsersProfileDidChangeEvent = DebouncedEvents.build(
            mode: .firstLast,
            maxFrequencySeconds: 1.0,
            onQueue: .main
        ) { [weak self] in
            // Reload all cells if this is a group conversation,
            // since we may need to update the sender names on the messages.
            self?.loadCoordinator.enqueueReload(canReuseInteractionModels: true, canReuseComponentStates: false)
        }
    }

    deinit {
        reloadTimer?.invalidate()
        scrollUpdateTimer?.invalidate()
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        AssertIsOnMainThread()

        // We won't have a navigation controller if we're presented in a preview
        owsAssertDebug(self.navigationController != nil || self.isInPreviewPlatter)

        super.viewDidLoad()

        createContents()
        createConversationScrollButtons()
        createHeaderViews()
        addNotificationListeners()
        loadCoordinator.viewDidLoad()

        self.startReloadTimer()
    }

    private func createContents() {
        AssertIsOnMainThread()

        self.layout.delegate = self.loadCoordinator

        // We use the root view bounds as the initial frame for the collection
        // view so that its contents can be laid out immediately.
        //
        // TODO: To avoid relayout, it'd be better to take into account safeAreaInsets,
        //       but they're not yet set when this method is called.
        self.collectionView.frame = view.bounds
        self.collectionView.layoutDelegate = self
        self.collectionView.delegate = self.loadCoordinator
        self.collectionView.dataSource = self.loadCoordinator
        self.collectionView.showsVerticalScrollIndicator = true
        self.collectionView.showsHorizontalScrollIndicator = false
        self.collectionView.keyboardDismissMode = .interactive
        self.collectionView.allowsMultipleSelection = true
        self.collectionView.backgroundColor = .clear

        // To minimize time to initial apearance, we initially disable prefetching, but then
        // re-enable it once the view has appeared.
        self.collectionView.isPrefetchingEnabled = false

        self.view.addSubview(self.collectionView)
        self.collectionView.autoPinEdge(toSuperviewEdge: .top)
        self.collectionView.autoPinEdge(toSuperviewEdge: .bottom)
        self.collectionView.autoPinEdge(toSuperviewSafeArea: .leading)
        self.collectionView.autoPinEdge(toSuperviewSafeArea: .trailing)

        self.collectionView.accessibilityIdentifier = "collectionView"

        self.registerReuseIdentifiers()

        // The view controller will only automatically adjust content insets for a
        // scrollView at index 0, so we need the collection view to remain subview index 0.
        // But the background views should appear visually behind the collection view.
        let backgroundContainer = self.backgroundContainer
        backgroundContainer.delegate = self
        self.view.addSubview(backgroundContainer)
        backgroundContainer.autoPinEdgesToSuperviewEdges()
        setUpWallpaper()

        self.view.addSubview(bottomBar)
        self.bottomBarBottomConstraint = bottomBar.autoPinEdge(toSuperviewEdge: .bottom)
        bottomBar.autoPinWidthToSuperview()

        self.selectionToolbar = self.buildSelectionToolbar()

        // This should kick off the first load.
        owsAssertDebug(!self.hasRenderState)
        self.updateConversationStyle()
    }

    public override var canBecomeFirstResponder: Bool {
        return true
    }

    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()

        guard hasViewWillAppearEverBegun else {
            return result
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return result
        }

        // If we become the first responder, it means that the
        // input toolbar is not the first responder. As such,
        // we should clear out the desired keyboard since an
        // interactive dismissal may have just occurred and we
        // need to update the UI to reflect that fact. We don't
        // actually ever want to be the first responder, so resign
        // immediately. We just want to know when the responder
        // state of our children changed and that information is
        // conveniently bubbled up the responder chain.
        if result {
            self.resignFirstResponder()
            inputToolbar.clearDesiredKeyboard()
        }

        return result
    }

    public override var inputAccessoryView: UIView? {
        inputAccessoryPlaceholder
    }

    public override var textInputContextIdentifier: String? {
        thread.uniqueId
    }

    public func dismissPresentedViewControllerIfNecessary() {
        guard let presentedViewController = self.presentedViewController else {
            return
        }

        if presentedViewController is ActionSheetController || presentedViewController is UIAlertController {
            dismiss(animated: false, completion: nil)
            return
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        self.viewWillAppearDidBegin()

        super.viewWillAppear(animated)

        if self.inputToolbar == nil {
            // This will create the input toolbar for the first time.
            // It's important that we do this at the "last moment" to
            // avoid expensive work that delays CVC presentation.
            self.applyTheme()
            owsAssertDebug(self.inputToolbar != nil)

            self.createGestureRecognizers()
        } else {
            self.ensureBannerState()
        }

        self.isViewVisible = true
        self.viewWillAppearForLoad()

        // We should have already requested contact access at this point, so this should be a no-op
        // unless it ever becomes possible to load this VC without going via the ChatListViewController.
        SSKEnvironment.shared.contactManagerImplRef.requestSystemContactsOnce()

        self.updateBarButtonItems()
        self.updateNavigationTitle()

        self.ensureBottomViewType()
        self.updateInputToolbarLayout(initialLayout: true)
        self.refreshCallState()

        self.showMessageRequestDialogIfRequired()
        self.viewWillAppearDidComplete()
    }

    private var groupAndProfileRefresherTask: Task<Void, any Error>?

    public override func viewDidAppear(_ animated: Bool) {
        self.viewDidAppearDidBegin()

        super.viewDidAppear(animated)

        // We don't present incoming message notifications for the presented
        // conversation. But there's a narrow window *while* the conversationVC
        // is being presented where a message notification for the not-quite-yet
        // presented conversation can be shown. If that happens, dismiss it as soon
        // as we enter the conversation.
        SSKEnvironment.shared.notificationPresenterRef.cancelNotifications(threadId: thread.uniqueId)

        // recover status bar when returning from PhotoPicker, which is dark (uses light status bar)
        self.setNeedsStatusBarAppearanceUpdate()

        self.markVisibleMessagesAsRead()
        self.startReadTimer()
        self.updateNavigationBarSubtitleLabel()
        self.autoLoadMoreIfNecessary()

        let serviceIds = thread.recipientAddressesWithSneakyTransaction.compactMap(\.serviceId)

        self.groupAndProfileRefresherTask?.cancel()
        self.groupAndProfileRefresherTask = Task {
            await self.updateV2GroupIfNecessary()

            // Fetch profiles AFTER refreshing the group to ensure GSEs are available.
            let profileFetcher = SSKEnvironment.shared.profileFetcherRef
            for serviceId in Set(serviceIds).shuffled() {
                try Task.checkCancellation()
                let thread = self.thread as? TSGroupThread
                let context = ProfileFetchContext(groupId: try? thread?.groupIdentifier, isOpportunistic: true)
                _ = try? await profileFetcher.fetchProfile(for: serviceId, context: context)
            }
        }

        if !self.viewHasEverAppeared {
            // To minimize time to initial apearance, we initially disable prefetching, but then
            // re-enable it once the view has appeared.
            self.collectionView.isPrefetchingEnabled = true
        }

        self.isViewCompletelyAppeared = true
        self.shouldAnimateKeyboardChanges = true

        switch self.actionOnOpen {
        case .none:
            break
        case .compose:
            // Don't pop the keyboard if we have a pending message request, since
            // the user can't currently send a message until acting on this
            if nil == requestView {
                self.popKeyBoard()
            }
        case .voiceCall:
            self.startIndividualAudioCall()
        case .videoCall:
            self.startIndividualVideoCall()
        case .groupCallLobby:
            self.showGroupLobbyOrActiveCall()
        case .newGroupActionSheet:
            DispatchQueue.main.async { [weak self] in
                self?.showGroupLinkPromotionActionSheet()
            }
        case .updateDraft:
            // Do nothing input toolbar was just created with the latest draft.
            break
        }

        scrollToInitialPosition(animated: false)
        if viewState.hasAppliedFirstLoad {
            self.clearInitialScrollState()
        }

        // Clear the "on open" state after the view has been presented.
        self.actionOnOpen = .none

        self.updateInputToolbarLayout()
        self.configureScrollDownButtons()
        inputToolbar?.viewDidAppear()

        self.viewDidAppearDidComplete()
    }

    // `viewWillDisappear` is called whenever the view *starts* to disappear,
    // but, as is the case with the "pan left for message details view" gesture,
    // this can be canceled. As such, we shouldn't tear down anything expensive
    // until `viewDidDisappear`.
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.isViewCompletelyAppeared = false

        dismissMessageContextMenu(animated: false)

        self.dismissReactionsDetailSheet(animated: false)
        self.saveLastVisibleSortIdAndOnScreenPercentage(async: true)

        self.groupAndProfileRefresherTask?.cancel()
        self.groupAndProfileRefresherTask = nil
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.userHasScrolled = false
        self.isViewVisible = false
        self.shouldAnimateKeyboardChanges = false

        AppEnvironment.shared.cvAudioPlayerRef.stopAll()

        self.cancelReadTimer()
        self.saveDraft()
        self.markVisibleMessagesAsRead()
        self.finishRecordingVoiceMessage(sendImmediately: false)
        self.mediaCache.removeAllObjects()
        inputToolbar?.clearDesiredKeyboard()

        self.isUserScrolling = false
        self.isWaitingForDeceleration = false

        self.scrollingAnimationCompletionTimer?.invalidate()
        self.scrollingAnimationCompletionTimer = nil
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Title view sometimes disappears when orientation changes.
        // Reset it here as a workaround.
        navigationItem.titleView = nil
        navigationItem.titleView = headerView

        guard hasViewWillAppearEverBegun else {
            return
        }
        guard nil != inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        // We resize the inputToolbar whenever it's text is modified, including when setting saved draft-text.
        // However it's possible this draft-text is set before the inputToolbar (an inputAccessoryView) is mounted
        // in the view hierarchy. Since it's not in the view hierarchy, it hasn't been laid out and has no width,
        // which is used to determine height.
        // So here we unsure the proper height once we know everything's been laid out.
        self.inputToolbar?.ensureTextViewHeight()

        self.positionGroupCallTooltip()
    }

    public override var shouldAutorotate: Bool {
        // Don't allow orientation changes while recording voice messages.
        if viewState.inProgressVoiceMessage?.isRecording == true {
            return false
        }

        return super.shouldAutorotate
    }

    public override func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()

        Logger.info("didChangePreferredContentSize")

        resetForSizeOrOrientationChange()

        guard hasViewWillAppearEverBegun else {
            return
        }
        guard let inputToolbar = inputToolbar else {
            owsFailDebug("Missing inputToolbar.")
            return
        }

        inputToolbar.updateFontSizes()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        applyTheme()
        self.updateThemeIfNecessary()
    }

    private func updateThemeIfNecessary() {
        AssertIsOnMainThread()

        if self.isDarkThemeEnabled == Theme.isDarkThemeEnabled {
            return
        }
        self.isDarkThemeEnabled = Theme.isDarkThemeEnabled

        self.updateConversationStyle()

        self.applyTheme()
    }

    private func applyTheme() {
        guard hasViewWillAppearEverBegun else {
            owsFailDebug("Not yet ready.")
            return
        }

        // make sure toolbar extends below iPhoneX home button.
        self.view.backgroundColor = Theme.toolbarBackgroundColor

        self.updateWallpaperView()

        self.updateNavigationTitle()
        self.updateNavigationBarSubtitleLabel()

        self.updateInputToolbar()
        self.updateInputToolbarLayout()
        self.updateBarButtonItems()
        self.ensureBannerState()

        dismissReactionsDetailSheet(animated: false)
    }

    func reloadCollectionViewForReset() {
        AssertIsOnMainThread()

        guard hasAppearedAndHasAppliedFirstLoad else {
            return
        }
        // We use an obj-c free function so that we can handle NSException.
        self.collectionView.cvc_reloadData(animated: false, cvc: self)
    }

    var isViewVisible: Bool {
        get { viewState.isViewVisible }
        set {
            viewState.isViewVisible = newValue

            updateCellsVisible()
        }
    }

    func updateCellsVisible() {
        AssertIsOnMainThread()

        let isAppInBackground = CurrentAppContext().isInBackground()
        let isCellVisible = self.isViewVisible && !isAppInBackground
        for cell in self.collectionView.visibleCells {
            guard let cell = cell as? CVCell else {
                owsFailDebug("Invalid cell.")
                continue
            }
            cell.isCellVisible = isCellVisible
        }
        self.updateScrollingContent()
    }

    // MARK: - Orientation

    public override func viewWillTransition(to size: CGSize,
                                            with coordinator: UIViewControllerTransitionCoordinator) {
        AssertIsOnMainThread()

        super.viewWillTransition(to: size, with: coordinator)

        dismissReactionsDetailSheet(animated: false)

        guard hasAppearedAndHasAppliedFirstLoad else {
            return
        }

        self.setScrollActionForSizeTransition()

        _ = coordinator.animate(
            alongsideTransition: { _ in
            },
            completion: { [weak self] _ in
                self?.clearScrollActionForSizeTransition()
            })
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        AssertIsOnMainThread()

        self.updateBarButtonItems()
        self.updateNavigationBarSubtitleLabel()

        // Invoking -ensureBannerState synchronously can lead to reenterant updates to the
        // trait collection while building the banners. This can lead us to blow out the stack
        // on unrelated trait collection changes (e.g. rotating to landscape).
        // We workaround this by just asyncing any banner updates to break the synchronous
        // dependency chain.
        DispatchQueue.main.async {
            self.ensureBannerState()
        }
    }

    public override func viewSafeAreaInsetsDidChange() {
        AssertIsOnMainThread()

        super.viewSafeAreaInsetsDidChange()

        updateContentInsetsDebounced()
        self.updateInputToolbarLayout()
        self.viewSafeAreaInsetsDidChangeForLoad()
        self.updateConversationStyle()
    }
}

// MARK: -

// TODO: Is this necessary?
extension ConversationViewController: UINavigationControllerDelegate {
}

// MARK: -

extension ConversationViewController: ContactsViewHelperObserver {
    public func contactsViewHelperDidUpdateContacts() {
        AssertIsOnMainThread()

        loadCoordinator.enqueueReload(canReuseInteractionModels: true, canReuseComponentStates: false)
    }
}
