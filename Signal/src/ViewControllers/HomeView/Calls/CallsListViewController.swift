//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalMessaging
import SignalRingRTC

// MARK: - CallCellDelegate

private protocol CallCellDelegate: AnyObject {
    func joinCall(from viewModel: CallsListViewController.CallViewModel)
    func returnToCall(from viewModel: CallsListViewController.CallViewModel)
    func showCallInfo(from viewModel: CallsListViewController.CallViewModel)
}

// MARK: - CallsListViewController

class CallsListViewController: OWSViewController, HomeTabViewController, CallServiceObserver {
    private typealias DiffableDataSource = UITableViewDiffableDataSource<Section, CallViewModel.ID>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, CallViewModel.ID>

    private enum Constants {
        /// The maximum number of search results to match.
        static let maxSearchResults: UInt = 100

        /// An interval to wait after the search term changes before actually
        /// issuing a search.
        static let searchDebounceInterval: TimeInterval = 0.1
    }

    // MARK: - Dependencies

    private struct Dependencies {
        let badgeManager: BadgeManager
        let callRecordDeleteManager: CallRecordDeleteManager
        let callRecordDeleteAllJobQueue: CallRecordDeleteAllJobQueue
        let callRecordMissedCallManager: CallRecordMissedCallManager
        let callRecordQuerier: CallRecordQuerier
        let callRecordStore: CallRecordStore
        let callService: CallService
        let contactsManager: any ContactManager
        let db: SDSDatabaseStorage
        let fullTextSearchFinder: FullTextSearchFinder.Type
        let interactionStore: InteractionStore
        let threadStore: ThreadStore
    }

    private lazy var deps: Dependencies = Dependencies(
        badgeManager: AppEnvironment.shared.badgeManager,
        callRecordDeleteManager: DependenciesBridge.shared.callRecordDeleteManager,
        callRecordDeleteAllJobQueue: SSKEnvironment.shared.callRecordDeleteAllJobQueueRef,
        callRecordMissedCallManager: DependenciesBridge.shared.callRecordMissedCallManager,
        callRecordQuerier: DependenciesBridge.shared.callRecordQuerier,
        callRecordStore: DependenciesBridge.shared.callRecordStore,
        callService: NSObject.callService,
        contactsManager: NSObject.contactsManager,
        db: NSObject.databaseStorage,
        fullTextSearchFinder: FullTextSearchFinder.self,
        interactionStore: DependenciesBridge.shared.interactionStore,
        threadStore: DependenciesBridge.shared.threadStore
    )

    // MARK: - Lifecycle

    private var logger: PrefixedLogger = PrefixedLogger(prefix: "[CallsListVC]")

    private lazy var emptyStateMessageView: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()

    private lazy var noSearchResultsView: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .dynamicTypeBody
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.titleView = filterPicker
        updateBarButtonItems()

        let searchController = UISearchController(searchResultsController: nil)
        navigationItem.searchController = searchController
        searchController.searchResultsUpdater = self

        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()
        tableView.delegate = self
        tableView.allowsSelectionDuringEditing = true
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.separatorStyle = .none
        tableView.contentInset = .zero
        tableView.register(CallCell.self, forCellReuseIdentifier: Self.callCellReuseIdentifier)
        tableView.dataSource = dataSource

        // [CallsTab] TODO: Remove when releasing
        let internalReminder = ReminderView(
            style: .warning,
            text: "The calls tab is internal-only. Some features are not yet implemented."
        )
        // tableHeaderView doesn't like autolayout. I'm sure I could get it to
        // work but it's internal anyway so I'm not gonna bother.
        internalReminder.frame.height = 100
        tableView.tableHeaderView = internalReminder

        view.addSubview(emptyStateMessageView)
        emptyStateMessageView.autoCenterInSuperview()

        view.addSubview(noSearchResultsView)
        noSearchResultsView.autoPinWidthToSuperviewMargins()
        noSearchResultsView.autoPinEdge(toSuperviewMargin: .top, withInset: 80)

        applyTheme()
        attachSelfAsObservers()

        loadCallRecordsAnew(animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        updateDisplayedDateForAllCallCells()
        clearMissedCallsIfNecessary()
    }

    override func themeDidChange() {
        super.themeDidChange()
        applyTheme()
        reloadAllRows()
    }

    private func updateBarButtonItems() {
        if tableView.isEditing {
            navigationItem.leftBarButtonItem = cancelMultiselectButton()
            navigationItem.rightBarButtonItem = deleteAllCallsButton()
        } else {
            navigationItem.leftBarButtonItem = profileBarButtonItem()
            navigationItem.rightBarButtonItem = newCallButton()
        }
    }

    private func applyTheme() {
        view.backgroundColor = Theme.backdropColor
        tableView.backgroundColor = Theme.backgroundColor
    }

    // MARK: Profile button

    private func profileBarButtonItem() -> UIBarButtonItem {
        createSettingsBarButtonItem(
            databaseStorage: databaseStorage,
            actions: { settingsAction in
                [
                    .init(
                        title: Strings.selectCallsButtonTitle,
                        image: Theme.iconImage(.contextMenuSelect),
                        attributes: []
                    ) { [weak self] _ in
                        self?.startMultiselect()
                    },
                    settingsAction,
                ]
            },
            showAppSettings: { [weak self] in
                self?.showAppSettings()
            }
        )
    }

    private func showAppSettings() {
        AssertIsOnMainThread()

        conversationSplitViewController?.selectedConversationViewController?.dismissMessageContextMenu(animated: true)
        presentFormSheet(AppSettingsViewController.inModalNavigationController(), animated: true)
    }

    private func startMultiselect() {
        Logger.debug("Select calls")
        // Swipe actions count as edit mode, so cancel those
        // before entering multiselection editing mode.
        tableView.setEditing(false, animated: true)
        tableView.setEditing(true, animated: true)
        updateBarButtonItems()
        showToolbar()
    }

    private var multiselectToolbarContainer: BlurredToolbarContainer?
    private var multiselectToolbar: UIToolbar? {
        multiselectToolbarContainer?.toolbar
    }

    private func showToolbar() {
        guard let tabController = tabBarController as? HomeTabBarController else { return }

        let toolbarContainer = BlurredToolbarContainer()
        toolbarContainer.alpha = 0
        view.addSubview(toolbarContainer)
        toolbarContainer.autoPinWidthToSuperview()
        toolbarContainer.autoPinEdge(toSuperviewEdge: .bottom)
        self.multiselectToolbarContainer = toolbarContainer

        let bottomInset = tabController.tabBar.height - tabController.tabBar.safeAreaInsets.bottom
        self.tableView.contentInset.bottom = bottomInset
        self.tableView.verticalScrollIndicatorInsets.bottom = bottomInset

        tabController.setTabBarHidden(true, animated: true, duration: 0.1) { _ in
            // See ChatListViewController.showToolbar for why this is async
            DispatchQueue.main.async {
                self.updateMultiselectToolbarButtons()
            }
            UIView.animate(withDuration: 0.25) {
                toolbarContainer.alpha = 1
            }
        }
    }

    private func updateMultiselectToolbarButtons() {
        guard let multiselectToolbar else { return }

        let selectedRows = tableView.indexPathsForSelectedRows ?? []
        let hasSelectedEntries = !selectedRows.isEmpty

        let deleteButton = UIBarButtonItem(
            title: CommonStrings.deleteButton,
            style: .plain,
            target: self,
            action: #selector(deleteSelectedCalls)
        )
        deleteButton.isEnabled = hasSelectedEntries

        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        multiselectToolbar.setItems(
            [spacer, deleteButton],
            animated: false
        )
    }

    @objc
    private func deleteSelectedCalls() {
        guard let selectedRows = tableView.indexPathsForSelectedRows else {
            return
        }

        let selectedViewModelIds: [CallViewModel.ID] = selectedRows.compactMap { idxPath in
            return calls.allLoadedViewModelIds[safe: idxPath.row]
        }
        owsAssertBeta(selectedRows.count == selectedViewModelIds.count)

        deleteCalls(viewModelIds: selectedViewModelIds)
    }

    // MARK: New call button

    private func newCallButton() -> UIBarButtonItem {
        let barButtonItem = UIBarButtonItem(
            image: Theme.iconImage(.buttonNewCall),
            style: .plain,
            target: self,
            action: #selector(newCall)
        )
        barButtonItem.accessibilityLabel = OWSLocalizedString(
            "NEW_CALL_LABEL",
            comment: "Accessibility label for the new call button on the Calls Tab"
        )
        barButtonItem.accessibilityHint = OWSLocalizedString(
            "NEW_CALL_HINT",
            comment: "Accessibility hint describing the action of the new call button on the Calls Tab"
        )
        return barButtonItem
    }

    @objc
    private func newCall() {
        let viewController = NewCallViewController()
        viewController.delegate = self
        let modal = OWSNavigationController(rootViewController: viewController)
        self.navigationController?.presentFormSheet(modal, animated: true)
    }

    // MARK: Cancel multiselect button

    private func cancelMultiselectButton() -> UIBarButtonItem {
        let barButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelMultiselect),
            accessibilityIdentifier: CommonStrings.cancelButton
        )
        return barButtonItem
    }

    @objc
    private func cancelMultiselect() {
        tableView.setEditing(false, animated: true)
        updateBarButtonItems()
        hideToolbar()
    }

    private func hideToolbar() {
        guard let multiselectToolbarContainer else { return }
        UIView.animate(withDuration: 0.25) {
            multiselectToolbarContainer.alpha = 0
        } completion: { _ in
            multiselectToolbarContainer.removeFromSuperview()
            guard let tabController = self.tabBarController as? HomeTabBarController else { return }
            tabController.setTabBarHidden(false, animated: true, duration: 0.1) { _ in
                self.tableView.contentInset.bottom = 0
                self.tableView.verticalScrollIndicatorInsets.bottom = 0
            }
        }
    }

    // MARK: Delete All button

    private func deleteAllCallsButton() -> UIBarButtonItem {
        return UIBarButtonItem(
            title: Strings.deleteAllCallsButtonTitle,
            style: .plain,
            target: self,
            action: #selector(promptAboutDeletingAllCalls)
        )
    }

    @objc
    private func promptAboutDeletingAllCalls() {
        OWSActionSheets.showConfirmationAlert(
            title: Strings.deleteAllCallsPromptTitle,
            message: Strings.deleteAllCallsPromptMessage,
            proceedTitle: Strings.deleteAllCallsButtonTitle,
            proceedStyle: .destructive
        ) { _ in
            self.deps.db.asyncWrite { tx in
                /// This will ultimately post "call records deleted"
                /// notifications that this view is listening to, so we don't
                /// need to do any manual UI updates.
                self.deps.callRecordDeleteAllJobQueue.addJob(
                    sendDeleteAllSyncMessage: true,
                    deleteAllBeforeTimestamp: Date().ows_millisecondsSince1970,
                    tx: tx
                )
            }
        }
    }

    // MARK: Tab picker

    private enum FilterMode: Int {
        case all = 0
        case missed = 1
    }

    private lazy var filterPicker: UISegmentedControl = {
        let segmentedControl = UISegmentedControl(items: [
            Strings.filterPickerOptionAll,
            Strings.filterPickerOptionMissed
        ])
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        return segmentedControl
    }()

    @objc
    private func tabChanged() {
        loadCallRecordsAnew(animated: true)
        updateMultiselectToolbarButtons()
    }

    private var currentFilterMode: FilterMode {
        FilterMode(rawValue: filterPicker.selectedSegmentIndex) ?? .all
    }

    // MARK: - Observers and Notifications

    private func attachSelfAsObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(significantTimeChangeOccurred),
            name: UIApplication.significantTimeChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(groupCallInteractionWasUpdated),
            name: GroupCallInteractionUpdatedNotification.name,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(receivedCallRecordStoreNotification),
            name: CallRecordStoreNotification.name,
            object: nil
        )

        // No need to sync state since we're still setting up the view.
        deps.callService.addObserver(
            observer: self,
            syncStateImmediately: false
        )
    }

    /// A significant time change has occurred, according to the system. We
    /// should update the displayed date for all visible calls.
    @objc
    private func significantTimeChangeOccurred() {
        updateDisplayedDateForAllCallCells()
    }

    private func updateDisplayedDateForAllCallCells() {
        for callCell in tableView.visibleCells.compactMap({ $0 as? CallCell }) {
            callCell.updateDisplayedDateAndScheduleRefresh()
        }
    }

    /// When a group call interaction changes, we'll reload the row for the call
    /// it represents (if that row is loaded) so as to reflect the latest state
    /// for that group call.
    ///
    /// Recall that we track "is a group call ongoing" as a property on the
    /// interaction representing that group call, so we need this so we reload
    /// when the call ends.
    ///
    /// Note also that the ``didUpdateCall(from:to:)`` hook below is hit during
    /// the group-call-join process but before we have actually joined the call,
    /// due to the asynchronous nature of group calls. Consequently, we also
    /// need this hook to reload when we ourselves have joined the call, as us
    /// joining updates the "joined members" property also tracked on the group
    /// call interaction.
    @objc
    private func groupCallInteractionWasUpdated(_ notification: NSNotification) {
        guard let notification = GroupCallInteractionUpdatedNotification(notification) else {
            owsFail("Unexpectedly failed to instantiate group call interaction updated notification!")
        }

        let viewModelIdForGroupCall = CallViewModel.ID(
            callId: notification.callId,
            threadRowId: notification.groupThreadRowId
        )

        reloadRows(forIdentifiers: [viewModelIdForGroupCall])
    }

    @objc
    private func receivedCallRecordStoreNotification(_ notification: NSNotification) {
        guard let callRecordStoreNotification = CallRecordStoreNotification(notification) else {
            owsFail("Unexpected notification! \(type(of: notification))")
        }

        switch callRecordStoreNotification.updateType {
        case .inserted:
            newCallRecordWasInserted()
        case .deleted(let callRecordIds):
            existingCallRecordsWereDeleted(
                recordIds: callRecordIds
            )
        case .statusUpdated(let record):
            callRecordStatusWasUpdated(
                callId: record.callId,
                threadRowId: record.threadRowId
            )
        }
    }

    /// When a call record is inserted, we'll try loading newer records.
    ///
    /// The 99% case for a call record being inserted is that a new call was
    /// started – which is to say, the inserted call record is the most recent
    /// call. For this case, by loading newer calls we'll load that new call and
    /// present it at the top.
    ///
    /// It is possible that we'll have a call inserted into the middle of our
    /// existing calls, for example if we receive a delayed sync message about a
    /// call from a while ago that we somehow never learned about on this
    /// device. If that happens, we won't load and live-update with that call –
    /// instead, we'll see it the next time this view is reloaded.
    private func newCallRecordWasInserted() {
        /// Only attempt to load newer calls if the top row is visible. If not,
        /// we'll load newer calls when the user scrolls up anyway.
        let shouldLoadNewerCalls: Bool = {
            guard
                let visibleIndexPaths = tableView.indexPathsForVisibleRows,
                !visibleIndexPaths.isEmpty
            else {
                return true
            }

            return visibleIndexPaths.contains(.indexPathForPrimarySection(row: 0))
        }()

        if shouldLoadNewerCalls {
            loadMoreCalls(direction: .newer, animated: true)
        }
    }

    private func existingCallRecordsWereDeleted(
        recordIds: [CallRecordStoreNotification.CallRecordIdentifier]
    ) {
        let deletedViewModelIds: [CallViewModel.ID] = recordIds.map { recordId in
            CallViewModel.ID(
                callId: recordId.callId,
                threadRowId: recordId.threadRowId
            )
        }

        calls.dropViewModels(ids: deletedViewModelIds)
        updateSnapshot(animated: true)
    }

    /// When the status of a call record changes, we'll reload the row it
    /// represents (if that row is loaded) so as to reflect the latest state for
    /// that record.
    ///
    /// For example, imagine a ringing call that is declined on this device and
    /// accepted on another device. The other device will tell us it accepted
    /// via a sync message, and we should update this view to reflect the
    /// accepted call.
    private func callRecordStatusWasUpdated(
        callId: UInt64,
        threadRowId: Int64
    ) {
        let viewModelIdForUpdatedRecord = CallViewModel.ID(
            callId: callId,
            threadRowId: threadRowId
        )

        reloadRows(forIdentifiers: [viewModelIdForUpdatedRecord])
    }

    // MARK: CallServiceObserver

    /// When we learn that this device has joined or left a call, we'll reload
    /// any rows related to that call so that we show the latest state in this
    /// view.
    ///
    /// Recall that any 1:1 call we are not actively joined to has ended, and
    /// that that is not the case for group calls.
    func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        let callViewModelIdsToReload = [oldValue, newValue].compactMap { call -> CallViewModel.ID? in
            return call?.callViewModelId
        }

        reloadRows(forIdentifiers: callViewModelIdsToReload)
    }

    // MARK: - Clear missed calls

    /// A serial queue for clearing the missed-call badge.
    private let clearMissedCallQueue = DispatchQueue(label: "org.signal.calls-list-clear-missed")

    /// Asynchronously clears any missed-call badges, avoiding write
    /// transactions if possible.
    ///
    /// - Important
    /// The asynchronous work enqueued by this method is executed serially, such
    /// that multiple calls to this method will not race.
    private func clearMissedCallsIfNecessary() {
        clearMissedCallQueue.async {
            let unreadMissedCallCount = self.deps.db.read { tx in
                self.deps.callRecordMissedCallManager.countUnreadMissedCalls(
                    tx: tx.asV2Read
                )
            }

            /// We expect that the only unread calls to mark as read will be
            /// missed calls, so if there's no unread missed calls no need to
            /// open a write transaction.
            guard unreadMissedCallCount > 0 else { return }

            self.deps.db.write { tx in
                self.deps.callRecordMissedCallManager.markUnreadCallsAsRead(
                    tx: tx.asV2Write
                )

                tx.addAsyncCompletionOnMain {
                    self.deps.badgeManager.invalidateBadgeValue()
                }
            }
        }
    }

    // MARK: - Call loading

    private var _calls: LoadedCalls!
    private var calls: LoadedCalls! {
        get {
            AssertIsOnMainThread()
            return _calls
        }
        set(newValue) {
            AssertIsOnMainThread()
            _calls = newValue
        }
    }

    /// Used to avoid concurrent calls to ``loadCallRecordsAnew(animated:)``
    /// from clobbering each other.
    private let loadCallRecordsAnewToken = AtomicUuid(lock: AtomicLock())

    /// Asynchronously resets our current ``LoadedCalls`` for the current UI
    /// state, then kicks off an initial page load.
    ///
    /// - Note
    /// This method will perform an FTS search for our current search term, if
    /// we have one. That operation can be painfully slow for users with a large
    /// FTS index, so we need to do it asynchronously.
    private func loadCallRecordsAnew(animated: Bool) {
        let searchTerm = self.searchTerm
        let onlyLoadMissedCalls: Bool = {
            switch self.currentFilterMode {
            case .all: return false
            case .missed: return true
            }
        }()

        let loadIdentifier = loadCallRecordsAnewToken.rotate()

        deps.db.asyncRead(
            block: { tx -> CallRecordLoader.Configuration in
                if let searchTerm {
                    let threadRowIdsMatchingSearchTerm: [Int64] = self.deps.fullTextSearchFinder
                        .findThreadsMatching(
                            searchTerm: searchTerm,
                            maxSearchResults: Constants.maxSearchResults,
                            tx: tx
                        )
                        .map { thread in
                            guard let sqliteRowId = thread.sqliteRowId else {
                                owsFail("How did we match a thread in the FTS index that hasn't been inserted?")
                            }

                            return sqliteRowId
                        }

                    return CallRecordLoader.Configuration(
                        onlyLoadMissedCalls: onlyLoadMissedCalls,
                        onlyMatchThreadRowIds: threadRowIdsMatchingSearchTerm
                    )
                } else {
                    return CallRecordLoader.Configuration(
                        onlyLoadMissedCalls: onlyLoadMissedCalls,
                        onlyMatchThreadRowIds: nil
                    )
                }
            },
            completionQueue: .main,
            completion: { configuration in
                guard self.loadCallRecordsAnewToken.get() == loadIdentifier else {
                    /// While we were building the configuration, another caller
                    /// entered this method. Bail out in preference of the later
                    /// caller!
                    return
                }

                // Build a loader for this view's current state.
                let callRecordLoader = CallRecordLoader(
                    callRecordQuerier: self.deps.callRecordQuerier,
                    configuration: configuration
                )

                // Reset our loaded calls.
                self.calls = LoadedCalls(
                    callRecordLoader: callRecordLoader,
                    createCallViewModelBlock: self.createCallViewModel
                )

                // Load the initial page of records.
                self.loadMoreCalls(direction: .older, animated: animated)
            }
        )
    }

    /// Load more calls as necessary given that a row for the given index path
    /// is soon going to be presented.
    ///
    /// - Returns
    /// The call view model for this index path. A return value of `nil`
    /// represents an unexpected error.
    private func loadMoreCallsIfNecessary(
        indexPathToBeDisplayed indexPath: IndexPath
    ) -> CallViewModel? {
        if indexPath.row == calls.allLoadedViewModelIds.count - 1 {
            /// If this index path represents the oldest loaded call, try and
            /// load another page of even-older calls.
            loadMoreCalls(direction: .older, animated: false)
        } else if !calls.hasCachedViewModel(rowIndex: indexPath.row) {
            /// If we don't have a view model ready to go for this row, load
            /// until we do.
            ///
            /// This is probably because we're scrolling through so many calls
            /// we can't keep them all cached and we've evicted the view model
            /// for this row, but we've scrolled back to it and need to re-load
            /// the view model.
            ///
            /// Note that the table may request view models for totally disjoint
            /// rows. For example, imagine we're scrolled down a couple hundred
            /// calls and the user triggers the "scroll-to-top" gesture. The
            /// table is gonna scroll super-fast to the top and request models
            /// for rows right at the top, which have long been paged out. Along
            /// the way, it may request view models for sporadic rows as it
            /// passes over them.
            ///
            /// All of that to say: we need support for "page in view models for
            /// an arbitrary index path", which is what this does.
            deps.db.read { tx in
                calls.loadUntilCached(rowIndex: indexPath.row, tx: tx)
            }
        }

        return calls.getCachedViewModel(rowIndex: indexPath.row)
    }

    /// Synchronously loads more calls, then asynchronously update the snapshot
    /// if necessary.
    private func loadMoreCalls(
        direction loadDirection: LoadedCalls.LoadDirection,
        animated: Bool
    ) {
        let shouldUpdateSnapshot = deps.db.read { tx in
            return calls.loadMore(direction: loadDirection, tx: tx)
        }

        guard shouldUpdateSnapshot else { return }

        DispatchQueue.main.async {
            self.updateSnapshot(animated: animated)
        }
    }

    /// Converts a ``CallRecord`` to a ``CallViewModel``.
    ///
    /// - Note
    /// This method involves calls to external dependencies, as the view model
    /// state relies on state elsewhere in the app (such as any
    /// currently-ongoing calls).
    private func createCallViewModel(
        callRecord: CallRecord,
        tx: SDSAnyReadTransaction
    ) -> CallViewModel {
        guard let callThread = deps.threadStore.fetchThread(
            rowId: callRecord.threadRowId,
            tx: tx.asV2Read
        ) else {
            owsFail("Missing thread for call record! This should be impossible, per the DB schema.")
        }

        let callDirection: CallViewModel.Direction = {
            if callRecord.callStatus.isMissedCall {
                return .missed
            }

            switch callRecord.callDirection {
            case .incoming: return .incoming
            case .outgoing: return .outgoing
            }
        }()

        let callState: CallViewModel.State = {
            let currentCallId: UInt64? = deps.callService.currentCall?.callId

            switch callRecord.callStatus {
            case .individual:
                if callRecord.callId == currentCallId {
                    // We can have at most one 1:1 call active at a time, and if
                    // we have an active 1:1 call we must be in it. All other
                    // 1:1 calls must have ended.
                    return .participating
                }
            case .group:
                guard let groupCallInteraction: OWSGroupCallMessage = deps.interactionStore
                    .fetchAssociatedInteraction(
                        callRecord: callRecord, tx: tx.asV2Read
                    )
                else {
                    owsFail("Missing interaction for group call. This should be impossible per the DB schema!")
                }

                // We learn that a group call ended by peeking the group. During
                // that peek, we update the group call interaction. It's a
                // leetle wonky that we use the interaction to store that info,
                // but such is life.
                if !groupCallInteraction.hasEnded {
                    if callRecord.callId == currentCallId {
                        return .participating
                    }

                    return .active
                }
            }

            return .ended
        }()

        if let contactThread = callThread as? TSContactThread {
            let callType: CallViewModel.RecipientType.CallType = {
                switch callRecord.callType {
                case .audioCall:
                    return .audio
                case .groupCall:
                    owsFailDebug("Had group call type for 1:1 call!")
                    fallthrough
                case .videoCall:
                    return .video
                }
            }()

            return CallViewModel(
                backingCallRecord: callRecord,
                title: deps.contactsManager.displayName(
                    for: contactThread.contactAddress,
                    transaction: tx
                ),
                recipientType: .individual(type: callType, contactThread: contactThread),
                direction: callDirection,
                state: callState
            )
        } else if let groupThread = callThread as? TSGroupThread {
            return CallViewModel(
                backingCallRecord: callRecord,
                title: groupThread.groupModel.groupNameOrDefault,
                recipientType: .group(groupThread: groupThread),
                direction: callDirection,
                state: callState
            )
        } else {
            owsFail("Call thread was neither contact nor group! This should be impossible.")
        }
    }

    // MARK: - Search term

    /// - Important
    /// Don't use this directly – use ``searchTerm``.
    private var _searchTerm: String? {
        didSet {
            guard oldValue != searchTerm else {
                // If the term hasn't changed, don't do anything.
                return
            }

            searchTermDidChange()
        }
    }

    /// The user's current search term. Coalesces empty strings into `nil`.
    private var searchTerm: String? {
        get { _searchTerm?.nilIfEmpty }
        set { _searchTerm = newValue?.nilIfEmpty }
    }

    private func searchTermDidChange() {
        let searchTermSnapshot = searchTerm

        DispatchQueue.global().asyncAfter(deadline: .now() + Constants.searchDebounceInterval) {
            guard self.searchTerm == searchTermSnapshot else {
                /// The search term changed in the debounce period, so we'll
                /// bail out here in preference for the later-changed search
                /// term.
                return
            }

            self.loadCallRecordsAnew(animated: true)
        }
    }

    // MARK: - Table view

    fileprivate enum Section: Int, Hashable {
        case primary = 0
    }

    fileprivate struct CallViewModel: Hashable, Identifiable {
        enum Direction: Hashable {
            case outgoing
            case incoming
            case missed

            var label: String {
                switch self {
                case .outgoing:
                    return Strings.callDirectionLabelOutgoing
                case .incoming:
                    return Strings.callDirectionLabelIncoming
                case .missed:
                    return Strings.callDirectionLabelMissed
                }
            }
        }

        enum State: Hashable {
            /// This call is active, but the user is not in it.
            case active
            /// The user is currently in this call.
            case participating
            /// The call is no longer active.
            case ended
        }

        enum RecipientType: Hashable {
            case individual(type: CallType, contactThread: TSContactThread)
            case group(groupThread: TSGroupThread)

            enum CallType: Hashable {
                case audio
                case video
            }
        }

        let backingCallRecord: CallRecord

        let title: String
        let recipientType: RecipientType
        let direction: Direction
        let state: State

        var callId: UInt64 { backingCallRecord.callId }
        var threadRowId: Int64 { backingCallRecord.threadRowId }
        var callBeganTimestamp: UInt64 { backingCallRecord.callBeganTimestamp }
        var callBeganDate: Date { Date(millisecondsSince1970: callBeganTimestamp) }

        init(
            backingCallRecord: CallRecord,
            title: String,
            recipientType: RecipientType,
            direction: Direction,
            state: State
        ) {
            self.backingCallRecord = backingCallRecord
            self.title = title
            self.recipientType = recipientType
            self.direction = direction
            self.state = state
        }

        var callType: RecipientType.CallType {
            switch recipientType {
            case let .individual(callType, _):
                return callType
            case .group(_):
                return .video
            }
        }

        /// The `TSThread` for the call. If a `TSContactThread` or
        /// `TSGroupThread` is needed, switch on `recipientType`
        /// instead of typecasting this property.
        var thread: TSThread {
            switch recipientType {
            case let .individual(_, contactThread):
                return contactThread
            case let .group(groupThread):
                return groupThread
            }
        }

        var isMissed: Bool {
            switch direction {
            case .outgoing, .incoming:
                return false
            case .missed:
                return true
            }
        }

        // MARK: Hashable: Equatable

        static func == (lhs: CallViewModel, rhs: CallViewModel) -> Bool {
            return lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            id.hash(into: &hasher)
        }

        // MARK: Identifiable

        struct ID: Hashable {
            let callId: UInt64
            let threadRowId: Int64
        }

        var id: ID {
            ID(callId: callId, threadRowId: threadRowId)
        }
    }

    let tableView = UITableView(frame: .zero, style: .plain)

    private static var callCellReuseIdentifier = "callCell"

    private lazy var dataSource = UITableViewDiffableDataSource<Section, CallViewModel.ID>(
        tableView: tableView
    ) { [weak self] tableView, indexPath, modelID -> UITableViewCell? in
        guard
            let self,
            let callCell = tableView.dequeueReusableCell(
                withIdentifier: Self.callCellReuseIdentifier
            ) as? CallCell
        else { return UITableViewCell() }

        /// This load should be sufficiently fast that doing it here
        /// synchronously is fine.
        if let viewModelForIndexPath = self.loadMoreCallsIfNecessary(
            indexPathToBeDisplayed: indexPath
        ) {
            callCell.delegate = self
            callCell.viewModel = viewModelForIndexPath

            return callCell
        } else {
            owsFailBeta("Missing cached view model – how did this happen?")

            /// Return an empty table cell, rather than a ``CallCell`` that's
            /// gonna be incorrectly configured.
            return UITableViewCell()
        }
    }

    private func getSnapshot() -> Snapshot {
        var snapshot = Snapshot()
        snapshot.appendSections([.primary])
        snapshot.appendItems(calls.allLoadedViewModelIds)
        return snapshot
    }

    private func updateSnapshot(animated: Bool) {
        dataSource.apply(getSnapshot(), animatingDifferences: animated)
        updateEmptyStateMessage()
        cancelMultiselectIfEmpty()
    }

    /// Reload the rows for the given view model IDs that are currently loaded.
    private func reloadRows(forIdentifiers identifiersToReload: [CallViewModel.ID]) {
        // Recreate the view models, so when the data source reloads the rows
        // it'll reflect the new underlying state for that row.
        //
        // This step will also drop any IDs for models that are not currently
        // loaded, which should not be included in the snapshot.
        let identifiersToReload = deps.db.read { tx -> [CallViewModel.ID] in
            return calls.recreateViewModels(
                ids: identifiersToReload, tx: tx
            ) { viewModelId -> CallRecord? in
                switch deps.callRecordStore.fetch(
                    viewModelId: viewModelId, tx: tx
                ) {
                case .matchFound(let freshCallRecord):
                    return freshCallRecord
                case .matchNotFound, .matchDeleted:
                    return nil
                }
            }
        }

        var snapshot = getSnapshot()
        snapshot.reloadItems(identifiersToReload)
        dataSource.apply(snapshot)
    }

    private func reloadAllRows() {
        var snapshot = getSnapshot()
        snapshot.reloadSections([.primary])
        dataSource.apply(snapshot)
    }

    private func cancelMultiselectIfEmpty() {
        if
            tableView.isEditing,
            calls.allLoadedViewModelIds.isEmpty
        {
            cancelMultiselect()
        }
    }

    private func updateEmptyStateMessage() {
        switch (calls.allLoadedViewModelIds.count, searchTerm) {
        case (0, .some(let searchTerm)) where !searchTerm.isEmpty:
            noSearchResultsView.text = String(
                format: Strings.searchNoResultsFoundLabelFormat,
                arguments: [searchTerm]
            )
            noSearchResultsView.layer.opacity = 1
            emptyStateMessageView.layer.opacity = 0
        case (0, _):
            emptyStateMessageView.attributedText = NSAttributedString.composed(of: {
                switch currentFilterMode {
                case .all:
                    return [
                        Strings.noRecentCallsLabel,
                        "\n",
                        Strings.noRecentCallsSuggestionLabel
                            .styled(with: .font(.dynamicTypeSubheadline)),
                    ]
                case .missed:
                    return [
                        Strings.noMissedCallsLabel
                    ]
                }
            }())
            .styled(
                with: .font(.dynamicTypeSubheadline.semibold())
            )
            noSearchResultsView.layer.opacity = 0
            emptyStateMessageView.layer.opacity = 1
        case (_, _):
            // Hide empty state message
            noSearchResultsView.layer.opacity = 0
            emptyStateMessageView.layer.opacity = 0
        }
    }
}

private extension IndexPath {
    static func indexPathForPrimarySection(row: Int) -> IndexPath {
        return IndexPath(
            row: row,
            section: CallsListViewController.Section.primary.rawValue
        )
    }
}

private extension SignalCall {
    var callId: UInt64? {
        switch mode {
        case .individual(let individualCall):
            return individualCall.callId
        case .group(let groupCall):
            return groupCall.peekInfo?.eraId.map { callIdFromEra($0) }
        }
    }

    var callViewModelId: CallsListViewController.CallViewModel.ID? {
        guard let callId else { return nil }
        return .init(callId: callId, threadRowId: threadRowId)
    }

    private var threadRowId: Int64 {
        guard let threadRowId = thread.sqliteRowId else {
            owsFail("How did we get a call whose thread does not exist in the DB?")
        }

        return threadRowId
    }
}

private extension CallRecordStore {
    func fetch(
        viewModelId: CallsListViewController.CallViewModel.ID,
        tx: SDSAnyReadTransaction
    ) -> CallRecordStoreMaybeDeletedFetchResult {
        return fetch(
            callId: viewModelId.callId,
            threadRowId: viewModelId.threadRowId,
            tx: tx.asV2Read
        )
    }
}

// MARK: UITableViewDelegate

extension CallsListViewController: UITableViewDelegate {

    private func viewModel(
        forIndexPathThatShouldHaveOne indexPath: IndexPath
    ) -> CallViewModel? {
        owsAssert(
            indexPath.section == Section.primary.rawValue,
            "Unexpected section for index path: \(indexPath.section)"
        )

        guard let viewModel = calls.getCachedViewModel(rowIndex: indexPath.row) else {
            owsFailBeta("Missing view model for index path. How did this happen?")
            return nil
        }

        return viewModel
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            updateMultiselectToolbarButtons()
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)

        guard let viewModel = viewModel(forIndexPathThatShouldHaveOne: indexPath) else {
            return owsFailDebug("Missing view model")
        }
        callBack(from: viewModel)
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            updateMultiselectToolbarButtons()
        }
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        updateBarButtonItems()
        showToolbar()
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        return self.longPressActions(forRowAt: indexPath)
            .map { actions in UIMenu.init(children: actions) }
            .map { menu in
                UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { _ in menu }
            }
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let viewModel = viewModel(forIndexPathThatShouldHaveOne: indexPath) else {
            owsFailDebug("Missing call view model")
            return nil
        }

        let goToChatAction = makeContextualAction(
            style: .normal,
            color: .ows_accentBlue,
            image: "arrow-square-upright-fill",
            title: Strings.goToChatActionTitle
        ) { [weak self] in
            self?.goToChat(from: viewModel)
        }

        return .init(actions: [goToChatAction])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let viewModel = viewModel(forIndexPathThatShouldHaveOne: indexPath) else {
            owsFailDebug("Missing call view model")
            return nil
        }

        let deleteAction = makeContextualAction(
            style: .destructive,
            color: .ows_accentRed,
            image: "trash-fill",
            title: CommonStrings.deleteButton
        ) { [weak self] in
            self?.deleteCalls(viewModelIds: [viewModel.id])
        }

        return .init(actions: [deleteAction])
    }

    private func makeContextualAction(
        style: UIContextualAction.Style,
        color: UIColor,
        image: String,
        title: String,
        action: @escaping () -> Void
    ) -> UIContextualAction {
        let action = UIContextualAction(
            style: style,
            title: nil
        ) { _, _, completion in
            action()
            completion(true)
        }
        action.backgroundColor = color
        action.image = UIImage(named: image)?.withTitle(
            title,
            font: .dynamicTypeFootnote.medium(),
            color: .ows_white,
            maxTitleWidth: 68,
            minimumScaleFactor: CGFloat(8) / CGFloat(13),
            spacing: 4
        )?.withRenderingMode(.alwaysTemplate)

        return action
    }

    private func longPressActions(forRowAt indexPath: IndexPath) -> [UIAction]? {
        guard let viewModel = viewModel(forIndexPathThatShouldHaveOne: indexPath) else {
            owsFailDebug("Missing call view model")
            return nil
        }

        var actions = [UIAction]()

        switch viewModel.state {
        case .active:
            let joinCallTitle: String
            let joinCallIconName: String
            switch viewModel.callType {
            case .audio:
                joinCallTitle = Strings.joinAudioCallActionTitle
                joinCallIconName = Theme.iconName(.contextMenuVoiceCall)
            case .video:
                joinCallTitle = Strings.joinVideoCallActionTitle
                joinCallIconName = Theme.iconName(.contextMenuVideoCall)
            }
            let joinCallAction = UIAction(
                title: joinCallTitle,
                image: UIImage(named: joinCallIconName),
                attributes: []
            ) { [weak self] _ in
                self?.joinCall(from: viewModel)
            }
            actions.append(joinCallAction)
        case .participating:
            let returnToCallIconName: String
            switch viewModel.callType {
            case .audio:
                returnToCallIconName = Theme.iconName(.contextMenuVoiceCall)
            case .video:
                returnToCallIconName = Theme.iconName(.contextMenuVideoCall)
            }
            let returnToCallAction = UIAction(
                title: Strings.returnToCallActionTitle,
                image: UIImage(named: returnToCallIconName),
                attributes: []
            ) { [weak self] _ in
                self?.returnToCall(from: viewModel)
            }
            actions.append(returnToCallAction)
        case .ended:
            switch viewModel.recipientType {
            case .individual:
                let audioCallAction = UIAction(
                    title: Strings.startAudioCallActionTitle,
                    image: Theme.iconImage(.contextMenuVoiceCall),
                    attributes: []
                ) { [weak self] _ in
                    self?.startAudioCall(from: viewModel)
                }
                actions.append(audioCallAction)
            case .group:
                break
            }

            let videoCallAction = UIAction(
                title: Strings.startVideoCallActionTitle,
                image: Theme.iconImage(.contextMenuVideoCall),
                attributes: []
            ) { [weak self] _ in
                self?.startVideoCall(from: viewModel)
            }
            actions.append(videoCallAction)
        }

        let goToChatAction = UIAction(
            title: Strings.goToChatActionTitle,
            image: Theme.iconImage(.contextMenuOpenInChat),
            attributes: []
        ) { [weak self] _ in
            self?.goToChat(from: viewModel)
        }
        actions.append(goToChatAction)

        let infoAction = UIAction(
            title: Strings.viewCallInfoActionTitle,
            image: Theme.iconImage(.contextMenuInfo),
            attributes: []
        ) { [weak self] _ in
            self?.showCallInfo(from: viewModel)
        }
        actions.append(infoAction)

        let selectAction = UIAction(
            title: Strings.selectCallActionTitle,
            image: Theme.iconImage(.contextMenuSelect),
            attributes: []
        ) { [weak self] _ in
            self?.selectCall(forRowAt: indexPath)
        }
        actions.append(selectAction)

        switch viewModel.state {
        case .active, .ended:
            let deleteAction = UIAction(
                title: Strings.deleteCallActionTitle,
                image: Theme.iconImage(.contextMenuDelete),
                attributes: .destructive
            ) { [weak self] _ in
                self?.deleteCalls(viewModelIds: [viewModel.id])
            }
            actions.append(deleteAction)
        case .participating:
            break
        }

        return actions
    }
}

// MARK: - Actions

extension CallsListViewController: CallCellDelegate, NewCallViewControllerDelegate {

    private func callBack(from viewModel: CallViewModel) {
        switch viewModel.callType {
        case .audio:
            startAudioCall(from: viewModel)
        case .video:
            startVideoCall(from: viewModel)
        }
    }

    private func startAudioCall(from viewModel: CallViewModel) {
        // [CallsTab] TODO: See ConversationViewController.startIndividualCall(withVideo:)
        switch viewModel.recipientType {
        case let .individual(_, contactThread):
            callService.initiateCall(thread: contactThread, isVideo: false)
        case .group:
            owsFail("Shouldn't be able to start audio call from group")
        }
    }

    private func startVideoCall(from viewModel: CallViewModel) {
        // [CallsTab] TODO: Check if the conversation is blocked or there's a message request.
        // See ConversationViewController.startIndividualCall(withVideo:)
        // and  ConversationViewController.showGroupLobbyOrActiveCall()
        switch viewModel.recipientType {
        case let .individual(_, contactThread):
            callService.initiateCall(thread: contactThread, isVideo: true)
        case let .group(groupThread):
            GroupCallViewController.presentLobby(thread: groupThread)
        }
    }

    private func goToChat(from viewModel: CallViewModel) {
        goToChat(for: viewModel.thread)
    }

    private func deleteCalls(viewModelIds: [CallViewModel.ID]) {
        deps.db.asyncWrite { tx in
            let callRecords = viewModelIds.compactMap { viewModelId -> CallRecord? in
                switch self.deps.callRecordStore.fetch(
                    viewModelId: viewModelId,
                    tx: tx
                ) {
                case .matchFound(let callRecord):
                    return callRecord
                case .matchDeleted, .matchNotFound:
                    return nil
                }
            }

            /// Deleting these call records will trigger a ``CallRecordStoreNotification``,
            /// which we're listening for in this view and will in turn lead us
            /// to update the UI as appropriate.
            ///
            /// We also want to send a sync message since this is a delete
            /// originating from this device.
            self.deps.callRecordDeleteManager.deleteCallRecordsAndAssociatedInteractions(
                callRecords: callRecords,
                sendSyncMessageOnDelete: true,
                tx: tx.asV2Write
            )
        }
    }

    private func selectCall(forRowAt indexPath: IndexPath) {
        startMultiselect()
        tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
    }

    // MARK: CallCellDelegate

    fileprivate func joinCall(from viewModel: CallViewModel) {
        guard case let .group(groupThread: thread) = viewModel.recipientType else {
            owsFailBeta("Individual call should not be showing a join button")
            return
        }
        // TODO: Check if it's joinable
        GroupCallViewController.presentLobby(thread: thread)
    }

    fileprivate func returnToCall(from viewModel: CallViewModel) {
        guard WindowManager.shared.hasCall else { return }
        WindowManager.shared.returnToCallView()
    }

    fileprivate func showCallInfo(from viewModel: CallViewModel) {
        Logger.debug("Show call info")
    }

    // MARK: NewCallViewControllerDelegate

    func goToChat(for thread: TSThread) {
        SignalApp.shared.presentConversationForThread(thread, action: .compose, animated: false)
    }
}

// MARK: UISearchResultsUpdating

extension CallsListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        self.searchTerm = searchController.searchBar.text
    }
}

// MARK: - LoadedCalls

private extension CallsListViewController {
    struct LoadedCalls {
        typealias CreateCallViewModelBlock = (CallRecord, SDSAnyReadTransaction) -> CallViewModel

        enum LoadDirection {
            case older
            case newer
        }

        private struct LoadedViewModelIds {
            private(set) var ids: [CallViewModel.ID] = []
            private var indicesByIds: [CallViewModel.ID: Int] = [:]

            func index(id: CallViewModel.ID) -> Int? {
                return indicesByIds[id]
            }

            /// Append the new loaded IDs.
            mutating func append(ids newIds: [CallViewModel.ID]) {
                for newId in newIds {
                    indicesByIds[newId] = ids.count
                    ids.append(newId)
                }
            }

            /// Prepend new loaded IDs.
            mutating func prepend(ids newIds: [CallViewModel.ID]) {
                ids = newIds + ids
                indicesByIds = LoadedCalls.indicesByIds(ids)
            }

            /// Drop the given loaded IDs.
            mutating func drop(ids idsToDrop: Set<CallViewModel.ID>) {
                ids.removeAll { idsToDrop.contains($0) }
                indicesByIds = LoadedCalls.indicesByIds(ids)
            }
        }

        private enum Constants {
            static let pageSizeToLoad: UInt = 50
            static let maxCachedViewModelCount: Int = 150
        }

        private var callRecordLoader: CallRecordLoader
        private let createCallViewModelBlock: CreateCallViewModelBlock

        private var loadedViewModelIds: LoadedViewModelIds
        var allLoadedViewModelIds: [CallViewModel.ID] { loadedViewModelIds.ids }

        private var cachedViewModels: [CallViewModel] {
            didSet {
                cachedViewModelIndicesByIds = Self.indicesByIds(cachedViewModels.map { $0.id })
            }
        }
        private var cachedViewModelIndicesByIds: [CallViewModel.ID: Int]

        private static func indicesByIds(_ viewModelIds: [CallViewModel.ID]) -> [CallViewModel.ID: Int] {
            return Dictionary(
                viewModelIds.enumerated().map { (idx, viewModelId) -> (CallViewModel.ID, Int) in
                    return (viewModelId, idx)
                },
                uniquingKeysWith: { _, new in new }
            )
        }

        init(
            callRecordLoader: CallRecordLoader,
            createCallViewModelBlock: @escaping CreateCallViewModelBlock
        ) {
            self.callRecordLoader = callRecordLoader
            self.createCallViewModelBlock = createCallViewModelBlock

            self.loadedViewModelIds = LoadedViewModelIds()

            self.cachedViewModels = []
            self.cachedViewModelIndicesByIds = [:]
        }

        // MARK: Accessors

        func getCachedViewModel(id viewModelId: CallViewModel.ID) -> CallViewModel? {
            guard let index = cachedViewModelIndicesByIds[viewModelId] else {
                return nil
            }

            return cachedViewModels[index]
        }

        func getCachedViewModel(rowIndex: Int) -> CallViewModel? {
            guard let viewModelId = loadedViewModelIds.ids[safe: rowIndex] else {
                return nil
            }

            return getCachedViewModel(id: viewModelId)
        }

        func hasCachedViewModel(rowIndex: Int) -> Bool {
            return getCachedViewModel(rowIndex: rowIndex) != nil
        }

        // MARK: Mutators

        /// Repeatedly loads pages of view models until a cached view model is
        /// available for the given row index.
        ///
        /// This method is safe to call for any valid row index; i.e., for any
        /// index covered by ``loadedViewModelIds``.
        ///
        /// - Note
        /// This may result in multiple synchronous page loads if necessary. For
        /// example, if view models are cached for rows in range `(500, 600)`
        /// and this method is called for row 10, all the rows between row 500
        /// and row 10 will be loaded.
        ///
        /// This behavior should be fine in practice, since loading a page is an
        /// extremely fast operation.
        mutating func loadUntilCached(
            rowIndex: Int,
            tx: SDSAnyReadTransaction
        ) {
            guard
                let firstCachedViewModel = cachedViewModels.first,
                let firstCachedViewModelRowIndex = loadedViewModelIds.index(id: firstCachedViewModel.id),
                let lastCachedViewModel = cachedViewModels.last,
                let lastCachedViewModelRowIndex = loadedViewModelIds.index(id: lastCachedViewModel.id)
            else {
                owsFail("How did we attempt to load until a specific row index, without *any* cached models?")
            }

            let loadDirection: LoadDirection = {
                if rowIndex > lastCachedViewModelRowIndex {
                    return .older
                } else if rowIndex < firstCachedViewModelRowIndex {
                    return .newer
                }

                owsFail("Row index is in the cached range, but somehow we didn't have a cached model. How did that happen?")
            }()

            while true {
                if hasCachedViewModel(rowIndex: rowIndex) {
                    break
                }

                _ = loadMore(direction: loadDirection, tx: tx)
            }
        }

        /// Load a page of calls in the requested direction.
        ///
        /// - Returns
        /// Whether any new calls were loaded as part of this operation.
        mutating func loadMore(
            direction loadDirection: LoadDirection,
            tx: SDSAnyReadTransaction
        ) -> Bool {
            let loadDirection: CallRecordLoader.LoadDirection = {
                switch loadDirection {
                case .older:
                    return .older(oldestCallTimestamp: cachedViewModels.last?.callBeganTimestamp)
                case .newer:
                    guard let newestCachedViewModel = cachedViewModels.first else {
                        // A little weird, but if we have no cached calls these
                        // are equivalent anyway.
                        return .older(oldestCallTimestamp: nil)
                    }

                    return .newer(newestCallTimestamp: newestCachedViewModel.callBeganTimestamp)
                }
            }()

            let newCallRecords: [CallRecord] = callRecordLoader.loadCallRecords(
                loadDirection: loadDirection,
                pageSize: Constants.pageSizeToLoad,
                tx: tx.asV2Read
            )

            let newViewModels: [CallViewModel] = newCallRecords.map { callRecord in
                return createCallViewModelBlock(callRecord, tx)
            }

            let firstTimeLoadedViewModelIds = newViewModels
                .map { $0.id }
                .filter { loadedViewModelIds.index(id: $0) == nil }

            if !firstTimeLoadedViewModelIds.isEmpty {
                switch loadDirection {
                case .older:
                    /// This is a hot codepath; we get here every time we load a
                    /// new page of records because we scrolled to the last
                    /// loaded one.
                    loadedViewModelIds.append(ids: firstTimeLoadedViewModelIds)
                case .newer:
                    /// We should only get here if a new call was started;
                    /// otherwise, a `.newer` load should never produce a
                    /// brand-new view model.
                    loadedViewModelIds.prepend(ids: firstTimeLoadedViewModelIds)
                }
            }

            cachedViewModels = {
                let combinedViewModels: [CallViewModel] = {
                    switch loadDirection {
                    case .older: return cachedViewModels + newViewModels
                    case .newer: return newViewModels + cachedViewModels
                    }
                }()

                if combinedViewModels.count <= Constants.maxCachedViewModelCount {
                    return combinedViewModels
                } else {
                    switch loadDirection {
                    case .older:
                        return Array(combinedViewModels.suffix(Constants.maxCachedViewModelCount))
                    case .newer:
                        return Array(combinedViewModels.prefix(Constants.maxCachedViewModelCount))
                    }
                }
            }()

            return !firstTimeLoadedViewModelIds.isEmpty
        }

        mutating func dropViewModels(ids viewModelIdsToDrop: [CallViewModel.ID]) {
            let viewModelIdsToDrop = Set(viewModelIdsToDrop)

            loadedViewModelIds.drop(ids: viewModelIdsToDrop)
            cachedViewModels.removeAll { viewModelIdsToDrop.contains($0.id) }
        }

        /// Recreates the view model for the given ID by calling the given
        /// block. If a given ID is not currently loaded, it is ignored.
        ///
        /// - Returns
        /// The IDs for the view models that were recreated. Note that this will
        /// not include any IDs that were ignored.
        mutating func recreateViewModels(
            ids idsToReload: [CallViewModel.ID],
            tx: SDSAnyReadTransaction,
            fetchCallRecordBlock: (CallViewModel.ID) -> CallRecord?
        ) -> [CallViewModel.ID] {
            let indicesToReload: [(
                Int,
                CallRecord,
                CallViewModel.ID
            )] = idsToReload.compactMap { viewModelId in
                guard
                    let cachedViewModelIndex = cachedViewModelIndicesByIds[viewModelId],
                    let freshCallRecord = fetchCallRecordBlock(viewModelId)
                else { return nil }

                return (
                    cachedViewModelIndex,
                    freshCallRecord,
                    viewModelId
                )
            }

            for (index, freshCallRecord, _) in indicesToReload {
                cachedViewModels[index] = createCallViewModelBlock(freshCallRecord, tx)
            }

            return indicesToReload.map { $0.2 }
        }
    }
}

// MARK: - Call cell

private extension CallsListViewController {
    class CallCell: UITableViewCell {
        private static var verticalMargin: CGFloat = 11
        private static var horizontalMargin: CGFloat = 20
        private static var joinButtonMargin: CGFloat = 18

        weak var delegate: CallCellDelegate?

        var viewModel: CallViewModel? {
            didSet {
                updateContents()
            }
        }

        // MARK: Subviews

        private lazy var avatarView = ConversationAvatarView(
            sizeClass: .thirtySix,
            localUserDisplayMode: .asUser
        )

        private lazy var titleLabel: UILabel = {
            let label = UILabel()
            label.font = .dynamicTypeHeadline
            return label
        }()

        private lazy var subtitleLabel = UILabel()

        private lazy var timestampLabel: UILabel = {
            let label = UILabel()
            label.font = .dynamicTypeBody2
            return label
        }()

        private lazy var detailsButton: OWSButton = {
            let button = OWSButton { [weak self] in
                self?.detailsTapped()
            }
            // The info icon is the button's own image and should be `horizontalMargin` from the edge
            button.contentEdgeInsets.trailing = Self.horizontalMargin
            button.contentEdgeInsets.leading = 8
            // The join button is a separate subview and should be `joinButtonMargin` from the edge
            button.layoutMargins.trailing = Self.joinButtonMargin
            return button
        }()

        private var joinPill: UIView?

        private func makeJoinPill() -> UIView? {
            guard let viewModel else { return nil }

            let icon: UIImage
            switch viewModel.callType {
            case .audio:
                icon = Theme.iconImage(.phoneFill16)
            case .video:
                icon = Theme.iconImage(.videoFill16)
            }

            let text: String
            switch viewModel.state {
            case .active:
                text = Strings.joinCallButtonTitle
            case .participating:
                text = Strings.returnToCallButtonTitle
            case .ended:
                return nil
            }

            let button = OWSRoundedButton()
            let font = UIFont.dynamicTypeBody2.bold()
            let title = NSAttributedString.composed(of: [
                NSAttributedString.with(
                    image: icon,
                    font: .dynamicTypeCallout,
                    centerVerticallyRelativeTo: font,
                    heightReference: .pointSize
                ),
                " ",
                text,
            ]).styled(
                with: .font(font),
                .color(.ows_white)
            )
            button.setAttributedTitle(title, for: .normal)
            button.backgroundColor = .ows_accentGreen
            button.contentEdgeInsets = .init(hMargin: 12, vMargin: 4)
            button.setCompressionResistanceHigh()
            return button
        }

        // MARK: Init

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)

            let bodyVStack = UIStackView(arrangedSubviews: [
                titleLabel,
                subtitleLabel,
            ])
            bodyVStack.axis = .vertical

            let leadingHStack = UIStackView(arrangedSubviews: [
                avatarView,
                bodyVStack,
            ])
            leadingHStack.alignment = .center
            leadingHStack.axis = .horizontal
            leadingHStack.spacing = 12

            let trailingHStack = UIStackView(arrangedSubviews: [
                timestampLabel,
                detailsButton,
            ])
            trailingHStack.axis = .horizontal
            trailingHStack.spacing = 0

            let outerHStack = UIStackView(arrangedSubviews: [
                leadingHStack,
                UIView(),
                trailingHStack,
            ])
            outerHStack.axis = .horizontal
            outerHStack.spacing = 4

            // The details button should take up the entire trailing space,
            // top to bottom, so the content should have zero margins.
            contentView.preservesSuperviewLayoutMargins = false
            contentView.layoutMargins = .zero

            leadingHStack.preservesSuperviewLayoutMargins = false
            leadingHStack.isLayoutMarginsRelativeArrangement = true
            leadingHStack.layoutMargins = .init(
                top: Self.verticalMargin,
                leading: Self.horizontalMargin,
                bottom: Self.verticalMargin,
                trailing: 0
            )

            contentView.addSubview(outerHStack)
            outerHStack.autoPinEdgesToSuperviewMargins()

            tintColor = .ows_accentBlue
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            timestampDisplayRefreshTimer?.invalidate()
        }

        // MARK: Dynamically-refreshing timestamp

        /// A timer tracking the next time this cell should refresh its
        /// displayed timestamp.
        private var timestampDisplayRefreshTimer: Timer?

        /// Immediately update the display timestamp for this cell, and schedule
        /// an automatic refresh of the display timestamp as appropriate.
        func updateDisplayedDateAndScheduleRefresh() {
            AssertIsOnMainThread()

            timestampDisplayRefreshTimer?.invalidate()
            timestampDisplayRefreshTimer = nil

            guard let viewModel else { return }

            let date: Date? = {
                switch viewModel.state {
                case .active, .participating:
                    /// Don't show a date for active calls.
                    return nil
                case .ended:
                    return viewModel.callBeganDate
                }
            }()

            guard let date else {
                timestampLabel.text = nil
                return
            }

            let (formattedDate, nextRefreshDate) = DateUtil.formatDynamicDateShort(date)

            timestampLabel.text = formattedDate

            if let nextRefreshDate {
                timestampDisplayRefreshTimer = .scheduledTimer(
                    withTimeInterval: max(1, nextRefreshDate.timeIntervalSinceNow),
                    repeats: false
                ) { [weak self] _ in
                    guard let self else { return }
                    self.updateDisplayedDateAndScheduleRefresh()
                }
            }
        }

        // MARK: Updates

        private func updateContents() {
            applyTheme()

            guard let viewModel else {
                return owsFailDebug("Missing view model")
            }

            avatarView.updateWithSneakyTransactionIfNecessary { configuration in
                configuration.dataSource = .thread(viewModel.thread)
            }

            self.titleLabel.text = viewModel.title

            switch viewModel.direction {
            case .incoming, .outgoing:
                titleLabel.textColor = Theme.primaryTextColor
            case .missed:
                titleLabel.textColor = .ows_accentRed
            }

            self.subtitleLabel.attributedText = {
                let icon: ThemeIcon
                switch viewModel.callType {
                case .audio:
                    icon = .phone16
                case .video:
                    icon = .video16
                }

                return .composed(of: [
                    NSAttributedString.with(
                        image: Theme.iconImage(icon),
                        font: .dynamicTypeCallout,
                        centerVerticallyRelativeTo: .dynamicTypeBody2,
                        heightReference: .pointSize
                    ),
                    " ",
                    viewModel.direction.label,
                ]).styled(with: .font(.dynamicTypeBody2))
            }()

            self.joinPill?.removeFromSuperview()

            switch viewModel.state {
            case .active, .participating:
                // Join button
                detailsButton.setImage(imageName: nil)
                detailsButton.tintColor = .ows_white

                if let joinPill = makeJoinPill() {
                    self.joinPill = joinPill
                    detailsButton.addSubview(joinPill)
                    joinPill.autoVCenterInSuperview()
                    joinPill.autoPinWidthToSuperviewMargins()
                }
            case .ended:
                // Info button
                detailsButton.setImage(imageName: "info")
                detailsButton.tintColor = Theme.primaryIconColor
            }

            updateDisplayedDateAndScheduleRefresh()
        }

        private func applyTheme() {
            backgroundColor = Theme.backgroundColor
            selectedBackgroundView?.backgroundColor = Theme.tableCell2SelectedBackgroundColor
            multipleSelectionBackgroundView?.backgroundColor = Theme.tableCell2MultiSelectedBackgroundColor

            titleLabel.textColor = Theme.primaryTextColor
            subtitleLabel.textColor = Theme.snippetColor
            timestampLabel.textColor = Theme.snippetColor
        }

        // MARK: Actions

        private func detailsTapped() {
            guard let viewModel else {
                return owsFailDebug("Missing view model")
            }

            guard let delegate else {
                return owsFailDebug("Missing delegate")
            }

            switch viewModel.state {
            case .active:
                delegate.joinCall(from: viewModel)
            case .participating:
                delegate.returnToCall(from: viewModel)
            case .ended:
                delegate.showCallInfo(from: viewModel)
            }
        }
    }
}

// MARK: - FullTextSearchFinder

private extension FullTextSearchFinder {
    static func findThreadsMatching(
        searchTerm: String,
        maxSearchResults: UInt,
        tx: SDSAnyReadTransaction
    ) -> [TSThread] {
        var threads = [TSThread]()

        FullTextSearchFinder.enumerateObjects(
            searchText: searchTerm,
            maxResults: maxSearchResults,
            transaction: tx
        ) { (thread: TSThread, _, _) in
            threads.append(thread)
        }

        return threads
    }
}
