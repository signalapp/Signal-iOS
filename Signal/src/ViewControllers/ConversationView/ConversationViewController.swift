//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

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

// MARK: -

public class ConversationViewController: OWSViewController {

    public let viewState: CVViewState
    public let loadCoordinator: CVLoadCoordinator
    public let layout: ConversationViewLayout
    public let collectionView: ConversationCollectionView
    public let searchController: ConversationSearchController

    var selectionToolbar: MessageActionsToolbar?

    var otherUsersProfileDidChangeEvent: DebouncedEvent?
    private var leases = [ModelReadCacheSizeLease]()

    // MARK: -

    @objc
    public required init(threadViewModel: ThreadViewModel,
                         action: ConversationViewAction = .none,
                         focusMessageId: String? = nil) {
        AssertIsOnMainThread()

        Logger.verbose("")

        let conversationStyle = ConversationViewController.buildInitialConversationStyle(threadViewModel: threadViewModel)
        self.viewState = CVViewState(threadViewModel: threadViewModel,
                                     conversationStyle: conversationStyle)
        self.loadCoordinator = CVLoadCoordinator(viewState: viewState)
        self.layout = ConversationViewLayout(conversationStyle: conversationStyle)
        self.collectionView = ConversationCollectionView(frame: .zero,
                                                         collectionViewLayout: self.layout)

        self.searchController = ConversationSearchController(thread: threadViewModel.threadRecord)

        super.init()

        self.viewState.delegate = self
        self.viewState.selectionState.delegate = self
        self.hidesBottomBarWhenPushed = true

        #if TESTABLE_BUILD
        self.initialLoadBenchSteps.step("Init CVC")
        #endif

        self.inputAccessoryPlaceholder.delegate = self

        // If we're not scrolling to a specific message AND we don't have
        // any unread messages, try to focus on the last visible interaction.
        var focusMessageId = focusMessageId
        if focusMessageId == nil, !threadViewModel.hasUnreadMessages {
            focusMessageId = self.lastVisibleInteractionIdWithSneakyTransaction(threadViewModel)
        }

        contactsViewHelper.addObserver(self)
        contactShareViewHelper.delegate = self

        self.actionOnOpen = action

        self.recordInitialScrollState(focusMessageId)

        loadCoordinator.configure(delegate: self,
                                  componentDelegate: self,
                                  focusMessageIdOnOpen: focusMessageId)

        searchController.delegate = self

        // because the search bar view is hosted in the navigation bar, it's not in the CVC's responder
        // chain, and thus won't inherit our inputAccessoryView, so we manually set it here.
        searchController.uiSearchController.searchBar.inputAccessoryView = self.inputAccessoryPlaceholder

        self.otherUsersProfileDidChangeEvent = DebouncedEvents.build(mode: .firstLast,
                                                                     maxFrequencySeconds: 1.0,
                                                                     onQueue: .asyncOnQueue(queue: .main)) { [weak self] in
            // Reload all cells if this is a group conversation,
            // since we may need to update the sender names on the messages.
            self?.loadCoordinator.enqueueReload(canReuseInteractionModels: true,
                                                canReuseComponentStates: false)
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

        #if TESTABLE_BUILD
        initialLoadBenchSteps.step("viewDidLoad.1")
        #endif

        super.viewDidLoad()

        createContents()
        createConversationScrollButtons()
        createHeaderViews()
        addNotificationListeners()
        loadCoordinator.viewDidLoad()

        self.startReloadTimer()

        #if TESTABLE_BUILD
        initialLoadBenchSteps.step("viewDidLoad.2")
        #endif
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
        setupWallpaper()

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
            Logger.verbose("presentedViewController was nil")
            return
        }

        if presentedViewController is ActionSheetController ||
            presentedViewController is UIAlertController {
            Logger.verbose("Dismissing presentedViewController: \(type(of: presentedViewController))")
            dismiss(animated: false, completion: nil)
            return
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        self.viewWillAppearDidBegin()

        #if TESTABLE_BUILD
        initialLoadBenchSteps.step("viewWillAppear.1")
        #endif

        Logger.verbose("viewWillAppear")

        super.viewWillAppear(animated)

        if let groupThread = thread as? TSGroupThread {
            acquireCacheLeases(groupThread)
        }

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
        self.contactsManagerImpl.requestSystemContactsOnce()

        self.updateBarButtonItems()
        self.updateNavigationTitle()

        // One-time work performed the first time we enter the view.
        if !self.viewHasEverAppeared {
            BenchManager.completeEvent(eventId: String(format: "presenting-conversation-\(thread.uniqueId)"))
        }
        self.ensureBottomViewType()
        self.updateInputToolbarLayout()
        self.refreshCallState()

        self.showMessageRequestDialogIfRequired()
        self.viewWillAppearDidComplete()
        #if TESTABLE_BUILD
        initialLoadBenchSteps.step("viewWillAppear.2")
        #endif
    }

    private func acquireCacheLeases(_ groupThread: TSGroupThread) {
        guard leases.isEmpty else {
            // Hold leases for the CVC's lifetime because a view controller may "viewDidAppear" more than once without
            // leaving the navigation controller's stack.
            return
        }
        let numberOfGroupMembers = groupThread.groupModel.groupMembers.count
        leases = [groupThread.profileManager.leaseCacheSize(numberOfGroupMembers),
                  groupThread.contactsManager.leaseCacheSize(numberOfGroupMembers),
                  groupThread.modelReadCaches.signalAccountReadCache.leaseCacheSize(numberOfGroupMembers)].compactMap { $0 }
    }

    public override func viewDidAppear(_ animated: Bool) {
        self.viewDidAppearDidBegin()

        InstrumentsMonitor.trackEvent(name: "ConversationViewController.viewDidAppear")

        #if TESTABLE_BUILD
        initialLoadBenchSteps.step("viewDidAppear.1")
        #endif
        Logger.verbose("viewDidAppear")

        super.viewDidAppear(animated)

        // We don't present incoming message notifications for the presented
        // conversation. But there's a narrow window *while* the conversationVC
        // is being presented where a message notification for the not-quite-yet
        // presented conversation can be shown. If that happens, dismiss it as soon
        // as we enter the conversation.
        self.notificationPresenter.cancelNotifications(threadId: thread.uniqueId)

        // recover status bar when returning from PhotoPicker, which is dark (uses light status bar)
        self.setNeedsStatusBarAppearanceUpdate()

        self.markVisibleMessagesAsRead()
        self.startReadTimer()
        self.updateNavigationBarSubtitleLabel()
        _ = self.autoLoadMoreIfNecessary()
        if !DebugFlags.reduceLogChatter {
            self.bulkProfileFetch.fetchProfiles(thread: thread)
            self.updateV2GroupIfNecessary()
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
        case .audioCall:
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

        if !self.viewState.hasTriedToMigrateGroup {
            self.viewState.hasTriedToMigrateGroup = true

            if !DebugFlags.reduceLogChatter {
                GroupsV2Migration.autoMigrateThreadIfNecessary(thread: thread)
            }
        }

        self.viewDidAppearDidComplete()
        #if TESTABLE_BUILD
        initialLoadBenchSteps.step("viewDidAppear.2")
        #endif
    }

    // `viewWillDisappear` is called whenever the view *starts* to disappear,
    // but, as is the case with the "pan left for message details view" gesture,
    // this can be canceled. As such, we shouldn't tear down anything expensive
    // until `viewDidDisappear`.
    public override func viewWillDisappear(_ animated: Bool) {
        Logger.verbose("")

        super.viewWillDisappear(animated)

        self.isViewCompletelyAppeared = false

        dismissMessageContextMenu(animated: false)

        self.dismissReactionsDetailSheet(animated: false)
        self.saveLastVisibleSortIdAndOnScreenPercentage(async: true)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        Logger.verbose("")

        super.viewDidDisappear(animated)

        InstrumentsMonitor.trackEvent(name: "ConversationViewController.viewDidDisappear")

        self.userHasScrolled = false
        self.isViewVisible = false
        self.shouldAnimateKeyboardChanges = false

        self.cvAudioPlayer.stopAll()

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
        if let currentVoiceMessageModel = viewState.currentVoiceMessageModel,
           currentVoiceMessageModel.isRecording {
            return false
        }

        return super.shouldAutorotate
    }

    public override func themeDidChange() {
        super.themeDidChange()

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

    public override func applyTheme() {
        AssertIsOnMainThread()

        super.applyTheme()

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

        updateContentInsets(animated: false)
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

        self.updateNavigationTitle()
        loadCoordinator.enqueueReload(canReuseInteractionModels: true,
                                      canReuseComponentStates: false)
    }
}
