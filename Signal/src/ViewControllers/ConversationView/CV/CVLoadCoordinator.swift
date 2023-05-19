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

    var isLayoutApplyingUpdate: Bool { get }

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
    private let spoilerReveal: SpoilerRevealState

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

    required init(viewState: CVViewState, oldestUnreadMessageSortId: UInt64?) {
        self.viewState = viewState
        let threadViewModel = viewState.threadViewModel
        self.threadUniqueId = threadViewModel.threadRecord.uniqueId
        self.thread = threadViewModel.threadRecord
        self.conversationStyle = viewState.conversationStyle
        self.spoilerReveal = viewState.spoilerReveal
        self.oldestUnreadMessageSortId = oldestUnreadMessageSortId
        let viewStateSnapshot = CVViewStateSnapshot.snapshot(
            viewState: viewState,
            typingIndicatorsSender: nil,
            oldestUnreadMessageSortId: oldestUnreadMessageSortId,
            previousViewStateSnapshot: nil
        )
        self.renderState = CVRenderState.defaultRenderState(
            threadViewModel: threadViewModel,
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
                                               selector: #selector(conversationChatColorSettingDidChange),
                                               name: ChatColors.conversationChatColorSettingDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(customChatColorsDidChange),
                                               name: ChatColors.customChatColorsDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(autoChatColorsDidChange),
                                               name: ChatColors.autoChatColorsDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(phoneNumberDidChange),
                                               name: SignalRecipient.phoneNumberDidChange,
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
    private func phoneNumberDidChange(notification: Notification) {
        AssertIsOnMainThread()

        var notificationAddressKeys = Set<String>()
        if let phoneNumber = notification.userInfo?[SignalRecipient.notificationKeyPhoneNumber] as? String {
            notificationAddressKeys.insert(phoneNumber)
        }
        if let uuid = notification.userInfo?[SignalRecipient.notificationKeyUUID] as? String {
            notificationAddressKeys.insert(uuid)
        }

        var threadAddressKeys = Set<String>()
        for address in thread.recipientAddressesWithSneakyTransaction {
            if let uuidString = address.uuidString {
                threadAddressKeys.insert(uuidString)
            }
            if let phoneNumber = address.phoneNumber {
                threadAddressKeys.insert(phoneNumber)
            }
        }
        let shouldReload = !notificationAddressKeys.isDisjoint(with: threadAddressKeys)
        if shouldReload {
            enqueueReloadWithoutCaches()
        }
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
    private func conversationChatColorSettingDidChange(_ notification: NSNotification) {
        guard let threadUniqueId = notification.userInfo?[ChatColors.conversationChatColorSettingDidChangeThreadUniqueIdKey] as? String else {
            owsFailDebug("Missing threadUniqueId.")
            return
        }
        guard threadUniqueId == thread.uniqueId else {
            return
        }
        delegate?.chatColorDidChange()
    }

    @objc
    private func customChatColorsDidChange(_ notification: NSNotification) {
        delegate?.chatColorDidChange()
    }

    @objc
    private func autoChatColorsDidChange(_ notification: NSNotification) {
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

    // We should only have one "building" and one "landing"
    // in flight at a time. We _can_ start building request B
    // while A is still "landing", but only after its landing
    // has _begun_ (but not yet complete).
    //
    // We can only build one load at a time more many reasons.
    // Entities like the MessageMapping are not thread-safe.
    // Each load is based
    private let loadBuildingRequestId = AtomicOptional<CVLoadRequest.RequestId>(nil)
    private let loadLandingRequestId = AtomicOptional<CVLoadRequest.RequestId>(nil)
    private static let canOverlapLandingAnimations = true

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
        let spoilerReveal = self.spoilerReveal
        guard conversationStyle.viewWidth > 0 else {
            Logger.info("viewWidth not yet set.")
            return
        }
        guard let loadRequest = loadRequestBuilder.build() else {
            // No load is needed.
            return
        }
        if CVLoader.verboseLogging {
            Logger.info("Trying to begin load.")
        }
        guard loadBuildingRequestId.tryToSetIfNil(loadRequest.requestId) else {
            Logger.verbose("Ignoring; already loading.")
            return
        }
        loadRequestBuilder.loadBegun()
        if CVLoader.verboseLogging {
            Logger.info("Loading[\(loadRequest.requestId)]")
        }

        loadRequestBuilder = CVLoadRequest.Builder()

        load(
            loadRequest: loadRequest,
            conversationStyle: conversationStyle,
            spoilerReveal: spoilerReveal
        )
    }

    private func load(
        loadRequest: CVLoadRequest,
        conversationStyle: ConversationStyle,
        spoilerReveal: SpoilerRevealState
    ) {
        AssertIsOnMainThread()
        // We should do an "initial" load IFF this is our first load.
        owsAssertDebug(loadRequest.isInitialLoad == renderState.isEmptyInitialState)

        guard loadBuildingRequestId.get() == loadRequest.requestId else {
            owsFailDebug("loadBuildingRequestId is not set.")
            return
        }
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
            spoilerReveal: spoilerReveal,
            prevRenderState: prevRenderState,
            messageLoader: messageLoader
        )

        if CVLoader.verboseLogging {
            Logger.info("Before load promise[\(loadRequest.requestId)]")
        }

        firstly {
            loader.loadPromise()
        }.then(on: DispatchQueue.main) { [weak self] (update: CVUpdate) -> Promise<CVUpdate> in
            loadRequest.logLoadEvent("Load landing ready")
            guard let self = self else {
                throw OWSGenericError("Missing self.")
            }
            return self.loadLandWhenSafePromise(update: update)
        }.done(on: DispatchQueue.main) { [weak self] (update: CVUpdate) -> Void in
            self?.loadDidSucceed(update: update)
        }.catch(on: DispatchQueue.main) { [weak self] (error) in
            self?.loadDidFail(loadRequest: loadRequest, error: error)
        }
    }

    private func loadDidSucceed(update: CVUpdate) {
        AssertIsOnMainThread()

        let loadRequest = update.loadRequest
        loadRequest.logLoadEvent("Load complete \(update.prevRenderState.items.count) -> \(renderState.items.count)")

        let didClearBuildingFlag = loadBuildingRequestId.tryToClearIfEqual(loadRequest.requestId)
        // This flag should already be cleared.
        owsAssertDebug(!didClearBuildingFlag)
        let didClearLandingFlag = loadLandingRequestId.tryToClearIfEqual(loadRequest.requestId)
        if Self.canOverlapLandingAnimations {
            owsAssertDebug(!didClearLandingFlag)
        } else {
            owsAssertDebug(didClearLandingFlag)
        }

        // Initiate new load if necessary.
        loadIfNecessary()
    }

    private func loadDidFail(loadRequest: CVLoadRequest, error: Error) {
        AssertIsOnMainThread()

        owsFailDebug("Load failed[\(loadRequest.requestId)]: \(error)")

        let didClearBuildingFlag = loadBuildingRequestId.tryToClearIfEqual(loadRequest.requestId)
        let didClearLandingFlag = loadLandingRequestId.tryToClearIfEqual(loadRequest.requestId)
        owsAssertDebug(didClearBuildingFlag || didClearLandingFlag)

        // Initiate new load if necessary.
        loadIfNecessary()
    }

    // MARK: - Safe Landing

    // Lands the load when it is safe, blocking on animations,
    // previous loads landing, etc.
    private func loadLandWhenSafePromise(update: CVUpdate) -> Promise<CVUpdate> {
        AssertIsOnMainThread()

        let (loadPromise, loadFuture) = Promise<CVUpdate>.pending()

        loadLandWhenSafe(update: update, loadFuture: loadFuture)

        return loadPromise
    }

    private func loadLandWhenSafe(update: CVUpdate, loadFuture: Future<CVUpdate>) {

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
                if CVLoader.verboseLogging {
                    Logger.verbose("Waiting for keyboard animation.")
                }
                return false
            }
            guard viewState.selectionAnimationState != .animating  else {
                if CVLoader.verboseLogging {
                    Logger.verbose("Waiting for selection animation.")
                }
                return false
            }
            if let interaction = viewState.collectionViewActiveContextMenuInteraction, interaction.contextMenuVisible {
                if CVLoader.verboseLogging {
                    Logger.verbose("Waiting for context menu animation.")
                }
                return false
            }
            guard Self.canOverlapLandingAnimations || !delegate.isLayoutApplyingUpdate else {
                if CVLoader.verboseLogging {
                    Logger.verbose("Waiting for isLayoutApplyingUpdate.")
                }
                return false
            }
            guard !delegate.areCellsAnimating else {
                if CVLoader.verboseLogging {
                    Logger.verbose("Waiting for areCellsAnimating.")
                }
                return false
            }
            return true
        }

        let loadRequest = update.loadRequest

        // It's important that we only set loadLandingRequestId if canLandLoad is true.
        guard canLandLoad(),
              self.loadLandingRequestId.tryToSetIfNil(loadRequest.requestId) else {

            if CVLoader.verboseLogging {
                Logger.verbose("Waiting to land load.")
            }
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

        let (loadDidLandPromise, loadDidLandFuture) = Promise<Void>.pending()
        updateLoadLanding(renderState: renderState,
                          loadRequest: loadRequest,
                          loadDidLandFuture: loadDidLandFuture)

        delegate.updateWithNewRenderState(update: update,
                                          scrollAction: loadRequest.scrollAction,
                                          updateToken: updateToken)

        loadRequest.logLoadEvent("Load landing begun \(update.prevRenderState.items.count) -> \(renderState.items.count)")

        // Once this load's landing has _begun_ we can start building the next load.
        // loadLandingRequestId ensures that we only land one load at a time.
        //
        // We cannot start building the next load until this point, since the next
        // load will...
        //
        // * ...use the current renderState state as a point of departure.
        // * ...assume the UICollectionView has already been updated to reflect
        //   this load, so that it can safely performBatchUpdates().
        let didClearBuildingFlag = self.loadBuildingRequestId.tryToClearIfEqual(loadRequest.requestId)
        owsAssertDebug(didClearBuildingFlag)

        // If we can overlap landing animations, we can start landing the next
        // load immediately after we start landing this load.  If we commit to
        // this behavior, we can eliminate loadLandingRequestId.
        if Self.canOverlapLandingAnimations {
            loadDidLandImmediately()

            let didClearLandingFlag = loadLandingRequestId.tryToClearIfEqual(loadRequest.requestId)
            owsAssertDebug(didClearLandingFlag)
        }

        // Initiate new load if necessary.
        loadIfNecessary()

        // Wait for landing to complete.
        firstly { () -> Promise<Void> in
            loadDidLandPromise
        }.done(on: CVUtils.landingQueue) {
            loadRequest.logLoadEvent("Load landing complete")
            loadFuture.resolve(update)
        }.catch(on: CVUtils.landingQueue) { error in
            loadFuture.reject(error)
        }
    }

    // MARK: - LoadLanding

    private struct LoadLanding {
        let renderStateId: UInt
        let loadRequestId: UInt
        private var loadDidLandFuture: Future<Void>?

        init(renderStateId: UInt, loadRequestId: UInt, loadDidLandFuture: Future<Void>) {
            self.renderStateId = renderStateId
            self.loadRequestId = loadRequestId
            self.loadDidLandFuture = loadDidLandFuture
        }

        func fulfill() {
            AssertIsOnMainThread()

            guard let loadDidLandFuture = self.loadDidLandFuture else {
                owsFailDebug("Missing loadDidLandFuture.")
                return
            }
            if CVLoader.verboseLogging {
                Logger.info("LoadLanding fulfilled[\(loadRequestId)]")
            }
            loadDidLandFuture.resolve()
        }
    }
    private var currentLoadLanding: LoadLanding?

    private func updateLoadLanding(renderState: CVRenderState,
                                   loadRequest: CVLoadRequest,
                                   loadDidLandFuture: Future<Void>) {
        if let currentLoadLanding = self.currentLoadLanding {
            currentLoadLanding.fulfill()
        }
        self.currentLoadLanding = LoadLanding(renderStateId: renderState.renderStateId,
                                              loadRequestId: loadRequest.requestId,
                                              loadDidLandFuture: loadDidLandFuture)
    }

    func loadDidLandInView(renderState: CVRenderState) {
        AssertIsOnMainThread()

        guard let currentLoadLanding = currentLoadLanding,
              currentLoadLanding.renderStateId == renderState.renderStateId else {
            return
        }
        currentLoadLanding.fulfill()
        self.currentLoadLanding = nil
    }

    func loadDidLandImmediately() {
        AssertIsOnMainThread()

        currentLoadLanding?.fulfill()
        self.currentLoadLanding = nil
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
