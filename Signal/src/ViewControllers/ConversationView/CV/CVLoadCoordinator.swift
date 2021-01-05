//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

protocol CVLoadCoordinatorDelegate: UIScrollViewDelegate {
    var viewState: CVViewState { get }

    func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint

    func willUpdateWithNewRenderState(_ renderState: CVRenderState) -> CVUpdateToken

    func updateWithNewRenderState(update: CVUpdate,
                                  scrollAction: CVScrollAction,
                                  updateToken: CVUpdateToken)

    var isScrolledToBottom: Bool { get }

    var isScrollNearTopOfLoadWindow: Bool { get }

    var isScrollNearBottomOfLoadWindow: Bool { get }
}

// MARK: -

// This token lets CVC capture state from "before" a load
// lands that can be used when landing that load.
struct CVUpdateToken {
    let isScrolledToBottom: Bool
    let lastMessageForInboxSortId: UInt64?
}

// MARK: -

@objc
public class CVLoadCoordinator: NSObject {

    // MARK: - Dependencies

    private static var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    private static var profileManager: OWSProfileManager {
        return .shared()
    }

    private var typingIndicators: TypingIndicators {
        return SSKEnvironment.shared.typingIndicators
    }

    private var callService: CallService {
        return AppEnvironment.shared.callService
    }

    // MARK: -

    private weak var delegate: CVLoadCoordinatorDelegate?
    private weak var componentDelegate: CVComponentDelegate?

    private let viewState: CVViewState
    private var cellMediaCache: NSCache<NSString, AnyObject> { viewState.cellMediaCache }

    private let threadUniqueId: String

    private var conversationStyle: ConversationStyle

    var renderState: CVRenderState

    // CVC is perf-sensitive during its initial load and
    // presentation. We can use this flag to skip any expensive
    // work before the first load is complete.
    @objc
    public var hasRenderState: Bool {
        !renderState.isEmptyInitialState
    }

    @objc
    public var shouldHideCollectionViewContent = true {
        didSet {
            owsAssertDebug(!shouldHideCollectionViewContent)
        }
    }

    private var hasClearedUnreadMessagesIndicator = false

    private let messageMapping: CVMessageMapping

    // TODO: Remove. This model will get stale.
    private let thread: TSThread

    private var loadDidLandResolver: Resolver<Void>?

    required init(delegate: CVLoadCoordinatorDelegate,
                  componentDelegate: CVComponentDelegate,
                  conversationStyle: ConversationStyle,
                  focusMessageIdOnOpen: String?) {
        self.delegate = delegate
        self.componentDelegate = componentDelegate
        self.viewState = delegate.viewState
        let threadViewModel = viewState.threadViewModel
        self.threadUniqueId = threadViewModel.threadRecord.uniqueId
        self.thread = threadViewModel.threadRecord
        self.conversationStyle = conversationStyle

        let viewStateSnapshot = CVViewStateSnapshot.snapshot(viewState: viewState,
                                                             typingIndicatorsSender: nil,
                                                             hasClearedUnreadMessagesIndicator: hasClearedUnreadMessagesIndicator)
        self.renderState = CVRenderState.defaultRenderState(threadViewModel: threadViewModel,
                                                            viewStateSnapshot: viewStateSnapshot)

        self.messageMapping = CVMessageMapping(thread: threadViewModel.threadRecord)

        super.init()

        Self.databaseStorage.appendUIDatabaseSnapshotDelegate(self)

        // Kick off async load.
        loadInitialMapping(focusMessageIdOnOpen: focusMessageIdOnOpen)
    }

    // MARK: -

    @objc
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
                                               name: .blockListDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(localProfileDidChange),
                                               name: .localProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(otherUsersProfileDidChange(notification:)),
                                               name: .otherUsersProfileDidChange,
                                               object: nil)
        callService.addObserver(observer: self, syncStateImmediately: false)
    }

    @objc
    func applicationDidEnterBackground() {
         resetClearedUnreadMessagesIndicator()
    }

    @objc
    func typingIndicatorStateDidChange(notification: Notification) {
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
    func profileWhitelistDidChange() {
        AssertIsOnMainThread()

        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }

    @objc
    func blockListDidChange() {
        AssertIsOnMainThread()

        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }

    @objc
    func localProfileDidChange() {
        AssertIsOnMainThread()

        //        self.conversationProfileState = nil;
        enqueueReload(canReuseInteractionModels: true,
                      canReuseComponentStates: false)
    }

    @objc
    func otherUsersProfileDidChange(notification: Notification) {
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

    @objc
    public var canLoadOlderItems: Bool {
        renderState.canLoadOlderItems
    }

    @objc
    public var canLoadNewerItems: Bool {
        renderState.canLoadNewerItems
    }

    // MARK: - Load Requests

    // This property should only be accessed on the main thread.
    private var loadRequestBuilder = CVLoadRequest.Builder()

    // For thread safety, we can only have one load
    // in flight at a time. Entities like the MessageMapping
    // are not thread-safe.
    private let isLoading = AtomicBool(false)
    @objc
    public var hasLoadInFlight: Bool { isLoading.get() }

    private let autoLoadMoreThreshold: TimeInterval = 2 * kSecondInterval

    private var lastLoadOlderDate: Date?
    @objc
    public var didLoadOlderRecently: Bool {
        AssertIsOnMainThread()

        guard let lastLoadOlderDate = lastLoadOlderDate else {
            return false
        }
        return abs(lastLoadOlderDate.timeIntervalSinceNow) < autoLoadMoreThreshold
    }

    private var lastLoadNewerDate: Date?
    @objc
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

    @objc
    public func loadOlderItems() {
        guard !renderState.isEmptyInitialState else {
            return
        }
        loadRequestBuilder.loadOlderItems()
        loadIfNecessary()
    }

    @objc
    public func loadNewerItems() {
        guard !renderState.isEmptyInitialState else {
            return
        }
        loadRequestBuilder.loadNewerItems()
        loadIfNecessary()
    }

    @objc
    public func loadAndScrollToNewestItems(isAnimated: Bool) {
        loadRequestBuilder.loadAndScrollToNewestItems(isAnimated: isAnimated)
        loadIfNecessary()
    }

    @objc
    public func enqueueReload() {
        loadRequestBuilder.reload()
        loadIfNecessary()
    }

    public func enqueueReload(scrollAction: CVScrollAction) {
        loadRequestBuilder.reload(scrollAction: scrollAction)
        loadIfNecessary()
    }

    @objc
    public func enqueueReload(updatedInteractionIds: Set<String>,
                              deletedInteractionIds: Set<String>) {
        AssertIsOnMainThread()

        loadRequestBuilder.reload(updatedInteractionIds: updatedInteractionIds,
                                  deletedInteractionIds: deletedInteractionIds)
        loadIfNecessary()
    }

    @objc
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

    @objc
    public func enqueueReloadWithoutCaches() {
        AssertIsOnMainThread()

        loadRequestBuilder.reloadWithoutCaches()
        loadIfNecessary()
    }

    @objc
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

    @objc
    func clearUnreadMessagesIndicator() {
        AssertIsOnMainThread()

        // Once we've cleared the unread messages indicator,
        // make sure we don't show it again.
        hasClearedUnreadMessagesIndicator = true

        loadRequestBuilder.clearOldestUnreadInteraction()
        loadIfNecessary()
    }

    // MARK: -

    @objc
    func resetClearedUnreadMessagesIndicator() {
        AssertIsOnMainThread()

        hasClearedUnreadMessagesIndicator = false

        loadRequestBuilder.clearOldestUnreadInteraction()
        loadIfNecessary()
    }

    // MARK: -

    #if TESTABLE_BUILD
    @objc
    public let blockLoads = AtomicBool(false)
    #endif

    private func loadIfNecessary() {
        AssertIsOnMainThread()

        let conversationStyle = self.conversationStyle
        guard conversationStyle.viewWidth > 0 else {
            Logger.info("viewWidth not yet set.")
            return
        }
        guard let loadRequest = loadRequestBuilder.build() else {
            // No load is needed.
            return
        }
        #if TESTABLE_BUILD
        guard !blockLoads.get() else {
            return
        }
        #endif
        guard isLoading.tryToSetFlag() else {
            Logger.info("Ignoring; already loading.")
            return
        }

        loadRequestBuilder = CVLoadRequest.Builder()

        load(loadRequest: loadRequest,
             conversationStyle: conversationStyle)
    }

    private func load(loadRequest: CVLoadRequest, conversationStyle: ConversationStyle) {
        AssertIsOnMainThread()
        // We should do an "initial" load IFF this is our first load.
        owsAssertDebug(loadRequest.isInitialLoad == renderState.isEmptyInitialState)

        guard isLoading.get() else {
            owsFailDebug("isLoading not set.")
            return
        }
        let prevRenderState = renderState

        if loadRequest.loadType == .loadOlder {
            lastLoadOlderDate = Date()
        } else if loadRequest.loadType == .loadNewer {
            lastLoadNewerDate = Date()
        }

        let typingIndicatorsSender = typingIndicators.typingAddress(forThread: thread)
        let viewStateSnapshot = CVViewStateSnapshot.snapshot(viewState: viewState,
                                                             typingIndicatorsSender: typingIndicatorsSender,
                                                             hasClearedUnreadMessagesIndicator: hasClearedUnreadMessagesIndicator)
        let loader = CVLoader(threadUniqueId: threadUniqueId,
                              loadRequest: loadRequest,
                              viewStateSnapshot: viewStateSnapshot,
                              prevRenderState: prevRenderState,
                              messageMapping: messageMapping)

        firstly { () -> Promise<CVUpdate> in
            loader.loadPromise()
        }.then { [weak self] (update: CVUpdate) -> Promise<Void> in
            guard let self = self else {
                throw OWSGenericError("Missing self.")
            }
            guard let delegate = self.delegate else {
                throw OWSGenericError("Missing delegate.")
            }
            return self.loadLandWhenSafePromise(update: update, delegate: delegate)
        }.done { [weak self] () -> Void in
            guard let self = self else {
                throw OWSGenericError("Missing self.")
            }
            guard self.isLoading.tryToClearFlag() else {
                owsFailDebug("Could not clear isLoading flag.")
                return
            }
            // Initiate new load if necessary.
            self.loadIfNecessary()
        }.catch(on: CVUtils.workQueue) { [weak self] (error) in
            guard let self = self else {
                return
            }
            owsFailDebug("Error: \(error)")
            guard self.isLoading.tryToClearFlag() else {
                owsFailDebug("Could not clear isLoading flag.")
                return
            }
            // Initiate new load if necessary.
            self.loadIfNecessary()
        }
    }

    // MARK: - Safe Landing

    // Lands the load when its safe, blocking on scrolling.
    private func loadLandWhenSafePromise(update: CVUpdate,
                                         delegate: CVLoadCoordinatorDelegate) -> Promise<Void> {
        AssertIsOnMainThread()

        let (loadPromise, loadResolver) = Promise<Void>.pending()

        let viewState = self.viewState
        func canLandLoad() -> Bool {
            // Ensure isUserScrolling is a substate of hasScrollingAnimation.
            if viewState.isUserScrolling {
                owsAssertDebug(viewState.hasScrollingAnimation)
            }
            guard viewState.hasScrollingAnimation else {
                // If no scroll gesture or animation is in progress,
                // we can land the load.
                return true
            }
            if let delegate = self.delegate {
                if update.loadType == .loadOlder,
                   delegate.isScrollNearTopOfLoadWindow {
                    // If a scroll animation is progress, but we're very
                    // close to the edge of the load window, land the load.
                    return true
                } else if update.loadType == .loadNewer,
                          delegate.isScrollNearBottomOfLoadWindow {
                    // If a scroll animation is progress, but we're very
                    // close to the edge of the load window, land the load.
                    return true
                }
            }
            return false
        }

        func tryToResolve() {
            guard canLandLoad() else {
                // TODO: async() or asyncAfter()?
                Logger.verbose("Waiting to land load.")
                // We wait in a pretty tight loop to ensure loads land in a timely way.
                //
                // DispatchQueue.asyncAfter() will take longer to perform
                // its block than DispatchQueue.async() if the CPU is under
                // heavy load. That's desirable in this case.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                    tryToResolve()
                }
                return
            }

            let renderState = update.renderState
            let updateToken = delegate.willUpdateWithNewRenderState(renderState)

            self.renderState = renderState

            let (loadDidLandPromise, loadDidLandResolver) = Promise<Void>.pending()
            self.loadDidLandResolver = loadDidLandResolver

            let loadRequest = update.loadRequest
            delegate.updateWithNewRenderState(update: update,
                                              scrollAction: loadRequest.scrollAction,
                                              updateToken: updateToken)

            firstly { () -> Promise<Void> in
                // We've started the process of landing the load,
                // but its completion may be async.
                //
                // Block on load land completion.
                loadDidLandPromise
            }.done(on: .global()) {
                loadResolver.fulfill(())
            }.catch(on: .global()) { error in
                loadResolver.reject(error)
            }
        }

        tryToResolve()

        return loadPromise
    }

    // -

    public func loadDidLand() {
        AssertIsOnMainThread()
        guard let loadDidLandResolver = loadDidLandResolver else {
            owsFailDebug("Missing loadDidLandResolver.")
            return
        }
        loadDidLandResolver.fulfill(())
        self.loadDidLandResolver = nil
    }
}

// MARK: -

extension CVLoadCoordinator: UIDatabaseSnapshotDelegate {

    public func uiDatabaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)
    }

    public func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        guard databaseChanges.threadUniqueIds.contains(threadUniqueId) else {
            return
        }
        enqueueReload(updatedInteractionIds: databaseChanges.interactionUniqueIds,
                      deletedInteractionIds: databaseChanges.interactionDeletedUniqueIds)
    }

    public func uiDatabaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        enqueueReloadWithoutCaches()
    }

    public func uiDatabaseSnapshotDidReset() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        enqueueReloadWithoutCaches()
    }
}

// MARK: -

@objc
extension CVLoadCoordinator: UICollectionViewDataSource {

    public static let messageSection: Int = 0

    public var renderItems: [CVRenderItem] {
        AssertIsOnMainThread()

        return shouldHideCollectionViewContent ? [] : renderState.items
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
        let cellSelection = delegate.viewState.cellSelection
        let swipeToReplyState = delegate.viewState.swipeToReplyState
        cell.configure(renderItem: renderItem,
                       componentDelegate: componentDelegate,
                       cellSelection: cellSelection,
                       swipeToReplyState: swipeToReplyState)
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
        //        cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, cellName);
        //#endif
        //
        //return cell;
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

@objc
extension CVLoadCoordinator: UICollectionViewDelegate {

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? CVItemCell else {
            owsFailDebug("Unexpected cell type.")
            return
        }
        cell.isCellVisible = true
    }

    public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? CVItemCell else {
            owsFailDebug("Unexpected cell type.")
            return
        }
        cell.isCellVisible = false
    }

    // We use this hook to ensure scroll state continuity.  As the collection
    // view's content size changes, we want to keep the same cells in view.
    public func collectionView(_ collectionView: UICollectionView,
                               targetContentOffsetForProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {

        guard let delegate = self.delegate else {
            owsFailDebug("Missing delegate.")
            return proposedContentOffset
        }
        return delegate.targetContentOffset(forProposedContentOffset: proposedContentOffset)
    }
}

// MARK: -

@objc
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

    public func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        guard let delegate = self.delegate else {
            owsFailDebug("Missing delegate.")
            return proposedContentOffset
        }
        return delegate.targetContentOffset(forProposedContentOffset: proposedContentOffset)
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
