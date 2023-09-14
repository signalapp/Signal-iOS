//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

protocol CVLoadCoordinatorDelegate: UIScrollViewDelegate {
    var viewState: CVViewState { get }

    func willUpdateWithNewRenderState(_ renderState: CVRenderState) -> CVUpdateToken

    func updateWithNewRenderState(update: CVUpdate,
                                  scrollAction: CVScrollAction,
                                  updateToken: CVUpdateToken)

    func updateScrollingContent()

    func chatColorDidChange()

    func updateAccessibilityCustomActionsForCell(_ cell: CVItemCell)

    var isScrolledToBottom: Bool { get }

    var isScrollNearTopOfLoadWindow: Bool { get }

    var isScrollNearBottomOfLoadWindow: Bool { get }

    var areCellsAnimating: Bool { get }

    var conversationViewController: ConversationViewController? { get }
}

// MARK: -

// This token lets CVC capture state from "before" a load
// lands that can be used when landing that load.
struct CVUpdateToken {
    let isScrolledToBottom: Bool
    let lastMessageForInboxSortId: UInt64?
    let scrollContinuityToken: CVScrollContinuityToken
    let lastKnownDistanceFromBottom: CGFloat?
}

public class CVLoadCoordinator: NSObject {

    private weak var delegate: CVLoadCoordinatorDelegate?
    private weak var componentDelegate: CVComponentDelegate?

    private let viewState: CVViewState
    private var mediaCache: CVMediaCache { viewState.mediaCache }

    private let threadUniqueId: String

    private var conversationStyle: ConversationStyle
    private let spoilerState: SpoilerRenderState

    var renderState: CVRenderState

    // CVC is perf-sensitive during its initial load and
    // presentation. We can use this flag to skip any expensive
    // work before the first load is complete.
    public var hasRenderState: Bool {
        !renderState.isEmptyInitialState
    }

    public var shouldHideCollectionViewContent = true {
        didSet {
            owsAssertDebug(!shouldHideCollectionViewContent)
        }
    }

    private var oldestUnreadMessageSortId: UInt64?

    private let messageLoader: MessageLoader

    // TODO: Remove. This model will get stale.
    private let thread: TSThread

    required init(
        viewState: CVViewState,
        threadViewModel: ThreadViewModel,
        conversationViewModel: ConversationViewModel,
        oldestUnreadMessageSortId: UInt64?
    ) {
        self.viewState = viewState
        self.threadUniqueId = threadViewModel.threadRecord.uniqueId
        self.thread = threadViewModel.threadRecord
        self.conversationStyle = viewState.conversationStyle
        self.spoilerState = viewState.spoilerState
        self.oldestUnreadMessageSortId = oldestUnreadMessageSortId
        let viewStateSnapshot = CVViewStateSnapshot.snapshot(
            viewState: viewState,
            typingIndicatorsSender: nil,
            oldestUnreadMessageSortId: oldestUnreadMessageSortId,
            previousViewStateSnapshot: nil
        )
        self.renderState = CVRenderState.defaultRenderState(
            threadViewModel: threadViewModel,
            conversationViewModel: conversationViewModel,
            viewStateSnapshot: viewStateSnapshot
        )
        self.messageLoader = MessageLoader(
            batchFetcher: ConversationViewBatchFetcher(interactionFinder: InteractionFinder(threadUniqueId: thread.uniqueId)),
            interactionFetchers: [Self.modelReadCaches.interactionReadCache, SDSInteractionFetcherImpl()]
        )
        super.init()
    }

    func configure(delegate: CVLoadCoordinatorDelegate,
                   componentDelegate: CVComponentDelegate,
                   focusMessageIdOnOpen: String?) {
        self.delegate = delegate
        self.componentDelegate = componentDelegate

        Self.databaseStorage.appendDatabaseChangeDelegate(self)

        // Kick off async load.
        loadInitialMapping(focusMessageIdOnOpen: focusMessageIdOnOpen)
    }

    // MARK: -

    public func viewDidLoad() {
        addNotificationListeners()
    }

    // MARK: - Notifications

    private func addNotificationListeners() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidEnterBackground),
                                               name: .OWSApplicationDidEnterBackground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(typingIndicatorStateDidChange),
                                               name: TypingIndicatorsImpl.typingIndicatorStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(profileWhitelistDidChange),
                                               name: .profileWhitelistDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(blockListDidChange),
                                               name: BlockingManager.blockListDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(localProfileDidChange),
                                               name: .localProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(otherUsersProfileDidChange(notification:)),
                                               name: .otherUsersProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(skipContactAvatarBlurDidChange(notification:)),
                                               name: OWSContactsManager.skipContactAvatarBlurDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(skipGroupAvatarBlurDidChange(notification:)),
                                               name: OWSContactsManager.skipGroupAvatarBlurDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(chatColorsDidChange),
                                               name: ChatColors.chatColorsDidChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didLearnRecipientAssociation(notification:)),
                                               name: .didLearnRecipientAssociation,
                                               object: nil)
        callService.addObserver(observer: self, syncStateImmediately: false)
    }

    @objc
    private func applicationDidEnterBackground() {
        resetClearedUnreadMessagesIndicator()
    }

    @objc
    private func typingIndicatorStateDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let notificationThreadId = notification.object as? String else {
            return
        }
        guard notificationThreadId == thread.uniqueId else {
            return
        }

        enqueueReload()
    }

    @objc
    private func profileWhitelistDidChange() {
        AssertIsOnMainThread()

        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }

    @objc
    private func blockListDidChange() {
        AssertIsOnMainThread()

        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }

    @objc
    private func localProfileDidChange() {
        AssertIsOnMainThread()

        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }

    @objc
    private func otherUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()

        if let contactThread = thread as? TSContactThread {
            guard let address = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress,
                  address.isValid else {
                owsFailDebug("Missing or invalid address.")
                return
            }
            if contactThread.contactAddress == address {
                enqueueReloadWithoutCaches()
            }
        } else {
            // TODO: In groups, we could reload if any group member's profile changed.
            //       Ideally we would only reload cells that use that member's profile state.
        }
    }

    @objc
    private func didLearnRecipientAssociation(notification: Notification) {
        AssertIsOnMainThread()
        enqueueReloadWithoutCaches()
    }

    @objc
    private func skipContactAvatarBlurDidChange(notification: Notification) {
        guard let address = notification.userInfo?[OWSContactsManager.skipContactAvatarBlurAddressKey] as? SignalServiceAddress else {
            owsFailDebug("Missing address.")
            return
        }
        if let contactThread = thread as? TSContactThread {
            if contactThread.contactAddress == address {
                enqueueReloadWithoutCaches()
            }
        } else if let groupThread = thread as? TSGroupThread {
            if groupThread.groupMembership.allMembersOfAnyKind.contains(address) {
                enqueueReloadWithoutCaches()
            }
        } else {
            owsFailDebug("Invalid thread.")
        }
    }

    @objc
    private func skipGroupAvatarBlurDidChange(notification: Notification) {
        guard let groupUniqueId = notification.userInfo?[OWSContactsManager.skipGroupAvatarBlurGroupUniqueIdKey] as? String else {
            owsFailDebug("Missing groupId.")
            return
        }
        guard let groupThread = thread as? TSGroupThread,
              groupThread.uniqueId == groupUniqueId else {
            return
        }
        enqueueReloadWithoutCaches()
    }

    @objc
    private func chatColorsDidChange(_ notification: NSNotification) {
        guard notification.object == nil || (notification.object as? String) == thread.uniqueId else { return }
        delegate?.chatColorDidChange()
    }

    func appendUnsavedOutgoingTextMessage(_ message: TSOutgoingMessage) {
        AssertIsOnMainThread()
        // TODO:
        //        // Because the message isn't yet saved, we don't have sufficient information to build
        //        // in-memory placeholder for message types more complex than plain text.
        //        OWSAssertDebug(outgoingMessage.attachmentIds.count == 0);
        //        OWSAssertDebug(outgoingMessage.contactShare == nil);
        //
        //        NSMutableArray<TSOutgoingMessage *> *unsavedOutgoingMessages = [self.unsavedOutgoingMessages mutableCopy];
        //        [unsavedOutgoingMessages addObject:outgoingMessage];
        //        self.unsavedOutgoingMessages = unsavedOutgoingMessages;
        //
        //        [self updateForTransientItems];
    }

    // MARK: -

    public var canLoadOlderItems: Bool {
        renderState.canLoadOlderItems
    }

    public var canLoadNewerItems: Bool {
        renderState.canLoadNewerItems
    }

    // MARK: - Load Requests

    // This property should only be accessed on the main thread.
    private var loadRequestBuilder = CVLoadRequest.Builder()

    private var isBuildingLoad = false

    private let autoLoadMoreThreshold: TimeInterval = 2 * kSecondInterval

    private var lastLoadOlderDate: Date?
    public var didLoadOlderRecently: Bool {
        AssertIsOnMainThread()

        guard let lastLoadOlderDate = lastLoadOlderDate else {
            return false
        }
        return abs(lastLoadOlderDate.timeIntervalSinceNow) < autoLoadMoreThreshold
    }

    private var lastLoadNewerDate: Date?
    public var didLoadNewerRecently: Bool {
        AssertIsOnMainThread()

        guard let lastLoadNewerDate = lastLoadNewerDate else {
            return false
        }
        return abs(lastLoadNewerDate.timeIntervalSinceNow) < autoLoadMoreThreshold
    }
    private func loadInitialMapping(focusMessageIdOnOpen: String?) {
        owsAssertDebug(renderState.isEmptyInitialState)
        loadRequestBuilder.loadInitialMapping(focusMessageIdOnOpen: focusMessageIdOnOpen)
        loadIfNecessary()
    }

    public func loadOlderItems() {
        guard !renderState.isEmptyInitialState else {
            return
        }
        loadRequestBuilder.loadOlderItems()
        loadIfNecessary()
    }

    public func loadNewerItems() {
        guard !renderState.isEmptyInitialState else {
            return
        }
        loadRequestBuilder.loadNewerItems()
        loadIfNecessary()
    }

    public func loadAndScrollToNewestItems(isAnimated: Bool) {
        loadRequestBuilder.loadAndScrollToNewestItems(isAnimated: isAnimated)
        loadIfNecessary()
    }

    public func enqueueReload() {
        loadRequestBuilder.reload()
        loadIfNecessary()
    }

    public func enqueueReload(scrollAction: CVScrollAction) {
        loadRequestBuilder.reload(scrollAction: scrollAction)
        loadIfNecessary()
    }

    public func enqueueReload(updatedInteractionIds: Set<String>,
                              deletedInteractionIds: Set<String>) {
        AssertIsOnMainThread()

        loadRequestBuilder.reload(updatedInteractionIds: updatedInteractionIds,
                                  deletedInteractionIds: deletedInteractionIds)
        loadIfNecessary()
    }

    public func enqueueLoadAndScrollToInteraction(interactionId: String,
                                                  onScreenPercentage: CGFloat,
                                                  alignment: ScrollAlignment,
                                                  isAnimated: Bool) {
        AssertIsOnMainThread()

        loadRequestBuilder.loadAndScrollToInteraction(interactionId: interactionId,
                                                      onScreenPercentage: onScreenPercentage,
                                                      alignment: alignment,
                                                      isAnimated: isAnimated)
        loadIfNecessary()
    }

    public func enqueueReloadWithoutCaches() {
        AssertIsOnMainThread()

        loadRequestBuilder.reloadWithoutCaches()
        loadIfNecessary()
    }

    public func enqueueReload(canReuseInteractionModels: Bool,
                              canReuseComponentStates: Bool) {
        AssertIsOnMainThread()

        loadRequestBuilder.reload(canReuseInteractionModels: canReuseInteractionModels,
                                  canReuseComponentStates: canReuseComponentStates)
        loadIfNecessary()
    }

    // MARK: - Conversation Style

    public func updateConversationStyle(_ conversationStyle: ConversationStyle) {
        AssertIsOnMainThread()

        self.conversationStyle = conversationStyle

        // We need to kick off a reload cycle if conversationStyle changes.
        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }

    // MARK: - Unread Indicator

    func clearUnreadMessagesIndicator() {
        AssertIsOnMainThread()

        guard oldestUnreadMessageSortId != nil else {
            return
        }
        oldestUnreadMessageSortId = nil
        enqueueReload()
    }

    // MARK: -

    func resetClearedUnreadMessagesIndicator() {
        AssertIsOnMainThread()

        // TODO: Implement this method correctly by allowing the unread indicator
        // to be shown past initial load so we don't mark all messages as read on
        // foreground if we have a chat open.
    }

    // MARK: -

    private func loadIfNecessary() {
        AssertIsOnMainThread()

        loadIfNecessaryEvent.requestNotify()
    }

    private lazy var loadIfNecessaryEvent: DebouncedEvent = {
        DebouncedEvents.build(mode: .lastOnly,
                              maxFrequencySeconds: DebouncedEvents.thetaInterval,
                              onQueue: .asyncOnQueue(queue: .main)) { [weak self] in
            AssertIsOnMainThread()
            self?.loadIfNecessaryDebounced()
        }
    }()

    private func loadIfNecessaryDebounced() {
        AssertIsOnMainThread()

        let conversationStyle = self.conversationStyle
        let spoilerState = self.spoilerState
        guard conversationStyle.viewWidth > 0 else {
            Logger.info("viewWidth not yet set.")
            return
        }
        guard !isBuildingLoad, let loadRequest = loadRequestBuilder.build() else {
            return
        }
        isBuildingLoad = true
        loadRequestBuilder = CVLoadRequest.Builder()

        // We should do an "initial" load IFF this is our first load.
        owsAssertDebug(loadRequest.isInitialLoad == renderState.isEmptyInitialState)

        let prevRenderState = renderState

        if loadRequest.loadType == .loadOlder {
            lastLoadOlderDate = Date()
        } else if loadRequest.loadType == .loadNewer {
            lastLoadNewerDate = Date()
        }

        let typingIndicatorsSender = typingIndicatorsImpl.typingAddress(forThread: thread)
        let viewStateSnapshot = CVViewStateSnapshot.snapshot(
            viewState: viewState,
            typingIndicatorsSender: typingIndicatorsSender,
            oldestUnreadMessageSortId: oldestUnreadMessageSortId,
            previousViewStateSnapshot: prevRenderState.viewStateSnapshot
        )
        let loader = CVLoader(
            threadUniqueId: threadUniqueId,
            loadRequest: loadRequest,
            viewStateSnapshot: viewStateSnapshot,
            spoilerState: spoilerState,
            prevRenderState: prevRenderState,
            messageLoader: messageLoader
        )

        firstly {
            loader.loadPromise()
        }.then(on: DispatchQueue.main) { [weak self] (update: CVUpdate) -> Promise<Void> in
            guard let self = self else {
                throw OWSGenericError("Missing self.")
            }
            return self.loadLandWhenSafePromise(update: update)
        }.ensure(on: DispatchQueue.main) { [weak self] in
            guard let self else { return }
            owsAssertDebug(self.isBuildingLoad)
            self.isBuildingLoad = false
            // Initiate new load if necessary.
            self.loadIfNecessary()
        }.catch(on: DispatchQueue.main) { error in
            owsFailDebug("Load failed[\(loadRequest.requestId)]: \(error)")
        }
    }

    // MARK: - Safe Landing

    // Lands the load when it is safe, blocking on animations,
    // previous loads landing, etc.
    private func loadLandWhenSafePromise(update: CVUpdate) -> Promise<Void> {
        AssertIsOnMainThread()

        let (loadPromise, loadFuture) = Promise<Void>.pending()

        loadLandWhenSafe(update: update, loadFuture: loadFuture)

        return loadPromise
    }

    private func loadLandWhenSafe(update: CVUpdate, loadFuture: Future<Void>) {

        guard let delegate = self.delegate else {
            loadFuture.reject(OWSGenericError("Missing self or delegate."))
            return
        }

        func canLandLoad() -> Bool {
            AssertIsOnMainThread()

            // Allow multi selection animation load to land, even if keyboard is animating.
            if let lastKeyboardAnimationDate = viewState.lastKeyboardAnimationDate,
               lastKeyboardAnimationDate.isAfterNow,
               viewState.selectionAnimationState != .willAnimate {
                return false
            }
            guard viewState.selectionAnimationState != .animating  else {
                return false
            }
            if let interaction = viewState.collectionViewActiveContextMenuInteraction, interaction.contextMenuVisible {
                return false
            }
            guard !delegate.areCellsAnimating else {
                return false
            }
            return true
        }

        let loadRequest = update.loadRequest

        guard canLandLoad() else {
            // We wait in a pretty tight loop to ensure loads land in a timely way.
            //
            // DispatchQueue.asyncAfter() will take longer to perform
            // its block than DispatchQueue.async() if the CPU is under
            // heavy load. That's desirable in this case.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { [weak self] in
                self?.loadLandWhenSafe(update: update, loadFuture: loadFuture)
            }
            return
        }

        let renderState = update.renderState
        let updateToken = delegate.willUpdateWithNewRenderState(renderState)

        self.renderState = renderState

        delegate.updateWithNewRenderState(update: update,
                                          scrollAction: loadRequest.scrollAction,
                                          updateToken: updateToken)

        loadFuture.resolve()
    }
}

// MARK: -

extension CVLoadCoordinator: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        guard databaseChanges.threadUniqueIds.contains(threadUniqueId) else {
            return
        }
        enqueueReload(updatedInteractionIds: databaseChanges.interactionUniqueIds,
                      deletedInteractionIds: databaseChanges.interactionDeletedUniqueIds)
    }

    public func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        enqueueReloadWithoutCaches()
    }

    public func databaseChangesDidReset() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        enqueueReloadWithoutCaches()
    }
}

// MARK: -

extension CVLoadCoordinator: UICollectionViewDataSource {

    public static let messageSection: Int = 0

    public var renderItems: [CVRenderItem] {
        AssertIsOnMainThread()

        return shouldHideCollectionViewContent ? [] : renderState.items
    }

    public var renderStateId: UInt {
        return shouldHideCollectionViewContent ? CVRenderState.renderStateId_unknown : renderState.renderStateId
    }

    var allIndexPaths: [IndexPath] {
        AssertIsOnMainThread()

        return renderState.allIndexPaths
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        owsAssertDebug(sectionIdx == Self.messageSection)

        return renderItems.count
    }

    public func collectionView(_ collectionView: UICollectionView,
                               cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        owsAssertDebug(indexPath.section == Self.messageSection)

        guard let componentDelegate = self.componentDelegate else {
            owsFailDebug("Missing componentDelegate.")
            return UICollectionViewCell()
        }
        guard let renderItem = renderItems[safe: indexPath.row] else {
            owsFailDebug("Missing renderItem.")
            return UICollectionViewCell()
        }
        let cellReuseIdentifier = renderItem.cellReuseIdentifier
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier,
                                                            for: indexPath) as? CVCell else {
            owsFailDebug("Missing cell.")
            return UICollectionViewCell()
        }
        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            return UICollectionViewCell()
        }
        let messageSwipeActionState = delegate.viewState.messageSwipeActionState
        cell.configure(renderItem: renderItem,
                       componentDelegate: componentDelegate,
                       messageSwipeActionState: messageSwipeActionState)
        return cell

        //        // This must happen after load for display, since the tap
        //        // gesture doesn't get added to a view until this point.
        //        if ([cell isKindOfClass:[OWSMessageCell class]]) {
        //            OWSMessageCell *messageCell = (OWSMessageCell *)cell;
        //            [self.tapGestureRecognizer requireGestureRecognizerToFail:messageCell.messageViewTapGestureRecognizer];
        //            [self.tapGestureRecognizer requireGestureRecognizerToFail:messageCell.contentViewTapGestureRecognizer];
        //
        //            [messageCell.messageViewTapGestureRecognizer requireGestureRecognizerToFail:self.panGestureRecognizer];
        //            [messageCell.contentViewTapGestureRecognizer requireGestureRecognizerToFail:self.panGestureRecognizer];
        //        }
        //
        //        #ifdef DEBUG
        //        // TODO: Confirm with nancy if this will work.
        //        NSString *cellName = [NSString stringWithFormat:@"interaction.%@", NSUUID.UUID.UUIDString];
        //        if (viewItem.hasBodyText && viewItem.displayableBodyText.displayAttributedText.length > 0) {
        //            NSString *textForId =
        //                [viewItem.displayableBodyText.displayAttributedText.string stringByReplacingOccurrencesOfString:@" "
        //                    withString:@"_"];
        //            cellName = [NSString stringWithFormat:@"message.text.%@", textForId];
        //        } else if (viewItem.stickerInfo) {
        //            cellName = [NSString stringWithFormat:@"message.sticker.%@", [viewItem.stickerInfo asKey]];
        //        }
        //        cell.accessibilityIdentifier = "CVLoadCoordinator.\(cellName)"
        // #endif
        //
        // return cell;
    }

    public func collectionView(_ collectionView: UICollectionView,
                               viewForSupplementaryElementOfKind kind: String,
                               at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader ||
                kind == UICollectionView.elementKindSectionFooter else {
            owsFailDebug("unexpected supplementaryElement: \(kind)")
            return UICollectionReusableView()
        }
        guard let loadMoreView =
                collectionView.dequeueReusableSupplementaryView(ofKind: kind,
                                                                withReuseIdentifier: LoadMoreMessagesView.reuseIdentifier,
                                                                for: indexPath) as? LoadMoreMessagesView else {
            owsFailDebug("Couldn't load supplementary view: \(kind)")
            return UICollectionReusableView()
        }
        loadMoreView.configureForDisplay()
        return loadMoreView
    }

    public var indexPathOfUnreadIndicator: IndexPath? {
        renderState.indexPathOfUnreadIndicator
    }

    public func indexPath(forInteractionUniqueId interactionUniqueId: String) -> IndexPath? {
        renderState.indexPath(forInteractionUniqueId: interactionUniqueId)
    }
}

// MARK: -

extension CVLoadCoordinator: UICollectionViewDelegate {

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? CVItemCell else {
            owsFailDebug("Unexpected cell type.")
            return
        }
        cell.isCellVisible = true
        let delegate = self.delegate
        DispatchQueue.main.async {
            delegate?.updateScrollingContent()
            delegate?.updateAccessibilityCustomActionsForCell(cell)
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? CVItemCell else {
            owsFailDebug("Unexpected cell type.")
            return
        }
        cell.isCellVisible = false
        delegate?.updateScrollingContent()
    }
}

// MARK: -

extension CVLoadCoordinator: ConversationViewLayoutDelegate {

    public var layoutItems: [ConversationViewLayoutItem] {
        renderItems
    }

    public var showLoadOlderHeader: Bool {
        // We need to have at least one item to hang the supplementary view on.
        return canLoadOlderItems && !renderItems.isEmpty
    }

    public var showLoadNewerHeader: Bool {
        // We need to have at least one item to hang the supplementary view on.
        //
        // We could show both the "load older" and "load newer" items. If so we
        // need two items to hang the supplementary views on.
        let minItemCount = showLoadOlderHeader ? 2 : 1
        return canLoadNewerItems && renderItems.count >= minItemCount
    }

    public var layoutHeaderHeight: CGFloat {
        showLoadOlderHeader ? LoadMoreMessagesView.fixedHeight : 0
    }

    public var layoutFooterHeight: CGFloat {
        showLoadNewerHeader ? LoadMoreMessagesView.fixedHeight : 0
    }

    public var conversationViewController: ConversationViewController? {
        guard let delegate = self.delegate else {
            owsFailDebug("Missing delegate.")
            return nil
        }
        return delegate.conversationViewController
    }
}

// MARK: -

extension CVLoadCoordinator: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        delegate?.scrollViewDidScroll?(scrollView)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.scrollViewWillBeginDragging?(scrollView)
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        delegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        delegate?.scrollViewDidEndDecelerating?(scrollView)
    }

    public func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        delegate?.scrollViewShouldScrollToTop?(scrollView) ?? false
    }

    public func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        delegate?.scrollViewDidScrollToTop?(scrollView)
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        delegate?.scrollViewDidEndScrollingAnimation?(scrollView)
    }
}

// MARK: -

extension CVLoadCoordinator: CallServiceObserver {
    public func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        guard thread.isGroupV2Thread else {
            return
        }
        guard oldValue?.thread.uniqueId == thread.uniqueId ||
                newValue?.thread.uniqueId == thread.uniqueId else {
            return
        }
        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }
}
