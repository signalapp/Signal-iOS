//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension ConversationViewController {

    public var isGroupConversation: Bool { thread.isGroupThread }

    public static var messageSection: Int { CVLoadCoordinator.messageSection }

    public var hasRenderState: Bool { !renderState.isEmptyInitialState }

    public var hasAppearedAndHasAppliedFirstLoad: Bool {
        (hasRenderState &&
            hasViewDidAppearEverBegun &&
            !loadCoordinator.shouldHideCollectionViewContent)
    }

    public var lastReloadDate: Date { renderState.loadDate }

    public func indexPath(forInteractionUniqueId interactionUniqueId: String) -> IndexPath? {
        loadCoordinator.indexPath(forInteractionUniqueId: interactionUniqueId)
    }

    public func indexPath(forItemViewModel itemViewModel: CVItemViewModelImpl) -> IndexPath? {
        indexPath(forInteractionUniqueId: itemViewModel.interaction.uniqueId)
    }

    public func interaction(forIndexPath indexPath: IndexPath) -> TSInteraction? {
        guard let renderItem = self.renderItem(forIndex: indexPath.row) else {
            return nil
        }
        return renderItem.interaction
    }

    var indexPathOfUnreadMessagesIndicator: IndexPath? {
        loadCoordinator.indexPathOfUnreadIndicator
    }

    public var canLoadOlderItems: Bool {
        loadCoordinator.canLoadOlderItems
    }

    public var canLoadNewerItems: Bool {
        loadCoordinator.canLoadNewerItems
    }

    public var currentRenderStateDebugDescription: String {
        renderState.debugDescription
    }

    public var isLayoutApplyingUpdate: Bool {
        layout.isPerformBatchUpdatesOrReloadDataBeingAppliedOrSettling
    }

    public var areCellsAnimating: Bool {
        viewState.activeCellAnimations.count > 0
    }
}

// MARK: -

extension ConversationViewController: CVLoadCoordinatorDelegate {

    public var conversationViewController: ConversationViewController? {
        self
    }

    func chatColorDidChange() {
        updateConversationStyle()
    }

    func updateAccessibilityCustomActionsForCell(_ cell: CVItemCell) {
        if let cvcell = cell as? CVCell {
            updateAccessibilityCustomActionsForCell(cell: cvcell)
        }
    }

    func willUpdateWithNewRenderState(_ renderState: CVRenderState) -> CVUpdateToken {
        AssertIsOnMainThread()

        // HACK to work around radar #28167779
        // "UICollectionView performBatchUpdates can trigger a crash if the collection view is flagged for layout"
        // more: https://github.com/PSPDFKit-labs/radar.apple.com/tree/master/28167779%20-%20CollectionViewBatchingIssue
        // This was our #2 crash, and much exacerbated by the refactoring somewhere between 2.6.2.0-2.6.3.8
        //
        // NOTE: It's critical we do this before beginLongLivedReadTransaction.
        //       We want to relayout our contents using the old message mappings and
        //       view items before they are updated.
        collectionView.layoutIfNeeded()
        // ENDHACK to work around radar #28167779

        // Snapshot CVC layout state before we land the load;
        // we use this to ensure scroll continuity when landing the load.
        let scrollContinuityToken = layout.buildScrollContinuityToken()

        // CVC will often use this state to ensure scroll continuity
        // when landing loads, so ensure the value is updated before
        // landing loads.
        let lastKnownDistanceFromBottom = self.updateLastKnownDistanceFromBottom()

        return CVUpdateToken(isScrolledToBottom: self.isScrolledToBottom,
                             lastMessageForInboxSortId: threadViewModel.lastMessageForInbox?.sortId,
                             scrollContinuityToken: scrollContinuityToken,
                             lastKnownDistanceFromBottom: lastKnownDistanceFromBottom)
    }

    func updateWithNewRenderState(update: CVUpdate,
                                  scrollAction: CVScrollAction,
                                  updateToken: CVUpdateToken) {
        AssertIsOnMainThread()

        guard hasViewWillAppearEverBegun else {
            // It's safe to ignore updates before viewWillAppear
            // if called for the first time.

            Logger.info("View is not yet loaded.")
            loadDidLand(renderState: update.renderState)
            return
        }

        let benchSteps = BenchSteps(title: "updateWithNewRenderState")

        let renderState = update.renderState
        let isFirstLoad = renderState.isFirstLoad

        layout.update(conversationStyle: renderState.conversationStyle)

        var scrollAction = scrollAction
        if !viewState.hasAppliedFirstLoad {
            scrollAction = CVScrollAction(action: .initialPosition, isAnimated: false)
        } else if let scrollActionForSizeTransition = viewState.scrollActionForSizeTransition {
            // If we're in a size transition, honor the relevant scroll action.
            scrollAction = scrollActionForSizeTransition
        }

        // Capture old group model before we update threadViewModel.
        // This will be nil for non-group threads.
        let oldGroupModel = renderState.prevThreadViewModel?.threadRecord.groupModelIfGroupThread

        benchSteps.step("1")

        updateNavigationBarSubtitleLabel()
        updateBarButtonItems()

        // This will be nil for non-group threads.
        let newGroupModel = thread.groupModelIfGroupThread
        if oldGroupModel != newGroupModel {
            ensureBannerState()
        }

        // If the message has been deleted / disappeared, we need to dismiss
        dismissMessageContextMenuIfNecessary()

        showMessageRequestDialogIfRequiredAsync()

        if thread.isGroupThread {
            updateNavigationTitle()
        }

        Logger.verbose("Landing load: \(update.type.debugName), load: \(update.loadType), isFirstLoad: \(isFirstLoad), renderItems: \(update.prevRenderState.items.count) -> \(renderItems.count), scrollAction: \(scrollAction.description)")

        benchSteps.step("2")

        updateShouldHideCollectionViewContent(reloadIfClearingFlag: false)

        benchSteps.step("3")

        if loadCoordinator.shouldHideCollectionViewContent {

            Logger.verbose("Not applying load.")

            updateViewToReflectLoad(loadedRenderState: self.renderState)

            benchSteps.step("4a")

            loadDidLand(renderState: update.renderState)

            benchSteps.step("5a")
        } else {
            if !viewState.hasAppliedFirstLoad {
                // Ignore scrollAction; we need to scroll to .initialPosition.
                updateWithFirstLoad(update: update)
            } else {
                switch update.type {
                case .minor:
                    updateForMinorUpdate(update: update, scrollAction: scrollAction)
                case .reloadAll:
                    updateReloadingAll(renderState: renderState, scrollAction: scrollAction)
                case .diff(let items, let threadInteractionCount, let shouldAnimateUpdate):
                    updateWithDiff(update: update,
                                   items: items,
                                   shouldAnimateUpdate: shouldAnimateUpdate,
                                   scrollAction: scrollAction,
                                   threadInteractionCount: threadInteractionCount,
                                   updateToken: updateToken)
                }
            }

            benchSteps.step("4b")

            setHasAppliedFirstLoadIfNecessary()

            benchSteps.step("5b")
        }

        benchSteps.logAll()
    }

    // The more work we put into this method, the greater our
    // confidence we have that CVC view state is always up-to-date.
    // But that can make "minor update" updates more expensive.
    private func updateViewToReflectLoad(loadedRenderState: CVRenderState) {

        // We can skip some of this work
        guard self.hasViewWillAppearEverBegun else {
            return
        }

        let benchSteps = BenchSteps()

        self.updateLastKnownDistanceFromBottom()
        self.updateInputToolbarLayout()
        self.showMessageRequestDialogIfRequired()
        self.configureScrollDownButtons()

        benchSteps.step("loadCompletion.1")

        let hasViewDidAppearEverCompleted = self.hasViewDidAppearEverCompleted

        DispatchQueue.main.async {
            let benchSteps = BenchSteps()
            Self.databaseStorage.read { transaction in
                self.reloadReactionsDetailSheet(transaction: transaction)
                self.updateUnreadMessageFlag(transaction: transaction)
            }
            if hasViewDidAppearEverCompleted {
                _ = self.autoLoadMoreIfNecessary()
            }
            benchSteps.step("loadCompletion.2")
        }
    }

    private func loadDidLand(renderState: CVRenderState) {
        switch viewState.selectionAnimationState {
        case .willAnimate:
            viewState.selectionAnimationState = .animating
        case .animating, .idle:
            viewState.selectionAnimationState = .idle
            ensureBottomViewType()
        }

        self.loadCoordinator.loadDidLandInView(renderState: renderState)
    }

    // The view's first appearance and the first load can race.
    // We need to handle them completing in either order.
    //
    // This means performing much of the work we do when we land
    // the first load.
    public func viewWillAppearForLoad() {
        updateShouldHideCollectionViewContent(reloadIfClearingFlag: true)
    }

    public func viewSafeAreaInsetsDidChangeForLoad() {
        updateShouldHideCollectionViewContent(reloadIfClearingFlag: true)
    }

    // One of the inconveniences of iOS view presentation is that the
    // safeAreaInsets are set after viewWillAppear() and before
    // viewDidAppear(). We kick off our first load when view presentation
    // begins, but that load will have the wrong layout.
    //
    // Another considerations is that the view events (viewWillAppear(),
    // safeAreaInsets being set) can race with the first load(s).
    //
    // We use the shouldHideCollectionViewContent flag to handle these
    // issues. We don't "apply" loads until this flag is set. The flag
    // isn't set until:
    //
    // * viewWillAppear() has occurred at least once.
    // * safeAreaInsets is non-zero (if appropriate).
    // * At least one load has landed that has an appropriate safeAreaInsets
    //   value.
    //
    // This ensures that we don't render mis-formatted content during
    // view presentation.
    private func updateShouldHideCollectionViewContent(reloadIfClearingFlag: Bool) {
        // We hide collection view content until the view
        // appears for the first time.  Once we've cleared
        // the flag, never set it again.
        guard loadCoordinator.shouldHideCollectionViewContent else {
            return
        }

        let shouldHideCollectionViewContent: Bool = {
            // Don't hide content for more than a couple of seconds.
            let viewAge = abs(self.viewState.viewCreationDate.timeIntervalSinceNow)
            let maxHideTime = kSecondInterval * 2
            guard viewAge < maxHideTime else {
                // This should only occur on very slow devices.
                Logger.warn("View taking a long time to render content.")
                return false
            }

            // Hide content until "viewWillAppear()" is called for the
            // first time.
            guard self.hasViewWillAppearEverBegun else {
                return true
            }
            // Hide content until the first load lands.
            guard self.hasRenderState else {
                return true
            }
            guard renderState.conversationStyle.isValidStyle else {
                return true
            }
            return false
        }()

        guard !shouldHideCollectionViewContent else {
            return
        }

        loadCoordinator.shouldHideCollectionViewContent = false

        // Completion of the first load can race with the
        // view appearing for the first time. If the first load
        // completes first, we need to update the collection view
        // to reflect its contents.
        if reloadIfClearingFlag, hasRenderState {
            reloadCollectionViewImmediately()

            scrollToInitialPosition(animated: false)

            updateViewToReflectLoad(loadedRenderState: self.renderState)

            loadCoordinator.enqueueReload()

            setHasAppliedFirstLoadIfNecessary()
        }
    }

    private func reloadCollectionViewImmediately() {
        AssertIsOnMainThread()

        self.collectionView.cvc_reloadData(animated: false, cvc: self)
    }

    private func updateForMinorUpdate(update: CVUpdate, scrollAction: CVScrollAction) {
        Logger.verbose("")

        // If the scroll action is not animated, perform it _before_
        // updateViewToReflectLoad().
        if !scrollAction.isAnimated {
            self.perform(scrollAction: scrollAction)
        }

        updateViewToReflectLoad(loadedRenderState: self.renderState)

        loadDidLand(renderState: update.renderState)

        if scrollAction.isAnimated {
            self.perform(scrollAction: scrollAction)
        }
    }

    private func updateWithFirstLoad(update: CVUpdate) {

        let benchSteps = BenchSteps(title: "updateWithFirstLoad")

        #if TESTABLE_BUILD
        initialLoadBenchSteps.step("updateWithFirstLoad.1")
        #endif

        Logger.verbose("")

        benchSteps.step("1")

        reloadCollectionViewImmediately()

        benchSteps.step("2")

        scrollToInitialPosition(animated: false)
        if self.hasViewDidAppearEverCompleted {
            clearInitialScrollState()
        }

        benchSteps.step("3")

        updateViewToReflectLoad(loadedRenderState: self.renderState)

        benchSteps.step("4")

        loadDidLand(renderState: update.renderState)

        benchSteps.step("5")

        benchSteps.logAll()

        #if TESTABLE_BUILD
        initialLoadBenchSteps.step("updateWithFirstLoad.2")
        initialLoadBenchSteps.logAll()
        #endif
    }

    private func setHasAppliedFirstLoadIfNecessary() {

        guard !viewState.hasAppliedFirstLoad else {
            return
        }
        viewState.hasAppliedFirstLoad = true
        if self.hasViewDidAppearEverCompleted {
            clearInitialScrollState()
        }
    }

    private func updateReloadingAll(renderState: CVRenderState,
                                    scrollAction: CVScrollAction) {

        Logger.verbose("")

        reloadCollectionViewImmediately()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // If the scroll action is not animated, perform it _before_
            // updateViewToReflectLoad().
            if !scrollAction.isAnimated {
                self.perform(scrollAction: scrollAction)
            }
            self.updateViewToReflectLoad(loadedRenderState: renderState)
            self.loadDidLand(renderState: renderState)
            if scrollAction.isAnimated {
                self.perform(scrollAction: scrollAction)
            }
        }
    }

    private func resetViewStateAfterError() {
        Logger.verbose("")

        reloadCollectionViewForReset()

        // Try to update the lastKnownDistanceFromBottom; the content size may have changed.
        updateLastKnownDistanceFromBottom()
    }

    private func updateWithDiff(update: CVUpdate,
                                items: [CVUpdate.Item],
                                shouldAnimateUpdate: Bool,
                                scrollAction scrollActionParam: CVScrollAction,
                                threadInteractionCount: UInt,
                                updateToken: CVUpdateToken) {
        AssertIsOnMainThread()
        owsAssertDebug(!items.isEmpty)

        Logger.verbose("")

        let renderState = update.renderState
        let isScrolledToBottom = updateToken.isScrolledToBottom
        let viewState = self.viewState

        var scrollAction = scrollActionParam

        // Update scroll action to auto-scroll if necessary.
        if scrollAction.action == .none, !self.isUserScrolling {
            for item in items {
                let renderItem = item.value
                switch item.updateType {
                case .insert:

                    var wasJustInserted = false
                    if let lastMessageForInboxSortId = updateToken.lastMessageForInboxSortId {
                        if lastMessageForInboxSortId < renderItem.interaction.sortId {
                            wasJustInserted = true
                        }
                    } else {
                        // The first interaction in the thread.
                        wasJustInserted = true
                    }

                    // We want to auto-scroll to the bottom of the conversation
                    // if the user is inserting new interactions.
                    let isAutoScrollInteraction: Bool
                    switch renderItem.interactionType {
                    case .typingIndicator:
                        isAutoScrollInteraction = true
                    case .incomingMessage,
                         .outgoingMessage,
                         .call,
                         .error,
                         .info:
                        isAutoScrollInteraction = wasJustInserted
                    default:
                        isAutoScrollInteraction = false
                    }

                    if let outgoingMessage = renderItem.interaction as? TSOutgoingMessage,
                       !outgoingMessage.isFromLinkedDevice,
                       wasJustInserted {
                        // Whenever we send an outgoing message from the local device,
                        // auto-scroll to the bottom of the conversation, regardless
                        // of scroll state.
                        scrollAction = CVScrollAction(action: .bottomForNewMessage, isAnimated: true)
                        break
                    } else if isAutoScrollInteraction,
                              isScrolledToBottom {
                        // If we're already at the bottom of the conversation and
                        // a freshly inserted message or typing indicator appears,
                        // auto-scroll to show it.
                        scrollAction = CVScrollAction(action: .bottomForNewMessage, isAnimated: true)
                        break
                    }
                default:
                    break
                }
            }
        }

        if .loadOlder == renderState.loadType {
            scrollAction = .none
        }

        viewState.scrollActionForUpdate = scrollAction

        // We have two scroll continuity mechanisms:
        //
        // * The first is in the targetContentOffset(forProposedContentOffset:) method in CVC+Scroll.swift.
        //   This handles scroll continuity in most cases.
        // * The second is in ConversationViewLayout.willPerformBatchUpdates().
        //   We manipulate the content offset using
        //   UICollectionViewLayoutInvalidationContext.contentOffsetAdjustment.
        //
        // We prefer the second mechanism and only use the first mechanism to
        // handle special cases (ie. when shouldUseDelegateScrollContinuity is true).
        let scrollContinuity: ScrollContinuity = {
            guard let loadType = renderState.loadType else {
                owsFailDebug("Missing loadType.")
                return .delegateScrollContinuity
            }

            // TODO: We could extend the layout's invalidation-based approach
            // to scroll continuity to support more of these cases.
            if shouldUseDelegateScrollContinuity {
                return .delegateScrollContinuity
            }

            let scrollContinuityToken = updateToken.scrollContinuityToken

            switch loadType {
            case .loadInitialMapping:
                return .none
            case .loadSameLocation:
                return .contentRelativeToViewport(token: scrollContinuityToken,
                                                  isRelativeToTop: false)
            case .loadOlder:
                return .contentRelativeToViewport(token: scrollContinuityToken,
                                                  isRelativeToTop: true)
            case .loadNewer, .loadNewest:
                return .contentRelativeToViewport(token: scrollContinuityToken,
                                                  isRelativeToTop: false)
            case .loadPageAroundInteraction:
                return .contentRelativeToViewport(token: scrollContinuityToken,
                                                  isRelativeToTop: false)
            }
        }()

        let batchUpdatesBlock = {
            AssertIsOnMainThread()

            let section = Self.messageSection
            for item in items {
                if !DebugFlags.reduceLogChatter {
                    Logger.verbose("\(item.logSafeDescription)")
                }

                switch item.updateType {
                case .delete(let oldIndex):
                    let indexPath = IndexPath(row: oldIndex, section: section)
                    self.collectionView.deleteItems(at: [indexPath])
                case .insert(let newIndex):
                    let indexPath = IndexPath(row: newIndex, section: section)
                    self.collectionView.insertItems(at: [indexPath])
                case .move(let oldIndex, let newIndex):
                    let oldIndexPath = IndexPath(row: oldIndex, section: section)
                    let newIndexPath = IndexPath(row: newIndex, section: section)
                    self.collectionView.moveItem(at: oldIndexPath, to: newIndexPath)
                case .update(let oldIndex, _):
                    let indexPath = IndexPath(row: oldIndex, section: section)
                    self.collectionView.reloadItems(at: [indexPath])
                }
            }
        }

        let completion = { [weak self] (finished: Bool) in
            AssertIsOnMainThread()

            guard let self = self else {
                return
            }

            // If the scroll action is not animated, perform it _before_
            // updateViewToReflectLoad().
            if !scrollAction.isAnimated {
                self.perform(scrollAction: scrollAction)
            }

            self.updateViewToReflectLoad(loadedRenderState: renderState)

            if shouldAnimateUpdate {
                self.loadDidLand(renderState: update.renderState)
            }

            if scrollAction.isAnimated {
                self.perform(scrollAction: scrollAction)
            }

            viewState.scrollActionForUpdate = nil

            if !finished {
                Logger.verbose("performBatchUpdates did not finish")
                if DebugFlags.internalLogging {
                    Logger.warn("Layout: \(self.layout.debugDescription)")
                    Logger.warn("prevRenderState: \(update.prevRenderState.debugDescription)")
                    Logger.warn("renderState: \(update.renderState.debugDescription)")
                }

                // If animations were interrupted, reset to get back to a known good state.
                DispatchQueue.main.async { [weak self] in
                    self?.resetViewStateAfterError()
                }
            }
        }

        // We use an obj-c free function so that we can handle NSException.
        self.collectionView.cvc_performBatchUpdates(batchUpdatesBlock,
                                                    completion: completion,
                                                    animated: shouldAnimateUpdate,
                                                    scrollContinuity: scrollContinuity,
                                                    lastKnownDistanceFromBottom: updateToken.lastKnownDistanceFromBottom,
                                                    cvc: self)

        if !shouldAnimateUpdate {
            self.loadDidLand(renderState: update.renderState)
        }
    }

    private var scrolledToEdgeTolerancePoints: CGFloat {
        let deviceFrame = CurrentAppContext().frame
        // Within 1 screenful of the edge of the load window.
        return max(deviceFrame.width, deviceFrame.height)
    }

    var isScrollNearTopOfLoadWindow: Bool {
        return isScrolledToTop(tolerancePoints: scrolledToEdgeTolerancePoints)
    }

    var isScrollNearBottomOfLoadWindow: Bool {
        return isScrolledToBottom(tolerancePoints: scrolledToEdgeTolerancePoints)
    }

    public func registerReuseIdentifiers() {
        CVCell.registerReuseIdentifiers(collectionView: self.collectionView)
        collectionView.register(LoadMoreMessagesView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: LoadMoreMessagesView.reuseIdentifier)
        collectionView.register(LoadMoreMessagesView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                withReuseIdentifier: LoadMoreMessagesView.reuseIdentifier)
    }

    public static func buildInitialConversationStyle(threadViewModel: ThreadViewModel) -> ConversationStyle {
        ConversationStyle(type: .initial,
                          thread: threadViewModel.threadRecord,
                          viewWidth: 0,
                          hasWallpaper: threadViewModel.hasWallpaper,
                          isWallpaperPhoto: threadViewModel.isWallpaperPhoto,
                          chatColor: .placeholderValue)
    }

    @objc
    public static func buildDefaultConversationStyle(thread: TSThread) -> ConversationStyle {
        ConversationStyle(type: .default,
                          thread: thread,
                          viewWidth: 0,
                          hasWallpaper: false,
                          isWallpaperPhoto: false,
                          chatColor: .placeholderValue)
    }

    private func buildConversationStyle() -> ConversationStyle {
        AssertIsOnMainThread()

        var hasWallpaper: Bool = false
        var isWallpaperPhoto: Bool = false
        var chatColor: ChatColor = .placeholderValue
        databaseStorage.read { transaction in
            if let wallpaper = Wallpaper.wallpaperForRendering(for: self.thread, transaction: transaction) {
                hasWallpaper = true
                if case .photo = wallpaper {
                    isWallpaperPhoto = true
                } else {
                    isWallpaperPhoto = false
                }
            } else {
                hasWallpaper = false
                isWallpaperPhoto = false
            }
            chatColor = ChatColors.chatColorForRendering(thread: self.thread, transaction: transaction)
        }

        func buildDefaultConversationStyle(type: ConversationStyleType) -> ConversationStyle {
            // Treat all styles as "initial" (not to be trusted) until
            // we have a view config.
            let viewWidth = floor(collectionView.width)
            return ConversationStyle(type: type,
                                     thread: thread,
                                     viewWidth: viewWidth,
                                     hasWallpaper: hasWallpaper,
                                     isWallpaperPhoto: isWallpaperPhoto,
                                     chatColor: chatColor)
        }

        guard self.conversationStyle.type != .`default` else {
            // Once we built a normal style, never go back to
            // building an initial or placeholder style.
            owsAssertDebug(navigationController != nil || viewState.isInPreviewPlatter)
            return buildDefaultConversationStyle(type: .`default`)
        }

        guard let navigationController = navigationController else {
            if viewState.isInPreviewPlatter {
                // In a preview platter, we'll never have a navigation controller
                return buildDefaultConversationStyle(type: .`default`)
            } else {
                // Treat all styles as "initial" (not to be trusted) until
                // we have a navigationController.
                return buildDefaultConversationStyle(type: .initial)
            }
        }

        let collectionViewWidth = self.collectionView.width
        let rootViewWidth = self.view.width
        let viewSafeAreaInsets = self.view.safeAreaInsets
        let navigationViewWidth = navigationController.view.width
        let navigationSafeAreaInsets = navigationController.view.safeAreaInsets

        let isMissingSafeAreaInsets = (viewSafeAreaInsets == .zero &&
                                        navigationSafeAreaInsets != .zero)
        let hasInvalidWidth = (collectionViewWidth > navigationViewWidth ||
                                rootViewWidth > navigationViewWidth)
        let hasValidStyle = !isMissingSafeAreaInsets && !hasInvalidWidth
        if hasValidStyle {
            // No need to rewrite style; style is already valid.
            return buildDefaultConversationStyle(type: .`default`)
        } else {
            let viewAge = abs(self.viewState.viewCreationDate.timeIntervalSinceNow)
            let maxHideTime = kSecondInterval * 2
            guard viewAge < maxHideTime else {
                // This should never happen, but we want to put an upper bound on
                // how long we're willing to infer view state from the
                // navigationController. It might not always be safe to assume that
                // navigationController view and CVC view state converge.
                Logger.warn("View state taking a long time to be configured.")
                return buildDefaultConversationStyle(type: .placeholder)
            }

            // We can derive a style that reflects what the correct style will be,
            // using values from the navigationController.
            let viewWidth = floor(navigationViewWidth)
            return ConversationStyle(type: .placeholder,
                                     thread: thread,
                                     viewWidth: viewWidth,
                                     hasWallpaper: hasWallpaper,
                                     isWallpaperPhoto: isWallpaperPhoto,
                                     chatColor: chatColor)
        }
    }

    @discardableResult
    public func updateConversationStyle() -> Bool {
        AssertIsOnMainThread()

        let oldConversationStyle = self.conversationStyle
        let newConversationStyle = buildConversationStyle()

        let didChange = !newConversationStyle.isEqualForCellRendering(oldConversationStyle)
        if !didChange {
            return false
        }

        self.conversationStyle = newConversationStyle

        if let inputToolbar = inputToolbar {
            inputToolbar.update(conversationStyle: newConversationStyle)
        }

        // We need to kick off a reload cycle if conversationStyle changes.
        loadCoordinator.updateConversationStyle(newConversationStyle)

        return true
    }
}

// MARK: -

extension ConversationViewController: CVViewStateDelegate {
    public func viewStateUIModeDidChange(oldValue: ConversationUIMode) {

        if oldValue != uiMode && (oldValue == .selection || uiMode == .selection) {

            // Proactively update bottom bar before load lands
            ensureBottomViewType()

             // Block loads while things animate.
            viewState.selectionAnimationState = .willAnimate
            loadCoordinator.enqueueReload()

             DispatchQueue.main.asyncAfter(deadline: .now() + CVComponentMessage.selectionAnimationDuration) {
                self.viewState.selectionAnimationState = .idle
                 // Enqueue a new load after animation so the "wasShowingSelectionUI" state is updated.
                 self.loadCoordinator.enqueueReload()
             }
        } else {
            loadCoordinator.enqueueReload()
        }
    }
}

// MARK: - Load More

extension ConversationViewController {
    public func autoLoadMoreIfNecessary() -> Bool {
        AssertIsOnMainThread()

        guard hasAppearedAndHasAppliedFirstLoad else {
            return false
        }
        let isMainAppAndActive = CurrentAppContext().isMainAppAndActive
        guard isViewVisible, isMainAppAndActive else {
            return false
        }
        guard showLoadOlderHeader || showLoadNewerHeader else {
            return false
        }
        guard let navigationController = navigationController else {
            return false
        }
        navigationController.view.layoutIfNeeded()
        let navControllerSize = navigationController.view.frame.size
        let loadThreshold = navControllerSize.largerAxis * 3
        let distanceFromTop = collectionView.contentOffset.y
        let isCloseToTop = distanceFromTop < loadThreshold
        if showLoadOlderHeader, isCloseToTop {
            if loadCoordinator.didLoadOlderRecently {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    _ = self?.autoLoadMoreIfNecessary()
                }
                return false
            }

            loadCoordinator.loadOlderItems()
            return true
        }

        let distanceFromBottom = collectionView.contentSize.height - collectionView.bounds.size.height
            - collectionView.contentOffset.y
        let isCloseToBottom = distanceFromBottom < loadThreshold
        if showLoadNewerHeader, isCloseToBottom {
            if loadCoordinator.didLoadNewerRecently {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    _ = self?.autoLoadMoreIfNecessary()
                }
                return false
            }

            loadCoordinator.loadNewerItems()
            return true
        }

        return false
    }

    public var showLoadOlderHeader: Bool { loadCoordinator.showLoadOlderHeader }

    public var showLoadNewerHeader: Bool { loadCoordinator.showLoadNewerHeader }
}
