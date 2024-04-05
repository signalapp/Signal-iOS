//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalServiceKit
import SignalRingRTC

// MARK: - CallCellDelegate

private protocol CallCellDelegate: AnyObject {
    func joinCall(from viewModel: CallsListViewController.CallViewModel)
    func returnToCall(from viewModel: CallsListViewController.CallViewModel)
    func showCallInfo(from viewModel: CallsListViewController.CallViewModel)
}

// MARK: - CallsListViewController

class CallsListViewController: OWSViewController, HomeTabViewController, CallServiceObserver {
    private typealias DiffableDataSource = UITableViewDiffableDataSource<Section, CallViewModel.Reference>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, CallViewModel.Reference>

    private enum Constants {
        /// The maximum number of search results to match.
        static let maxSearchResults: Int = 100

        /// An interval to wait after the search term changes before actually
        /// issuing a search.
        static let searchDebounceInterval: TimeInterval = 0.1
    }

    // MARK: - Dependencies

    private struct Dependencies {
        let badgeManager: BadgeManager
        let blockingManager: BlockingManager
        let callRecordDeleteManager: CallRecordDeleteManager
        let callRecordDeleteAllJobQueue: CallRecordDeleteAllJobQueue
        let callRecordMissedCallManager: CallRecordMissedCallManager
        let callRecordQuerier: CallRecordQuerier
        let callRecordStore: CallRecordStore
        let callService: CallService
        let contactsManager: any ContactManager
        let db: SDSDatabaseStorage
        let interactionStore: InteractionStore
        let searchableNameFinder: SearchableNameFinder
        let threadStore: ThreadStore
    }

    private lazy var deps: Dependencies = Dependencies(
        badgeManager: AppEnvironment.shared.badgeManager,
        blockingManager: SSKEnvironment.shared.blockingManagerRef,
        callRecordDeleteManager: DependenciesBridge.shared.callRecordDeleteManager,
        callRecordDeleteAllJobQueue: SSKEnvironment.shared.callRecordDeleteAllJobQueueRef,
        callRecordMissedCallManager: DependenciesBridge.shared.callRecordMissedCallManager,
        callRecordQuerier: DependenciesBridge.shared.callRecordQuerier,
        callRecordStore: DependenciesBridge.shared.callRecordStore,
        callService: NSObject.callService,
        contactsManager: NSObject.contactsManager,
        db: NSObject.databaseStorage,
        interactionStore: DependenciesBridge.shared.interactionStore,
        searchableNameFinder: SearchableNameFinder(
            contactManager: NSObject.contactsManager,
            searchableNameIndexer: DependenciesBridge.shared.searchableNameIndexer,
            phoneNumberVisibilityFetcher: DependenciesBridge.shared.phoneNumberVisibilityFetcher,
            recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable
        ),
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

        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()
        tableView.delegate = self
        tableView.allowsSelectionDuringEditing = true
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.separatorStyle = .none
        tableView.contentInset = .zero
        tableView.register(CallCell.self, forCellReuseIdentifier: Self.callCellReuseIdentifier)
        tableView.dataSource = dataSource

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

    private lazy var toolbarDeleteButton = UIBarButtonItem(
        title: CommonStrings.deleteButton,
        style: .plain,
        target: self,
        action: #selector(deleteSelectedCalls)
    )

    private func showToolbar() {
        guard
            // Don't create a new toolbar if we already have one
            multiselectToolbarContainer == nil,
            let tabController = tabBarController as? HomeTabBarController
        else { return }

        let toolbarContainer = BlurredToolbarContainer()
        toolbarContainer.alpha = 0
        view.addSubview(toolbarContainer)
        toolbarContainer.autoPinWidthToSuperview()
        toolbarContainer.autoPinEdge(toSuperviewEdge: .bottom)
        self.multiselectToolbarContainer = toolbarContainer

        let bottomInset = tabController.tabBar.height - tabController.tabBar.safeAreaInsets.bottom
        self.tableView.contentInset.bottom = bottomInset
        self.tableView.verticalScrollIndicatorInsets.bottom = bottomInset

        tabController.setTabBarHidden(true, animated: true, duration: 0.1) { [weak self] _ in
            guard let self else { return }
            // See ChatListViewController.showToolbar for why this is async
            DispatchQueue.main.async {
                self.multiselectToolbar?.setItems(
                    [.flexibleSpace(), self.toolbarDeleteButton],
                    animated: false
                )
                self.updateMultiselectToolbarButtons()
            }
            UIView.animate(withDuration: 0.25) {
                toolbarContainer.alpha = 1
            }
        }
    }

    private func updateMultiselectToolbarButtons() {
        let selectedRows = tableView.indexPathsForSelectedRows ?? []
        let hasSelectedEntries = !selectedRows.isEmpty
        toolbarDeleteButton.isEnabled = hasSelectedEntries
    }

    @objc
    private func deleteSelectedCalls() {
        guard let selectedRows = tableView.indexPathsForSelectedRows else {
            return
        }

        let selectedViewModelReferences: [CallViewModel.Reference] = selectedRows.map { idxPath in
            viewModelLoader.loadedViewModelReferences[index: idxPath.row]
        }

        deleteCalls(viewModelReferences: selectedViewModelReferences)
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
        .cancelButton { [weak self] in
            self?.cancelMultiselect()
        }
    }

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
            self.multiselectToolbarContainer = nil
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
            /// Delete-all should use the timestamp of the most-recent call, at
            /// the time the action was initiated, as the timestamp we delete
            /// before (and include in the outgoing sync message).
            ///
            /// If we don't have a most-recent call there's no point in
            /// doing a delete anyway.
            ///
            /// We also want to be sure we get the absolute most-recent call,
            /// rather than the most recent call matching our UI state – if the
            /// user does delete-all while filtering to Missed, we still want to
            /// actually delete all.
            self.deps.db.asyncWrite { tx in
                guard
                    let mostRecentCallRecord = try? self.deps.callRecordQuerier.fetchCursor(
                        ordering: .descending, tx: tx.asV2Read
                    )?.next()
                else { return }

                /// This will ultimately post "call records deleted"
                /// notifications that this view is listening to, so we don't
                /// need to do any manual UI updates.
                self.deps.callRecordDeleteAllJobQueue.addJob(
                    sendDeleteAllSyncMessage: true,
                    deleteAllBefore: .callRecord(mostRecentCallRecord),
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
        segmentedControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        return segmentedControl
    }()

    // MARK: Search bar

    /// Sets the navigation item's search controller if it hasn't already been
    /// set. Call this after loading the table the first time so that the search
    /// bar is collapsed by default.
    func setSearchControllerIfNeeded() {
        guard navigationItem.searchController == nil else { return }
        let searchController = UISearchController(searchResultsController: nil)
        navigationItem.searchController = searchController
        searchController.searchResultsUpdater = self
    }

    @objc
    private func filterChanged() {
        loadCallRecordsAnew(animated: true)
        updateMultiselectToolbarButtons()
    }

    private var currentFilterMode: FilterMode {
        FilterMode(rawValue: filterPicker.selectedSegmentIndex) ?? .all
    }

    // MARK: - Observers and Notifications

    private func attachSelfAsObservers() {
        deps.db.appendDatabaseChangeDelegate(self)

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

        if DebugFlags.internalLogging {
            logger.info("Group call interaction was updated, reloading.")
        }

        let callRecordIdForGroupCall = CallRecord.ID(
            callId: notification.callId,
            threadRowId: notification.groupThreadRowId
        )

        reloadRows(callRecordIds: [callRecordIdForGroupCall])
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
            existingCallRecordsWereDeleted(callRecordIds: callRecordIds)
        case .statusUpdated(let callRecordId):
            callRecordStatusWasUpdated(callRecordId: callRecordId)
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

    private func existingCallRecordsWereDeleted(callRecordIds: [CallRecord.ID]) {
        deps.db.read { tx in
            viewModelLoader.dropCalls(
                matching: callRecordIds, tx: tx.asV2Read
            )
        }

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
    private func callRecordStatusWasUpdated(callRecordId: CallRecord.ID) {
        reloadRows(callRecordIds: [callRecordId])
    }

    // MARK: CallServiceObserver

    /// When we learn that this device has joined or left a call, we'll reload
    /// any rows related to that call so that we show the latest state in this
    /// view.
    ///
    /// Recall that any 1:1 call we are not actively joined to has ended, and
    /// that that is not the case for group calls.
    func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        let callRecordIdsToReload = [oldValue, newValue].compactMap { call -> CallRecord.ID? in
            return call?.callRecordId
        }

        reloadRows(callRecordIds: callRecordIdsToReload)
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
                    beforeTimestamp: nil,
                    sendSyncMessage: true,
                    tx: tx.asV2Write
                )
            }
        }
    }

    // MARK: - Call loading

    private var _viewModelLoader: ViewModelLoader!
    private var viewModelLoader: ViewModelLoader! {
        get {
            AssertIsOnMainThread()
            return _viewModelLoader
        }
        set(newValue) {
            AssertIsOnMainThread()
            _viewModelLoader = newValue
        }
    }

    /// Used to avoid concurrent calls to ``loadCallRecordsAnew(animated:)``
    /// from clobbering each other.
    private var loadCallRecordsAnewCounter = 0

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

        self.loadCallRecordsAnewCounter += 1
        let loadCallRecordsAnewCounterSnapshot = self.loadCallRecordsAnewCounter

        deps.db.asyncRead(
            block: { tx -> CallRecordLoaderImpl.Configuration in
                if let searchTerm {
                    var threadRowIdsMatchingSearchTerm = Set<Int64>()
                    let addresses = self.deps.searchableNameFinder.searchNames(
                        for: searchTerm,
                        maxResults: Constants.maxSearchResults,
                        tx: tx.asV2Read,
                        checkCancellation: {},
                        addGroupThread: { groupThread in
                            guard let sqliteRowId = groupThread.sqliteRowId else {
                                owsFail("How did we match a thread in the FTS index that hasn't been inserted?")
                            }
                            threadRowIdsMatchingSearchTerm.insert(sqliteRowId)
                        },
                        addStoryThread: { _ in }
                    )

                    for address in addresses {
                        guard
                            let contactThread = TSContactThread.getWithContactAddress(address, transaction: tx),
                            contactThread.shouldThreadBeVisible
                        else {
                            continue
                        }
                        guard let sqliteRowId = contactThread.sqliteRowId else {
                            owsFail("How did we match a thread in the FTS index that hasn't been inserted?")
                        }
                        threadRowIdsMatchingSearchTerm.insert(sqliteRowId)
                    }

                    return CallRecordLoaderImpl.Configuration(
                        onlyLoadMissedCalls: onlyLoadMissedCalls,
                        onlyMatchThreadRowIds: Array(threadRowIdsMatchingSearchTerm)
                    )
                } else {
                    return CallRecordLoaderImpl.Configuration(
                        onlyLoadMissedCalls: onlyLoadMissedCalls,
                        onlyMatchThreadRowIds: nil
                    )
                }
            },
            completionQueue: .main,
            completion: { configuration in
                guard self.loadCallRecordsAnewCounter == loadCallRecordsAnewCounterSnapshot else {
                    /// While we were building the configuration, another caller
                    /// entered this method. Bail out in preference of the later
                    /// caller!
                    return
                }

                // Build a loader for this view's current state.
                let callRecordLoader = CallRecordLoaderImpl(
                    callRecordQuerier: self.deps.callRecordQuerier,
                    configuration: configuration
                )

                /// We don't want to capture self in the blocks we pass to the
                /// view model loader (and thereby create a retain cycle), so
                /// instead we'll early-capture just the dependencies those
                /// blocks actually need and give them a copy.
                let capturedDeps = self.deps

                // Reset our loaded calls.
                self.viewModelLoader = ViewModelLoader(
                    callRecordLoader: callRecordLoader,
                    createCallViewModelBlock: { primaryCallRecord, coalescedCallRecords, tx in
                        return Self.createCallViewModel(
                            primaryCallRecord: primaryCallRecord,
                            coalescedCallRecords: coalescedCallRecords,
                            deps: capturedDeps,
                            tx: SDSDB.shimOnlyBridge(tx)
                        )
                    },
                    fetchCallRecordBlock: { callRecordId, tx -> CallRecord? in
                        return capturedDeps.callRecordStore.fetch(
                            callRecordId: callRecordId,
                            tx: SDSDB.shimOnlyBridge(tx)
                        ).unwrapped
                    }
                )

                // Load the initial page of records. We've thrown away all our
                // existing calls, so we want to always update the snapshot.
                self.loadMoreCalls(
                    direction: .older,
                    animated: animated,
                    forceUpdateSnapshot: true
                )
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
        if indexPath.row == viewModelLoader.loadedViewModelReferences.count - 1 {
            /// If this index path represents the oldest loaded call, try and
            /// load another page of even-older calls.
            loadMoreCalls(direction: .older, animated: false)
        } else if !viewModelLoader.hasCachedViewModel(
            loadedViewModelReferenceIndex: indexPath.row
        ) {
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
                viewModelLoader.loadUntilCached(
                    loadedViewModelReferenceIndex: indexPath.row, tx: tx.asV2Read
                )
            }
        }

        return viewModelLoader.getCachedViewModel(
            loadedViewModelReferenceIndex: indexPath.row
        )
    }

    /// Synchronously loads more calls, then asynchronously update the snapshot
    /// if any new calls were actually loaded.
    ///
    /// - Parameter forceUpdateSnapshot
    /// Whether we should always update the snapshot, regardless of if any new
    /// calls were loaded.
    private func loadMoreCalls(
        direction loadDirection: ViewModelLoader.LoadDirection,
        animated: Bool,
        forceUpdateSnapshot: Bool = false
    ) {
        let shouldUpdateSnapshot = deps.db.read { tx in
            return viewModelLoader.loadMore(
                direction: loadDirection, tx: tx.asV2Read
            )
        }

        guard forceUpdateSnapshot || shouldUpdateSnapshot else { return }

        DispatchQueue.main.async {
            self.updateSnapshot(animated: animated)
            // Add the search bar after loading table content the first time so
            // that it is collapsed by default.
            self.setSearchControllerIfNeeded()
        }
    }

    /// Converts ``CallRecord``s into a ``CallViewModel``.
    ///
    /// - Important
    /// The primary and and coalesced call records *must* all have the same
    /// thread, direction, missed status, and call type.
    private static func createCallViewModel(
        primaryCallRecord: CallRecord,
        coalescedCallRecords: [CallRecord],
        deps: Dependencies,
        tx: SDSAnyReadTransaction
    ) -> CallViewModel {
        owsAssert(
            coalescedCallRecords.allSatisfy { $0.threadRowId == primaryCallRecord.threadRowId },
            "Coalesced call records were for a different thread than the primary!"
        )
        owsAssert(
            coalescedCallRecords.allSatisfy { $0.callDirection == primaryCallRecord.callDirection },
            "Coalesced call records were of a different direction than the primary!"
        )
        owsAssert(
            coalescedCallRecords.allSatisfy { $0.callStatus.isMissedCall == primaryCallRecord.callStatus.isMissedCall },
            "Coalesced call records were of a different missed status than the primary!"
        )
        owsAssert(
            ([primaryCallRecord] + coalescedCallRecords).isSortedByTimestamp(.descending),
            "Primary and coalesced call records were not ordered descending by timestamp!"
        )

        guard let callThread = deps.threadStore.fetchThread(
            rowId: primaryCallRecord.threadRowId,
            tx: tx.asV2Read
        ) else {
            owsFail("Missing thread for call record! This should be impossible, per the DB schema.")
        }

        let callDirection: CallViewModel.Direction = {
            if primaryCallRecord.callStatus.isMissedCall {
                return .missed
            }

            switch primaryCallRecord.callDirection {
            case .incoming: return .incoming
            case .outgoing: return .outgoing
            }
        }()

        /// The call state may be different between the primary and the
        /// coalesced calls. For the view model's state, we use the primary.
        let callState: CallViewModel.State = {
            let currentCallId: UInt64? = deps.callService.currentCall?.callId

            switch primaryCallRecord.callStatus {
            case .individual:
                if primaryCallRecord.callId == currentCallId {
                    // We can have at most one 1:1 call active at a time, and if
                    // we have an active 1:1 call we must be in it. All other
                    // 1:1 calls must have ended.
                    return .participating
                }
            case .group:
                guard let groupCallInteraction: OWSGroupCallMessage = deps.interactionStore
                    .fetchAssociatedInteraction(
                        callRecord: primaryCallRecord, tx: tx.asV2Read
                    )
                else {
                    owsFail("Missing interaction for group call. This should be impossible per the DB schema!")
                }

                // We learn that a group call ended by peeking the group. During
                // that peek, we update the group call interaction. It's a
                // leetle wonky that we use the interaction to store that info,
                // but such is life.
                if !groupCallInteraction.hasEnded {
                    if primaryCallRecord.callId == currentCallId {
                        return .participating
                    }

                    return .active
                }
            }

            return .ended
        }()

        if let contactThread = callThread as? TSContactThread {
            let callType: CallViewModel.RecipientType.CallType = {
                switch primaryCallRecord.callType {
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
                primaryCallRecord: primaryCallRecord,
                coalescedCallRecords: coalescedCallRecords,
                title: deps.contactsManager.displayName(
                    for: contactThread.contactAddress, tx: tx
                ).resolvedValue(),
                recipientType: .individual(type: callType, contactThread: contactThread),
                direction: callDirection,
                state: callState
            )
        } else if let groupThread = callThread as? TSGroupThread {
            return CallViewModel(
                primaryCallRecord: primaryCallRecord,
                coalescedCallRecords: coalescedCallRecords,
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
        get { _searchTerm }
        set { _searchTerm = newValue?.nilIfEmpty }
    }

    private var searchTermCounter = 0

    private func searchTermDidChange() {
        self.searchTermCounter += 1
        let searchTermCounterSnapshot = self.searchTermCounter

        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.searchDebounceInterval) {
            guard self.searchTermCounter == searchTermCounterSnapshot else {
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

    struct CallViewModel {
        enum Reference: Hashable {
            case singleCall(CallRecord.ID)
            case coalescedCalls(
                primary: CallRecord.ID,
                coalesced: [CallRecord.ID]
            )

            var primaryId: CallRecord.ID {
                switch self {
                case .singleCall(let callRecordId): return callRecordId
                case .coalescedCalls(let primary, _): return primary
                }
            }
        }

        enum Direction {
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

        enum State {
            /// This call is active, but the user is not in it.
            case active
            /// The user is currently in this call.
            case participating
            /// The call is no longer active.
            case ended
        }

        enum RecipientType {
            case individual(type: CallType, contactThread: TSContactThread)
            case group(groupThread: TSGroupThread)

            enum CallType: Hashable {
                case audio
                case video
            }
        }

        let primaryCallRecord: CallRecord
        let coalescedCallRecords: [CallRecord]

        var allCallRecords: [CallRecord] { [primaryCallRecord] + coalescedCallRecords }

        var reference: Reference {
            if coalescedCallRecords.isEmpty {
                return .singleCall(primaryCallRecord.id)
            }

            return .coalescedCalls(
                primary: primaryCallRecord.id,
                coalesced: coalescedCallRecords.map { $0.id }
            )
        }

        let title: String
        let recipientType: RecipientType
        let direction: Direction
        let state: State

        var callId: UInt64 { primaryCallRecord.callId }
        var threadRowId: Int64 { primaryCallRecord.threadRowId }
        var callBeganDate: Date { primaryCallRecord.callBeganDate }

        /// The `callBeganTimestamp` of the oldest call contained herein.
        var oldestContainedTimestamp: UInt64 {
            if let lastCoalescedTimestamp = coalescedCallRecords.last?.callBeganTimestamp {
                return lastCoalescedTimestamp
            }

            return primaryCallRecord.callBeganTimestamp
        }

        /// The `callBeganTimestamp` of the newest call contained herein.
        var newestContainedTimestamp: UInt64 {
            return primaryCallRecord.callBeganTimestamp
        }

        init(
            primaryCallRecord: CallRecord,
            coalescedCallRecords: [CallRecord],
            title: String,
            recipientType: RecipientType,
            direction: Direction,
            state: State
        ) {
            self.primaryCallRecord = primaryCallRecord
            self.coalescedCallRecords = coalescedCallRecords
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
    }

    let tableView = UITableView(frame: .zero, style: .plain)

    private static var callCellReuseIdentifier = "callCell"

    private lazy var dataSource = DiffableDataSource(
        tableView: tableView
    ) { [weak self] tableView, indexPath, _viewModelReference -> UITableViewCell? in
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
            owsFailDebug("Missing cached view model – how did this happen?")

            /// Return an empty table cell, rather than a ``CallCell`` that's
            /// gonna be incorrectly configured.
            return UITableViewCell()
        }
    }

    private func getSnapshot() -> Snapshot {
        var snapshot = Snapshot()
        snapshot.appendSections([.primary])
        snapshot.appendItems(viewModelLoader.loadedViewModelReferences.allElements)
        return snapshot
    }

    private func updateSnapshot(animated: Bool) {
        dataSource.apply(getSnapshot(), animatingDifferences: animated)
        updateEmptyStateMessage()
        cancelMultiselectIfEmpty()
    }

    /// Reload any rows containing one of the given call record IDs.
    private func reloadRows(callRecordIds callRecordIdsToReload: [CallRecord.ID]) {
        /// Recreate the view models, so when the data source reloads the rows
        /// it'll reflect the new underlying state for that row.
        ///
        /// This step will also drop any IDs for models that are not currently
        /// loaded, which should not be included in the snapshot.
        let referencesToReload = deps.db.read { tx -> [CallViewModel.Reference] in
            return viewModelLoader.refreshViewModels(
                callRecordIds: callRecordIdsToReload, tx: tx.asV2Read
            )
        }

        if DebugFlags.internalLogging {
            logger.info("Reloading \(referencesToReload.count) rows.")
        }

        var snapshot = getSnapshot()
        snapshot.reloadItems(referencesToReload)
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
            viewModelLoader.loadedViewModelReferences.isEmpty
        {
            cancelMultiselect()
        }
    }

    private func updateEmptyStateMessage() {
        switch (viewModelLoader.loadedViewModelReferences.count, searchTerm) {
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

    var callRecordId: CallRecord.ID? {
        guard let callId else { return nil }
        return CallRecord.ID(callId: callId, threadRowId: threadRowId)
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
        callRecordId: CallRecord.ID,
        tx: SDSAnyReadTransaction
    ) -> CallRecordStore.MaybeDeletedFetchResult {
        return fetch(
            callId: callRecordId.callId,
            threadRowId: callRecordId.threadRowId,
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

        guard let viewModel = viewModelLoader.getCachedViewModel(
            loadedViewModelReferenceIndex: indexPath.row
        ) else {
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
            self?.deleteCalls(viewModelReferences: [viewModel.reference])
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
                self?.deleteCalls(viewModelReferences: [viewModel.reference])
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

    private var callStarterContext: CallStarter.Context {
        .init(
            blockingManager: deps.blockingManager,
            databaseStorage: deps.db,
            callService: deps.callService
        )
    }

    private func startAudioCall(from viewModel: CallViewModel) {
        switch viewModel.recipientType {
        case let .individual(_, contactThread):
            CallStarter(
                contactThread: contactThread,
                withVideo: false,
                context: self.callStarterContext
            ).startCall(from: self)
        case .group:
            owsFail("Shouldn't be able to start audio call from group")
        }
    }

    private func startVideoCall(from viewModel: CallViewModel) {
        switch viewModel.recipientType {
        case let .individual(_, contactThread):
            CallStarter(
                contactThread: contactThread,
                withVideo: true,
                context: self.callStarterContext
            ).startCall(from: self)
        case let .group(groupThread):
            CallStarter(
                groupThread: groupThread,
                context: self.callStarterContext
            ).startCall(from: self)
        }
    }

    private func goToChat(from viewModel: CallViewModel) {
        goToChat(for: viewModel.thread)
    }

    private func deleteCalls(viewModelReferences: [CallViewModel.Reference]) {
        deps.db.asyncWrite { tx in
            let callRecordIdsToDelete: [CallRecord.ID] = viewModelReferences.flatMap { reference in
                return reference.containedIds
            }

            let callRecordsToDelete = callRecordIdsToDelete.compactMap { callRecordId -> CallRecord? in
                return self.deps.callRecordStore.fetch(
                    callRecordId: callRecordId, tx: tx
                ).unwrapped
            }

            /// Deleting these call records will trigger a ``CallRecordStoreNotification``,
            /// which we're listening for in this view and will in turn lead us
            /// to update the UI as appropriate.
            ///
            /// We also want to send a sync message since this is a delete
            /// originating from this device.
            self.deps.callRecordDeleteManager.deleteCallRecordsAndAssociatedInteractions(
                callRecords: callRecordsToDelete,
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
        guard case let .group(groupThread) = viewModel.recipientType else {
            owsFailBeta("Individual call should not be showing a join button")
            return
        }
        CallStarter(
            groupThread: groupThread,
            context: self.callStarterContext
        ).startCall(from: self)
    }

    fileprivate func returnToCall(from viewModel: CallViewModel) {
        guard WindowManager.shared.hasCall else { return }
        WindowManager.shared.returnToCallView()
    }

    fileprivate func showCallInfo(from viewModel: CallViewModel) {
        AssertIsOnMainThread()

        let (threadViewModel, isSystemContact) = deps.db.read { tx in
            let thread = viewModel.thread
            let threadViewModel = ThreadViewModel(
                thread: thread,
                forChatList: false,
                transaction: tx
            )
            let isSystemContact = thread.isSystemContact(
                contactsManager: deps.contactsManager,
                tx: tx
            )
            return (threadViewModel, isSystemContact)
        }

        let callDetailsView = ConversationSettingsViewController(
            threadViewModel: threadViewModel,
            isSystemContact: isSystemContact,
            // Nothing would have been revealed, so this can be a fresh instance
            spoilerState: SpoilerRenderState(),
            callViewModel: viewModel
        )

        callDetailsView.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(callDetailsView, animated: true)
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

// MARK: - DatabaseChangeDelegate

extension CallsListViewController: DatabaseChangeDelegate {
    /// If the database changed externally – which is to say, in the NSE – state
    /// that this view relies on may have changed. We can't know if it'll have
    /// affected us, so we'll simply load calls fresh and make the table view
    /// reload all the cells.
    func databaseChangesDidUpdateExternally() {
        logger.info("Database changed externally, loading calls anew and reloading all rows.")

        loadCallRecordsAnew(animated: false)
        reloadAllRows()
    }

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {}
    func databaseChangesDidReset() {}
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

            let titleText: String = {
                if viewModel.coalescedCallRecords.isEmpty {
                    return viewModel.title
                }

                return String(
                    format: Strings.coalescedCallsTitleFormat,
                    viewModel.title,
                    "\(viewModel.allCallRecords.count)"
                )
            }()
            self.titleLabel.text = titleText

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
