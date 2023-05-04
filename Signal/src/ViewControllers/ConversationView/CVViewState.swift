//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol CVViewStateDelegate: AnyObject {
    func viewStateUIModeDidChange(oldValue: ConversationUIMode)
}

// MARK: -

// This can be a simple place to hang CVC's mutable view state.
//
// These properties should only be accessed on the main thread.
public class CVViewState: NSObject {
    public weak var delegate: CVViewStateDelegate?

    public var threadViewModel: ThreadViewModel
    public var conversationStyle: ConversationStyle
    public var inputToolbar: ConversationInputToolbar?
    public let headerView = ConversationHeaderView()

    public var hasTriedToMigrateGroup = false

    public let inputAccessoryPlaceholder = InputAccessoryViewPlaceholder()
    public var bottomBar = UIView.container()
    public var bottomBarBottomConstraint: NSLayoutConstraint?
    public var requestView: UIView?
    public var bannerView: UIView?
    public var groupNameCollisionFinder: GroupMembershipNameCollisionFinder?

    public var isDismissingInteractively = false

    public var isViewCompletelyAppeared = false
    public var isViewVisible = false
    public var shouldAnimateKeyboardChanges = false
    public var isInPreviewPlatter = false
    public let viewCreationDate = Date()
    public var hasAppliedFirstLoad = false

    public var isUserScrolling = false
    public var scrollingAnimationCompletionTimer: Timer?
    public var hasScrollingAnimation: Bool {
        AssertIsOnMainThread()

        return scrollingAnimationCompletionTimer != nil
    }
    public var scrollActionForSizeTransition: CVScrollAction?
    public var scrollActionForUpdate: CVScrollAction?
    public var lastKnownDistanceFromBottom: CGFloat?
    public var lastSearchedText: String?

    public var activeCellAnimations = Set<UUID>()

    public func beginCellAnimation(identifier: UUID) {
        activeCellAnimations.insert(identifier)
    }

    public func endCellAnimation(identifier: UUID) {
        activeCellAnimations.remove(identifier)
    }

    var bottomViewType: CVCBottomViewType = .none

    public var uiMode: ConversationUIMode = .normal {
        didSet {
            AssertIsOnMainThread()
            let didChange = uiMode != oldValue
            if didChange {
                selectionState.reset()
                delegate?.viewStateUIModeDidChange(oldValue: oldValue)
            }
        }
    }

    enum SelectionAnimationState { case idle, willAnimate, animating }
    var selectionAnimationState: SelectionAnimationState = .idle

    public let selectionState = CVSelectionState()
    public let textExpansion = CVTextExpansion()
    public let spoilerReveal = CVSpoilerReveal()
    public let messageSwipeActionState = CVMessageSwipeActionState()

    public var isDarkThemeEnabled: Bool = Theme.isDarkThemeEnabled

    public var sendMessageController: SendMessageController?

    public let mediaCache = CVMediaCache()

    public let contactShareViewHelper = ContactShareViewHelper()

    public var userHasScrolled = false

    public var groupCallTooltip: GroupCallTooltip?
    public var groupCallTooltipTailReferenceView: UIView?
    public var hasIncrementedGroupCallTooltipShownCount = false
    public var groupCallBarButtonItem: UIBarButtonItem?

    public var lastMessageSentDate: Date?

    public let scrollDownButton = ConversationScrollButton(iconName: "chevron-down-20")
    public var isHidingScrollDownButton = false
    public let scrollToNextMentionButton = ConversationScrollButton(iconName: "at-icon")
    public var isHidingScrollToNextMentionButton = false
    public var scrollUpdateTimer: Timer?
    public var isWaitingForDeceleration = false

    public var unreadMessageCount: UInt = 0
    public var unreadMentionMessages = [TSMessage]()

    public var actionOnOpen: ConversationViewAction = .none

    public var readTimer: Timer?
    public var reloadTimer: Timer?

    public var lastSortIdMarkedRead: UInt64 = 0
    public var isMarkingAsRead = false

    // MARK: - Gestures

    public let collectionViewTapGestureRecognizer = UITapGestureRecognizer()
    public let collectionViewLongPressGestureRecognizer = UILongPressGestureRecognizer()
    public let collectionViewContextMenuGestureRecognizer = UILongPressGestureRecognizer()
    public var collectionViewContextMenuSecondaryClickRecognizer: UITapGestureRecognizer?

    public let collectionViewPanGestureRecognizer = UIPanGestureRecognizer()
    public var collectionViewActiveContextMenuInteraction: ChatHistoryContextMenuInteraction?
    public var longPressHandler: CVLongPressHandler?
    public var panHandler: CVPanHandler?

    // MARK: -

    var initialScrollState: CVInitialScrollState?

    public var presentationStatus: CVPresentationStatus = .notYetPresented

    #if TESTABLE_BUILD
    public let initialLoadBenchSteps = BenchSteps(title: "initialLoadBenchSteps")
    public let presentationStatusBenchSteps = BenchSteps(title: "presentationStatusBenchSteps")
    #endif

    public let backgroundContainer = CVBackgroundContainer()

    weak var reactionsDetailSheet: ReactionsDetailSheet?

    public var lastKeyboardAnimationDate: Date?

    // MARK: - Voice Messages

    var inProgressVoiceMessage: VoiceMessageInProgressDraft?

    // MARK: - Gift Badges

    var shakenGiftMessageIds = Set<String>()

    var unwrappedGiftMessageIds = Set<String>()

    // MARK: - 

    public required init(threadViewModel: ThreadViewModel, conversationStyle: ConversationStyle) {
        self.threadViewModel = threadViewModel
        self.conversationStyle = conversationStyle
    }
}

// MARK: -

public extension ConversationViewController {

    var threadViewModel: ThreadViewModel { renderState.threadViewModel }

    @objc
    var thread: TSThread { threadViewModel.threadRecord }

    var disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration { threadViewModel.disappearingMessagesConfiguration }

    var conversationStyle: ConversationStyle {
        get { viewState.conversationStyle }
        set { viewState.conversationStyle = newValue }
    }

    var headerView: ConversationHeaderView { viewState.headerView }

    var inputToolbar: ConversationInputToolbar? {
        get { viewState.inputToolbar }
        set { viewState.inputToolbar = newValue }
    }

    var inputAccessoryPlaceholder: InputAccessoryViewPlaceholder {
        viewState.inputAccessoryPlaceholder
    }

    var bottomBar: UIView {
        viewState.bottomBar
    }

    var bottomBarBottomConstraint: NSLayoutConstraint? {
        get { viewState.bottomBarBottomConstraint }
        set { viewState.bottomBarBottomConstraint = newValue }
    }

    var requestView: UIView? {
        get { viewState.requestView }
        set { viewState.requestView = newValue }
    }

    var bannerView: UIView? {
        get { viewState.bannerView }
        set { viewState.bannerView = newValue }
    }

    var isDismissingInteractively: Bool {
        get { viewState.isDismissingInteractively }
        set { viewState.isDismissingInteractively = newValue }
    }

    var isViewCompletelyAppeared: Bool {
        get { viewState.isViewCompletelyAppeared }
        set { viewState.isViewCompletelyAppeared = newValue }
    }

    var shouldAnimateKeyboardChanges: Bool {
        get { viewState.shouldAnimateKeyboardChanges }
        set { viewState.shouldAnimateKeyboardChanges = newValue }
    }

    var isUserScrolling: Bool {
        get { viewState.isUserScrolling }
        set { viewState.isUserScrolling = newValue }
    }

    var scrollingAnimationCompletionTimer: Timer? {
        get { viewState.scrollingAnimationCompletionTimer }
        set { viewState.scrollingAnimationCompletionTimer = newValue }
    }

    var hasScrollingAnimation: Bool { viewState.hasScrollingAnimation }

    var uiMode: ConversationUIMode {
        get { viewState.uiMode }
        set {
            let oldValue = viewState.uiMode
            guard oldValue != newValue else {
                return
            }
            viewState.uiMode = newValue
            uiModeDidChange(oldValue: oldValue)
        }
    }

    var isShowingSelectionUI: Bool { viewState.uiMode.hasSelectionUI }

    var lastSearchedText: String? {
        get { viewState.lastSearchedText }
        set { viewState.lastSearchedText = newValue }
    }

    var isDarkThemeEnabled: Bool {
        get { viewState.isDarkThemeEnabled }
        set { viewState.isDarkThemeEnabled = newValue }
    }

    var isMeasuringKeyboardHeight: Bool { inputToolbar?.isMeasuringKeyboardHeight ?? false }

    var mediaCache: CVMediaCache { viewState.mediaCache }

    var groupCallBarButtonItem: UIBarButtonItem? {
        get { viewState.groupCallBarButtonItem }
        set { viewState.groupCallBarButtonItem = newValue }
    }

    var lastMessageSentDate: Date? {
        get { viewState.lastMessageSentDate }
        set { viewState.lastMessageSentDate = newValue }
    }

    var actionOnOpen: ConversationViewAction {
        get { viewState.actionOnOpen }
        set { viewState.actionOnOpen = newValue }
    }

    // MARK: - Gestures

    var collectionViewTapGestureRecognizer: UITapGestureRecognizer {
        viewState.collectionViewTapGestureRecognizer
    }
    var collectionViewLongPressGestureRecognizer: UILongPressGestureRecognizer {
        viewState.collectionViewLongPressGestureRecognizer
    }
    var collectionViewContextMenuGestureRecognizer: UILongPressGestureRecognizer {
        viewState.collectionViewContextMenuGestureRecognizer
    }
    var collectionViewContextMenuSecondaryClickRecognizer: UITapGestureRecognizer? {
        get { viewState.collectionViewContextMenuSecondaryClickRecognizer }
        set { viewState.collectionViewContextMenuSecondaryClickRecognizer = newValue }

    }

    var collectionViewPanGestureRecognizer: UIPanGestureRecognizer {
        viewState.collectionViewPanGestureRecognizer
    }

    var collectionViewActiveContextMenuInteraction: ChatHistoryContextMenuInteraction? {
        get { viewState.collectionViewActiveContextMenuInteraction }
        set { viewState.collectionViewActiveContextMenuInteraction = newValue }
    }

    var backgroundContainer: CVBackgroundContainer { viewState.backgroundContainer }
    internal var reactionsDetailSheet: ReactionsDetailSheet? {
        get { viewState.reactionsDetailSheet }
        set { viewState.reactionsDetailSheet = newValue }
    }
    var contactShareViewHelper: ContactShareViewHelper { viewState.contactShareViewHelper }

    // MARK: -

    #if TESTABLE_BUILD
    var initialLoadBenchSteps: BenchSteps { viewState.initialLoadBenchSteps }
    #endif
}

// MARK: -

extension CVViewState {

    var asCoreState: CVCoreState {
        CVCoreState(conversationStyle: conversationStyle, mediaCache: mediaCache)
    }
}

// MARK: -

// Accessors for the non-@objc properties.
extension ConversationViewController {

    var longPressHandler: CVLongPressHandler? {
        get { viewState.longPressHandler }
        set { viewState.longPressHandler = newValue }
    }

    var panHandler: CVPanHandler? {
        get { viewState.panHandler }
        set { viewState.panHandler = newValue }
    }

    public var selectionState: CVSelectionState { viewState.selectionState }

    func isTextExpanded(interactionId: String) -> Bool {
        viewState.textExpansion.isTextExpanded(interactionId: interactionId)
    }

    func setTextExpanded(interactionId: String) {
        viewState.textExpansion.setTextExpanded(interactionId: interactionId)
    }

    var initialScrollState: CVInitialScrollState? {
        get { viewState.initialScrollState }
        set { viewState.initialScrollState = newValue }
    }

    var lastKnownDistanceFromBottom: CGFloat? {
        get { viewState.lastKnownDistanceFromBottom }
        set { viewState.lastKnownDistanceFromBottom = newValue }
    }

    var sendMessageController: SendMessageController? {
        get { viewState.sendMessageController }
        set { viewState.sendMessageController = newValue }
    }
}

// MARK: -

// This struct facilitates passing around a few key
// pieces of CVC state during async loads.
struct CVCoreState {
    let conversationStyle: ConversationStyle
    let mediaCache: CVMediaCache
}

// MARK: -

public class CVTextExpansion {
    private var expandedTextInteractionsIds = Set<String>()

    required init(expandedTextInteractionsIds: Set<String>? = nil) {
        if let expandedTextInteractionsIds = expandedTextInteractionsIds {
            self.expandedTextInteractionsIds = expandedTextInteractionsIds
        }
    }

    public func isTextExpanded(interactionId: String) -> Bool {
        expandedTextInteractionsIds.contains(interactionId)
    }

    public func setTextExpanded(interactionId: String) {
        expandedTextInteractionsIds.insert(interactionId)
    }

    func copy() -> CVTextExpansion {
        CVTextExpansion(expandedTextInteractionsIds: expandedTextInteractionsIds)
    }

    //    // TODO: collapseCutoffDate
    //    let collapseCutoffDate = Date()
}

// MARK: -

public protocol CVSpoilerObserver: NSObjectProtocol {
    func didUpdateRevealedSpoilers()
}

@objc
public class CVSpoilerReveal: NSObject {
    private var revealedSpoilerIdsByMessage = [CVInteractionIdentifier: Set<StyleIdType>]()

    /// Returns the set of IDs in the ordered list of spoiler ranges for a given message that
    /// should be revealed.
    public func revealedSpoilerIds(
        interactionIdentifier: CVInteractionIdentifier
    ) -> Set<StyleIdType> {
        return revealedSpoilerIdsByMessage[interactionIdentifier] ?? []
    }

    public func setSpoilerRevealed(
        withID id: StyleIdType,
        interactionIdentifier: CVInteractionIdentifier
    ) {
        var revealedIds = revealedSpoilerIdsByMessage[interactionIdentifier] ?? Set()
        revealedIds.insert(id)
        revealedSpoilerIdsByMessage[interactionIdentifier] = revealedIds
        observers[interactionIdentifier]?.forEach {
            $0.value?.didUpdateRevealedSpoilers()
        }
    }

    private var observers = [CVInteractionIdentifier: [Weak<CVSpoilerObserver>]]()

    public func observeChanges(
        for interactionIdentifier: CVInteractionIdentifier,
        observer: CVSpoilerObserver
    ) {
        var observers = observers[interactionIdentifier] ?? []
        guard !observers.contains(where: {
            $0.value === observer
        }) else {
            return
        }
        observers.append(Weak(value: observer))
        self.observers[interactionIdentifier] = observers
    }

    public func removeObserver(
        for interactionIdentifier: CVInteractionIdentifier,
        observer: CVSpoilerObserver
    ) {
        var observers = observers[interactionIdentifier] ?? []
        observers.removeAll(where: {
            $0.value === observer
        })
        self.observers[interactionIdentifier] = observers
    }

    func copy() -> CVSpoilerReveal {
        let returnValue = CVSpoilerReveal()
        returnValue.revealedSpoilerIdsByMessage = revealedSpoilerIdsByMessage
        return returnValue
    }

    public override func isEqual(_ object: Any?) -> Bool {
        let lhs = self
        guard let rhs = object as? CVSpoilerReveal else {
            return false
        }
        guard lhs.revealedSpoilerIdsByMessage == rhs.revealedSpoilerIdsByMessage else {
            return false
        }
        guard lhs.observers.count == rhs.observers.count else {
            return false
        }
        for key in lhs.observers.keys {
            guard let lhsObs = lhs.observers[key], let rhsObs = rhs.observers[key] else {
                return false
            }
            guard lhsObs.count == rhsObs.count else {
                return false
            }
            for i in 0..<lhsObs.count {
                guard lhsObs[i].value === rhsObs[i].value else {
                    return false
                }
            }
        }
        return true
    }
}

// MARK: -

public class CVMessageSwipeActionState {
    public struct Progress {
        let xOffset: CGFloat
    }

    public typealias ProgressMap = [String: Progress]
    private var progressMap = ProgressMap()

    required init(progressMap: ProgressMap? = nil) {
        if let progressMap = progressMap {
            self.progressMap = progressMap
        }
    }

    public func getProgress(interactionId: String) -> Progress? {
        progressMap[interactionId]
    }

    public func setProgress(interactionId: String, progress: Progress) {
        progressMap[interactionId] = progress
    }

    public func resetProgress(interactionId: String) {
        progressMap[interactionId] = nil
    }

    func copy() -> CVMessageSwipeActionState {
        CVMessageSwipeActionState(progressMap: progressMap)
    }
}

// MARK: -

// Describes the initial scroll state when we present CVC.
//
// Initial scroll state only applies until the first time
// CVC.viewDidAppear() is called.
struct CVInitialScrollState {
    let focusMessageId: String?
}

// MARK: -

// Records whether or not the conversation view
// has ever reached these milestones of its lifecycle.
public enum CVPresentationStatus: UInt, CustomStringConvertible {
    case notYetPresented = 0
    case firstViewWillAppearHasBegun
    case firstViewWillAppearHasCompleted
    case firstViewDidAppearHasBegun
    case firstViewDidAppearHasCompleted

    public var description: String {
        switch self {
        case .notYetPresented:
            return ".notYetPresented"
        case .firstViewWillAppearHasBegun:
            return ".firstViewWillAppearHasBegun"
        case .firstViewWillAppearHasCompleted:
            return ".firstViewWillAppearHasCompleted"
        case .firstViewDidAppearHasBegun:
            return ".firstViewDidAppearHasBegun"
        case .firstViewDidAppearHasCompleted:
            return ".firstViewDidAppearHasCompleted"
        }
    }
}

// MARK: -

public extension ConversationViewController {

    var presentationStatus: CVPresentationStatus { viewState.presentationStatus }

    private func updatePresentationStatus(_ value: CVPresentationStatus) {
        AssertIsOnMainThread()

        if viewState.presentationStatus.rawValue < value.rawValue {
            Logger.verbose("presentationStatus: \(viewState.presentationStatus) -> \(value).")

            #if TESTABLE_BUILD
            viewState.presentationStatusBenchSteps.step(value.description)
            if value == .firstViewDidAppearHasCompleted {
                viewState.presentationStatusBenchSteps.logAll()
            }
            #endif

            viewState.presentationStatus = value
        }
    }

    func viewWillAppearDidBegin() {
        updatePresentationStatus(.firstViewWillAppearHasBegun)
    }

    func viewWillAppearDidComplete() {
        updatePresentationStatus(.firstViewWillAppearHasCompleted)
    }

    func viewDidAppearDidBegin() {
        updatePresentationStatus(.firstViewDidAppearHasBegun)
    }

    func viewDidAppearDidComplete() {
        updatePresentationStatus(.firstViewDidAppearHasCompleted)
    }

    var hasViewWillAppearEverBegun: Bool {
        viewState.presentationStatus.rawValue >= CVPresentationStatus.firstViewWillAppearHasBegun.rawValue
    }

    var hasViewDidAppearEverBegun: Bool {
        viewState.presentationStatus.rawValue >= CVPresentationStatus.firstViewDidAppearHasBegun.rawValue
    }

    var hasViewDidAppearEverCompleted: Bool {
        viewState.presentationStatus.rawValue >= CVPresentationStatus.firstViewDidAppearHasCompleted.rawValue
    }

    var viewHasEverAppeared: Bool {
        hasViewDidAppearEverCompleted
    }
}
