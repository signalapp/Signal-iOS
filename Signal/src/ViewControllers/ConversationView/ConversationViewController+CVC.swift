//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension ConversationViewController {

    @objc
    public static var messageSection: Int { CVLoadCoordinator.messageSection }

    @objc
    public var hasRenderState: Bool { !renderState.isEmptyInitialState }

    @objc
    public var hasAppearedAndHasAppliedFirstLoad: Bool {
        (hasRenderState &&
            hasViewDidAppearEverBegun &&
            !loadCoordinator.shouldHideCollectionViewContent)
    }

    @objc
    public var lastReloadDate: Date { renderState.loadDate }

    @objc
    public func indexPath(forInteractionUniqueId interactionUniqueId: String) -> IndexPath? {
        loadCoordinator.indexPath(forInteractionUniqueId: interactionUniqueId)
    }

    @objc
    public func indexPath(forItemViewModel itemViewModel: CVItemViewModelImpl) -> IndexPath? {
        indexPath(forInteractionUniqueId: itemViewModel.interaction.uniqueId)
    }

    @objc
    public func interaction(forIndexPath indexPath: IndexPath) -> TSInteraction? {
        guard let renderItem = self.renderItem(forIndex: indexPath.row) else {
            return nil
        }
        return renderItem.interaction
    }

    @objc
    var indexPathOfUnreadMessagesIndicator: IndexPath? {
        loadCoordinator.indexPathOfUnreadIndicator
    }

    @objc
    public var canLoadOlderItems: Bool {
        loadCoordinator.canLoadOlderItems
    }

    @objc
    public var canLoadNewerItems: Bool {
        loadCoordinator.canLoadNewerItems
    }

    @objc
    public var currentRenderStateDebugDescription: String {
        renderState.debugDescription
    }
}

// MARK: -

extension ConversationViewController: CVLoadCoordinatorDelegate {

    @objc
    public func buildLoadCoordinator(conversationStyle: ConversationStyle,
                                     focusMessageIdOnOpen: String?) -> CVLoadCoordinator {
        CVLoadCoordinator(delegate: self,
                          componentDelegate: self,
                          conversationStyle: conversationStyle,
                          focusMessageIdOnOpen: focusMessageIdOnOpen)
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

        // This will get cleared by updateViewToReflectLoad().
        owsAssertDebug(viewState.scrollContinuityMap == nil)
        viewState.scrollContinuityMap = buildScrollContinuityMap(forRenderState: renderState)

        return CVUpdateToken(isScrolledToBottom: self.isScrolledToBottom,
                             lastMessageForInboxSortId: threadViewModel.lastMessageForInbox?.sortId)
    }

    func updateWithNewRenderState(update: CVUpdate,
                                  scrollAction: CVScrollAction,
                                  updateToken: CVUpdateToken) {
        AssertIsOnMainThread()

        owsAssertDebug(self.viewState.scrollContinuityMap != nil)

        guard hasViewWillAppearEverBegun else {
            // It's safe to ignore updates before viewWillAppear
            // if called for the first time.

            Logger.info("View is not yet loaded.")
            loadDidLand()
            return
        }

        let benchSteps = BenchSteps(title: "updateWithNewRenderState")

        let renderState = update.renderState
        let isFirstLoad = renderState.isFirstLoad

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
        dismissMessageActionsIfNecessary()

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

            loadDidLand()

            benchSteps.step("5a")
        } else {
            if !viewState.hasAppliedFirstLoad {
                // Ignore scrollAction; we need to scroll to .initialPosition.
                updateWithFirstLoad()
            } else {
                switch update.type {
                case .minor:
                    updateForMinorUpdate(scrollAction: scrollAction)
                case .reloadAll:
                    updateReloadingAll(renderState: renderState,
                                       scrollAction: scrollAction)
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

        self.scrollContinuity = .bottom
        self.updateLastKnownDistanceFromBottom()
        self.updateInputToolbarLayout()
        self.ensureSelectionViewState()
        self.showMessageRequestDialogIfRequired()
        self.configureScrollDownButtons()

        benchSteps.step("loadCompletion.1")

        let hasViewDidAppearEverCompleted = self.hasViewDidAppearEverCompleted

        DispatchQueue.main.async {
            let benchSteps = BenchSteps()
            Self.databaseStorage.uiRead { transaction in
                self.reloadReactionsDetailSheet(with: transaction)
                self.updateUnreadMessageFlag(with: transaction)
            }
            if hasViewDidAppearEverCompleted {
                _ = self.autoLoadMoreIfNecessary()
            }
            benchSteps.step("loadCompletion.2")
        }
    }

    private func loadDidLand() {
        // Discard scrollContinuityMap after the load is complete.
        //
        // Do not discard scrollContinuityMap if it corresponds to a
        // subsequent load. Animated and non-animated loads might
        // land in any order and thus complete out of order.
        owsAssertDebug(viewState.scrollContinuityMap != nil)
        self.viewState.scrollContinuityMap = nil

        self.loadCoordinator.loadDidLand()
    }

    // The view's first appearance and the first load can race.
    // We need to handle them completing in either order.
    //
    // This means performing much of the work we do when we land
    // the first load.
    @objc
    public func viewWillAppearForLoad() {
        updateShouldHideCollectionViewContent(reloadIfClearingFlag: true)
    }

    @objc
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
            UIView.performWithoutAnimation {
                self.collectionView.reloadData()
                self.layout.invalidateLayout()
            }

            scrollToInitialPosition(animated: false)

            updateViewToReflectLoad(loadedRenderState: self.renderState)

            loadCoordinator.enqueueReload()

            setHasAppliedFirstLoadIfNecessary()
        }
    }

    private func updateForMinorUpdate(scrollAction: CVScrollAction) {
        Logger.verbose("")

        // If the scroll action is not animated, perform it _before_
        // updateViewToReflectLoad().
        if !scrollAction.isAnimated {
            self.perform(scrollAction: scrollAction)
        }

        updateViewToReflectLoad(loadedRenderState: self.renderState)

        loadDidLand()

        if scrollAction.isAnimated {
            self.perform(scrollAction: scrollAction)
        }
    }

    private func updateWithFirstLoad() {

        let benchSteps = BenchSteps(title: "updateWithFirstLoad")

        #if TESTABLE_BUILD
        initialLoadBenchSteps.step("updateWithFirstLoad.1")
        #endif

        Logger.verbose("")

        benchSteps.step("1")

        UIView.performWithoutAnimation {
            self.collectionView.reloadData()
            self.layout.invalidateLayout()
        }

        benchSteps.step("2")

        scrollToInitialPosition(animated: false)
        clearInitialScrollState()

        benchSteps.step("3")

        updateViewToReflectLoad(loadedRenderState: self.renderState)

        benchSteps.step("4")

        loadDidLand()

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
        clearInitialScrollState()
    }

    private func updateReloadingAll(renderState: CVRenderState,
                                    scrollAction: CVScrollAction) {

        Logger.verbose("")

        UIView.performWithoutAnimation {
            self.collectionView.reloadData()
            self.layout.invalidateLayout()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // If the scroll action is not animated, perform it _before_
            // updateViewToReflectLoad().
            if !scrollAction.isAnimated {
                self.perform(scrollAction: scrollAction)
            }
            self.updateViewToReflectLoad(loadedRenderState: renderState)
            self.loadDidLand()
            if scrollAction.isAnimated {
                self.perform(scrollAction: scrollAction)
            }
        }
    }

    private func resetViewStateAfterError() {
        Logger.verbose("")

        scrollContinuity = .bottom

        reloadCollectionView()

        // Try to update the lastKnownDistanceFromBottom; the content size may have changed.
        updateLastKnownDistanceFromBottom()

        ensureSelectionViewState()
    }

    private func updateWithDiff(update: CVUpdate,
                                items: [CVUpdate.Item],
                                shouldAnimateUpdate: Bool,
                                scrollAction scrollActionParam: CVScrollAction,
                                threadInteractionCount: UInt,
                                updateToken: CVUpdateToken) {
        owsAssertDebug(!items.isEmpty)

        Logger.verbose("")

        let renderState = update.renderState
        let isScrolledToBottom = updateToken.isScrolledToBottom
        let viewState = self.viewState

        var scrollAction = scrollActionParam

        scrollContinuity = isScrolledToBottom ? .bottom : .top
        if let loadType = renderState.loadType {
            if loadType == .loadOlder {
                scrollContinuity = .bottom
            }
        } else {
            owsFailDebug("Missing loadType.")
        }

        // Update scroll action to auto-scroll if necessary.
        if scrollAction.action == .none, !self.isUserScrolling {
            for item in items {
                switch item {
                case .insert(let renderItem, _):

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
                        scrollAction = CVScrollAction(action: .bottomOfLoadWindow, isAnimated: false)
                        break
                    } else if isAutoScrollInteraction,
                              isScrolledToBottom {
                        // If we're already at the bottom of the conversation and
                        // a freshly inserted message or typing indicator appears,
                        // auto-scroll to show it.
                        scrollAction = CVScrollAction(action: .bottomOfLoadWindow, isAnimated: false)
                        break
                    }
                default:
                    break
                }
            }
        }

        viewState.scrollActionForUpdate = scrollAction

        let batchUpdatesBlock = {
            AssertIsOnMainThread()

            let section = Self.messageSection
            var hasInserted = false
            var hasUpdated = false
            for item in items {
                switch item {
                case .insert(_, let newIndex):
                    // Always perform inserts before updates.
                    owsAssertDebug(!hasUpdated)
                    Logger.verbose("insert newIndex: \(newIndex)")
                    let indexPath = IndexPath(row: newIndex, section: section)
                    self.collectionView.insertItems(at: [indexPath])
                    hasInserted = true
                case .update(_, let oldIndex, _):
                    Logger.verbose("update oldIndex: \(oldIndex)")
                    let indexPath = IndexPath(row: oldIndex, section: section)
                    self.collectionView.reloadItems(at: [indexPath])
                    hasUpdated = true
                case .delete(_, let oldIndex):
                    Logger.verbose("delete oldIndex: \(oldIndex)")
                    // Always perform deletes before inserts and updates.
                    owsAssertDebug(!hasInserted && !hasUpdated)

                    let indexPath = IndexPath(row: oldIndex, section: section)
                    self.collectionView.deleteItems(at: [indexPath])
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

            self.loadDidLand()

            if scrollAction.isAnimated {
                self.perform(scrollAction: scrollAction)
            }

            viewState.scrollActionForUpdate = nil

            if !finished {
                Logger.warn("performBatchUpdates did not finish")
                Logger.warn("Layout: \(self.layout.debugDescription)")
                Logger.warn("prevRenderState: \(update.prevRenderState.debugDescription)")
                Logger.warn("renderState: \(update.renderState.debugDescription)")

                // If animations were interrupted, reset to get back to a known good state.
                DispatchQueue.main.async { [weak self] in
                    self?.resetViewStateAfterError()
                }
            }
        }

        let logFailureBlock = {
            for item in items {
                Logger.warn("item: \(item.debugDescription)")
            }
        }

        self.performBatchUpdates(batchUpdatesBlock,
                                 completion: completion,
                                 logFailureBlock: logFailureBlock,
                                 shouldAnimateUpdates: shouldAnimateUpdate)
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

    @objc
    public func registerReuseIdentifiers() {
        CVCell.registerReuseIdentifiers(collectionView: self.collectionView)
        collectionView.register(LoadMoreMessagesView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: LoadMoreMessagesView.reuseIdentifier)
        collectionView.register(LoadMoreMessagesView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                withReuseIdentifier: LoadMoreMessagesView.reuseIdentifier)
    }

    private func buildConversationStyle() -> ConversationStyle {
        AssertIsOnMainThread()

        func buildDefaultConversationStyle(type: ConversationStyleType) -> ConversationStyle {
            // Treat all styles as "initial" (not to be trusted) until
            // we have a view config.
            let viewWidth = floor(collectionView.width)
            return ConversationStyle(type: type,
                                     thread: thread,
                                     viewWidth: viewWidth)
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
                                     viewWidth: viewWidth)
        }
    }

    @objc
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

        // TODO: In "new CVC" we shouldn't update the layout's style until the render state changes.
        layout.update(conversationStyle: newConversationStyle)

        return true
    }
}

// MARK: -

extension ConversationViewController: CVViewStateDelegate {
    public func uiModeDidChange() {
        loadCoordinator.enqueueReload()
    }
}
