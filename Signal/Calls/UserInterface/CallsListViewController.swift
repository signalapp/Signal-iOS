//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalUI
import SignalRingRTC
import SignalServiceKit

// MARK: - CallCellDelegate

private protocol CallCellDelegate: AnyObject {
    func joinCall(from viewModel: CallsListViewController.CallViewModel)
    func returnToCall(from viewModel: CallsListViewController.CallViewModel)
    func showCallInfo(from viewModel: CallsListViewController.CallViewModel)
}

// MARK: - CallsListViewController

class CallsListViewController: OWSViewController, HomeTabViewController, CallServiceStateObserver, GroupCallObserver {
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, RowIdentifier>

    private enum Constants {
        /// The maximum number of search results to match.
        static let maxSearchResults: Int = 100

        /// An interval to wait after the search term changes before actually
        /// issuing a search.
        static let searchDebounceInterval: TimeInterval = 0.1
    }

    // MARK: - Dependencies

    private struct Dependencies {
        let adHocCallRecordManager: any AdHocCallRecordManager
        let badgeManager: BadgeManager
        let blockingManager: BlockingManager
        let callLinkStore: any CallLinkRecordStore
        let callRecordDeleteAllJobQueue: CallRecordDeleteAllJobQueue
        let callRecordDeleteManager: any CallRecordDeleteManager
        let callRecordMissedCallManager: CallRecordMissedCallManager
        let callRecordQuerier: CallRecordQuerier
        let callRecordStore: CallRecordStore
        let callService: CallService
        let contactsManager: any ContactManager
        let databaseChangeObserver: DatabaseChangeObserver
        let databaseStorage: SDSDatabaseStorage
        let db: any DB
        let groupCallManager: GroupCallManager
        let interactionDeleteManager: InteractionDeleteManager
        let interactionStore: InteractionStore
        let searchableNameFinder: SearchableNameFinder
        let threadStore: ThreadStore
        let tsAccountManager: any TSAccountManager
    }

    private nonisolated let deps: Dependencies = Dependencies(
        adHocCallRecordManager: DependenciesBridge.shared.adHocCallRecordManager,
        badgeManager: AppEnvironment.shared.badgeManager,
        blockingManager: SSKEnvironment.shared.blockingManagerRef,
        callLinkStore: DependenciesBridge.shared.callLinkStore,
        callRecordDeleteAllJobQueue: SSKEnvironment.shared.callRecordDeleteAllJobQueueRef,
        callRecordDeleteManager: DependenciesBridge.shared.callRecordDeleteManager,
        callRecordMissedCallManager: DependenciesBridge.shared.callRecordMissedCallManager,
        callRecordQuerier: DependenciesBridge.shared.callRecordQuerier,
        callRecordStore: DependenciesBridge.shared.callRecordStore,
        callService: AppEnvironment.shared.callService,
        contactsManager: SSKEnvironment.shared.contactManagerRef,
        databaseChangeObserver: DependenciesBridge.shared.databaseChangeObserver,
        databaseStorage: SSKEnvironment.shared.databaseStorageRef,
        db: DependenciesBridge.shared.db,
        groupCallManager: SSKEnvironment.shared.groupCallManagerRef,
        interactionDeleteManager: DependenciesBridge.shared.interactionDeleteManager,
        interactionStore: DependenciesBridge.shared.interactionStore,
        searchableNameFinder: SearchableNameFinder(
            contactManager: SSKEnvironment.shared.contactManagerRef,
            searchableNameIndexer: DependenciesBridge.shared.searchableNameIndexer,
            phoneNumberVisibilityFetcher: DependenciesBridge.shared.phoneNumberVisibilityFetcher,
            recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable
        ),
        threadStore: DependenciesBridge.shared.threadStore,
        tsAccountManager: DependenciesBridge.shared.tsAccountManager
    )

    private let appReadiness: AppReadinessSetter

    init(appReadiness: AppReadinessSetter) {
        self.appReadiness = appReadiness
        super.init()
    }

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
        OWSTableViewController2.removeBackButtonText(viewController: self)

        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()
        tableView.delegate = self
        tableView.allowsSelectionDuringEditing = true
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.separatorStyle = .none
        tableView.contentInset = .zero
        tableView.register(CreateCallLinkCell.self, forCellReuseIdentifier: Self.createCallLinkReuseIdentifier)
        tableView.register(CallCell.self, forCellReuseIdentifier: Self.callCellReuseIdentifier)
        tableView.dataSource = dataSource

        view.addSubview(emptyStateMessageView)
        emptyStateMessageView.autoCenterInSuperview()

        view.addSubview(noSearchResultsView)
        noSearchResultsView.autoPinWidthToSuperviewMargins()
        noSearchResultsView.autoPinEdge(toSuperviewMargin: .top, withInset: 80)

        applyTheme()

        initializeLoadedViewModels()
        attachSelfAsObservers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateDisplayedDateForAllCallCells()
        clearMissedCallsIfNecessary()
        isPeekingEnabled = true
        schedulePeekTimerIfNeeded()
        peekOnAppear()
        peekIfPossible()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isPeekingEnabled = false
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
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            buildActions: { settingsAction -> [UIAction] in
                return [
                    UIAction(
                        title: Strings.selectCallsButtonTitle,
                        image: Theme.iconImage(.contextMenuSelect),
                        handler: { [weak self] _ in
                            self?.startMultiselect()
                        }
                    ),
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
        presentFormSheet(AppSettingsViewController.inModalNavigationController(appReadiness: appReadiness), animated: true)
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

        let selectedModelReferenceses: [ViewModelLoader.ModelReferences] = selectedRows.map { idxPath in
            return viewModelLoader.modelReferences(at: idxPath.row)
        }

        promptToDeleteMultiple(count: selectedModelReferenceses.count) { [weak self] in
            do {
                try await self?.deleteCalls(modelReferenceses: selectedModelReferenceses)
                self?.presentToast(text: String.localizedStringWithFormat(
                    Strings.deleteMultipleSuccessFormat,
                    selectedModelReferenceses.count
                ))
            } catch {
                Logger.warn("\(error)")
                self?.presentSomeCallLinkDeletionError()
            }
        }
    }

    // MARK: Call Link Button

    private func createCallLink() {
        CreateCallLinkViewController.createCallLinkOnServerAndPresent(from: self)
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
        ) { [weak self] _ in
            Task {
                do {
                    try await self?.deleteAllCalls()
                } catch {
                    Logger.warn("\(error)")
                    self?.presentSomeCallLinkDeletionError()
                }
            }
        }
    }

    private func deleteAllCalls() async throws {
        let callLinksToDelete: [(rootKey: CallLinkRootKey, adminPasskey: Data)]
        callLinksToDelete = await self.deps.databaseStorage.awaitableWrite { tx in
            // We might have call links that have never been used. Plus, any call link
            // for which we're the admin isn't deleted by a "clear all" operation
            // because they must first be deleted on the server. (We delete them
            // individually at the end of this method.)
            let callLinksToDelete: [(rootKey: CallLinkRootKey, adminPasskey: Data)]
            callLinksToDelete = (try? self.deps.callLinkStore.fetchAll(tx: tx.asV2Read).compactMap {
                guard let adminPasskey = $0.adminPasskey else {
                    return nil
                }
                return ($0.rootKey, adminPasskey)
            }) ?? []
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
            let mostRecentCursor = self.deps.callRecordQuerier.fetchCursor(ordering: .descending, tx: tx.asV2Read)
            if let mostRecentCallRecord = try? mostRecentCursor?.next() {
                /// This will ultimately post "call records deleted"
                /// notifications that this view is listening to, so we don't
                /// need to do any manual UI updates.
                self.deps.callRecordDeleteAllJobQueue.addJob(
                    sendDeleteAllSyncMessage: true,
                    deleteAllBefore: .callRecord(mostRecentCallRecord),
                    tx: tx
                )
            }
            return callLinksToDelete
        }
        try await deleteCallLinks(callLinksToDelete: callLinksToDelete)
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
        Task { await reinitializeLoadedViewModels(animated: true) }
        updateMultiselectToolbarButtons()
    }

    private var currentFilterMode: FilterMode {
        FilterMode(rawValue: filterPicker.selectedSegmentIndex) ?? .all
    }

    // MARK: - Observers and Notifications

    private func attachSelfAsObservers() {
        deps.databaseChangeObserver.appendDatabaseChangeDelegate(self)

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

        // There might be an ongoing call when the calls tab appears, and if that's
        // the case, we want to grab its eraId before it ends.
        deps.callService.callServiceState.addObserver(self, syncStateImmediately: true)
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
            conversationId: .thread(threadRowId: notification.groupThreadRowId),
            callId: notification.callId
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
        loadMoreCalls(direction: .newer, animated: true)
    }

    private func existingCallRecordsWereDeleted(callRecordIds: [CallRecord.ID]) {
        deps.db.read { tx in
            viewModelLoader.dropCalls(matching: callRecordIds, tx: tx)
        }

        updateSnapshot(updatedReferences: [], animated: true)
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

    // MARK: CallServiceStateObserver

    private var currentCallId: UInt64?

    /// When we learn that this device has joined or left a call, we'll reload
    /// any rows related to that call so that we show the latest state in this
    /// view.
    ///
    /// Recall that any 1:1 call we are not actively joined to has ended, and
    /// that that is not the case for group calls.
    func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        // When a SignalCall ends, reload it if we know its callId.
        if let oldValue, let callId = self.currentCallId {
            switch oldValue.mode {
            case .individual(_):
                break
            case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
                call.removeObserver(self)
            }
            reloadRow(forCall: oldValue.mode, callId: callId)
            self.currentCallId = nil
        }

        // When a SignalCall starts, reload it as soon as we learn its callId.
        if let newValue {
            switch newValue.mode {
            case .individual(let call):
                if let callId = call.callId {
                    reloadRow(forCall: newValue.mode, callId: callId)
                    self.currentCallId = callId
                } else {
                    owsFailDebug("Can't start individual calls without callIds.")
                }
            case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
                // We need to fetch the eraId asynchronously, so there's nothing to refresh.
                call.addObserver(self, syncStateImmediately: true)
            }
        }
    }

    // MARK: GroupCallObserver

    func groupCallPeekChanged(_ call: GroupCall) {
        guard self.currentCallId == nil, let eraId = call.ringRtcCall.peekInfo?.eraId else {
            // We've already set it or still don't know it.
            return
        }
        let callId = callIdFromEra(eraId)
        self.currentCallId = callId
        reloadRow(forCall: CallMode(groupCall: call), callId: callId)
    }

    // MARK: Reloading the Current Call

    private func reloadRow(forCall callMode: CallMode, callId: UInt64) {
        let conversationId: CallRecord.ConversationID
        switch callMode {
        case .individual(let call):
            conversationId = .thread(threadRowId: call.thread.sqliteRowId!)
        case .groupThread(let call):
            let rowId = deps.db.read { tx in deps.threadStore.fetchGroupThread(groupId: call.groupId, tx: tx)?.sqliteRowId }
            guard let rowId else {
                owsFailDebug("Can't reload call with non-existent group thread.")
                return
            }
            conversationId = .thread(threadRowId: rowId)
        case .callLink(let call):
            // Query the database separately when starting & ending calls because the
            // row will usually be inserted during the call (ie `rowId` may be nil when
            // starting the call but nonnil when ending the very same call).
            let rowId = deps.db.read { tx in try? deps.callLinkStore.fetch(roomId: call.callLink.rootKey.deriveRoomId(), tx: tx)?.id }
            guard let rowId else {
                // If you open the lobby for an ongoing call that you've never joined,
                // we'll call this method after the peek succeeds. However, you haven't
                // joined the call yet, so there's no calls tab item that needs to be
                // reloaded to show the "Return" button. If you do join the call, a new row
                // will be added, and it will be (implicitly re)loaded because it's new.
                return
            }
            conversationId = .callLink(callLinkRowId: rowId)
        }
        reloadRows(callRecordIds: [CallRecord.ID(conversationId: conversationId, callId: callId)])
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
                self.deps.callRecordMissedCallManager.countUnreadMissedCalls(tx: tx)
            }

            /// We expect that the only unread calls to mark as read will be
            /// missed calls, so if there's no unread missed calls no need to
            /// open a write transaction.
            guard unreadMissedCallCount > 0 else { return }

            self.deps.db.write { tx in
                self.deps.callRecordMissedCallManager.markUnreadCallsAsRead(
                    beforeTimestamp: nil,
                    sendSyncMessage: true,
                    tx: tx
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

    private func initializeLoadedViewModels() {
        /// On initialization, we are not filtering to only missed calls.
        let onlyLoadMissedCalls = false

        /// On initialization, we are not filtering for any search term.
        let onlyMatchThreadRowIds: [Int64]? = nil

        setAndPrimeViewModelLoader(
            onlyLoadMissedCalls: onlyLoadMissedCalls,
            onlyMatchThreadRowIds: onlyMatchThreadRowIds,
            animated: false
        )
    }

    /// Used to avoid concurrent calls to `reinitializeLoadedViewModels` from
    /// clobbering each other.
    private var reinitializeLoadedViewModelsDebounceToken = 0

    /// Asynchronously resets our `viewModelLoader` for the current UI state,
    /// then kicks off an initial page load.
    ///
    /// - Note
    /// This method will perform an FTS search for our current search term, if
    /// we have one. That operation can be painfully slow for users with a large
    /// FTS index, so we need to do it asynchronously.
    private func reinitializeLoadedViewModels(animated: Bool) async {
        let searchTerm = self.searchTerm
        let onlyLoadMissedCalls: Bool = {
            switch self.currentFilterMode {
            case .all: return false
            case .missed: return true
            }
        }()

        self.reinitializeLoadedViewModelsDebounceToken += 1
        let debounceTokenSnapshot = self.reinitializeLoadedViewModelsDebounceToken

        let threadRowIdsMatchingSearchTerm: [Int64]?
        if let searchTerm {
            threadRowIdsMatchingSearchTerm = await findThreadRowIdsMatchingSearchTerm(searchTerm)
        } else {
            threadRowIdsMatchingSearchTerm = nil
        }

        guard self.reinitializeLoadedViewModelsDebounceToken == debounceTokenSnapshot else {
            /// While we were performing a search above, another caller entered
            /// this method. Bail out in preference of the later caller!
            return
        }

        setAndPrimeViewModelLoader(
            onlyLoadMissedCalls: onlyLoadMissedCalls,
            onlyMatchThreadRowIds: threadRowIdsMatchingSearchTerm,
            animated: animated
        )
    }

    /// Finds the row IDs of threads matching the given search term.
    ///
    /// - Note
    /// This operation can be slow, as it involves a potentially-heavy FTS
    /// query. Importantly, this method is `nonisolated` such that it doesn't
    /// inherit the `@MainActor` isolation of `UIViewController`.
    private nonisolated func findThreadRowIdsMatchingSearchTerm(
        _ searchTerm: String
    ) async -> [Int64] {
        return self.deps.databaseStorage.read { tx -> [Int64] in
            guard let localIdentifiers = self.deps.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
                owsFail("Can't search if you've never been registered.")
            }

            var threadRowIdsMatchingSearchTerm = Set<Int64>()
            let addresses = self.deps.searchableNameFinder.searchNames(
                for: searchTerm,
                maxResults: Constants.maxSearchResults,
                localIdentifiers: localIdentifiers,
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

            return Array(threadRowIdsMatchingSearchTerm)
        }
    }

    private func setAndPrimeViewModelLoader(
        onlyLoadMissedCalls: Bool,
        onlyMatchThreadRowIds: [Int64]?,
        animated: Bool
    ) {
        let callRecordLoader = CallRecordLoaderImpl(
            callRecordQuerier: self.deps.callRecordQuerier,
            configuration: CallRecordLoaderImpl.Configuration(
                onlyLoadMissedCalls: onlyLoadMissedCalls,
                onlyMatchThreadRowIds: onlyMatchThreadRowIds
            )
        )

        /// We don't want to capture self in the blocks we pass when creating
        /// the view model loader (and thereby create a retain cycle), so we'll
        /// early-capture the dependencies those blocks need.
        let capturedDeps = self.deps

        self.viewModelLoader = ViewModelLoader(
            callLinkStore: self.deps.callLinkStore,
            callRecordLoader: callRecordLoader,
            callViewModelForCallRecords: { callRecords, tx in
                return Self.callViewModel(
                    forCallRecords: callRecords,
                    upcomingCallLinkRowId: nil,
                    deps: capturedDeps,
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            },
            callViewModelForUpcomingCallLink: { callLinkRowId, tx in
                return Self.callViewModel(
                    forCallRecords: [],
                    upcomingCallLinkRowId: callLinkRowId,
                    deps: capturedDeps,
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            },
            fetchCallRecordBlock: { callRecordId, tx -> CallRecord? in
                return capturedDeps.callRecordStore.fetch(
                    callRecordId: callRecordId,
                    tx: SDSDB.shimOnlyBridge(tx)
                ).unwrapped
            },
            shouldFetchUpcomingCallLinks: !onlyLoadMissedCalls
        )

        self.reloadUpcomingCallLinks()

        // Load the initial page of records. We've thrown away all our
        // existing calls, so we want to always update the snapshot.
        self.loadMoreCalls(
            direction: .older,
            animated: animated,
            forceUpdateSnapshot: true
        )
    }

    /// Load more calls as necessary given that a row for the given index path
    /// is soon going to be presented.
    private func loadMoreCallsIfNecessary(indexToBeDisplayed callIndex: Int) {
        if callIndex + 1 == viewModelLoader.totalCount {
            /// If this index path represents the oldest loaded call, try and
            /// load another page of even-older calls.
            loadMoreCalls(direction: .older, animated: false)
        }
    }

    private func reloadUpcomingCallLinks() {
        deps.db.read { tx in viewModelLoader.reloadUpcomingCallLinkReferences(tx: tx) }
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
        let (shouldUpdateSnapshot, updatedReferences) = deps.db.read { tx in
            return viewModelLoader.loadCallHistoryItemReferences(direction: loadDirection, tx: tx)
        }

        guard forceUpdateSnapshot || shouldUpdateSnapshot || !updatedReferences.isEmpty else {
            return
        }

        DispatchQueue.main.async {
            self.updateSnapshot(updatedReferences: updatedReferences, animated: animated)
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
    private static func callViewModel(
        forCallRecords callRecords: [CallRecord],
        upcomingCallLinkRowId: Int64?,
        deps: Dependencies,
        tx: SDSAnyReadTransaction
    ) -> CallViewModel {
        owsPrecondition(
            Set(callRecords.map(\.conversationId)).count <= 1,
            "Coalesced call records were for a different conversation than the primary!"
        )
        owsPrecondition(
            Set(callRecords.map(\.callDirection)).count <= 1,
            "Coalesced call records were of a different direction than the primary!"
        )
        owsPrecondition(
            Set(callRecords.map(\.callStatus.isMissedCall)).count <= 1,
            "Coalesced call records were of a different missed status than the primary!"
        )
        owsPrecondition(
            callRecords.isSortedByTimestamp(.descending),
            "Primary and coalesced call records were not ordered descending by timestamp!"
        )

        let callLinkRecord = { () -> CallLinkRecord? in
            let callLinkRowId: Int64
            if let upcomingCallLinkRowId {
                callLinkRowId = upcomingCallLinkRowId
            } else if case .callLink(let callLinkRowId2) = callRecords.first!.conversationId {
                callLinkRowId = callLinkRowId2
            } else {
                return nil
            }
            do {
                return try deps.callLinkStore.fetch(rowId: callLinkRowId, tx: tx.asV2Read) ?? {
                    owsFail("Couldn't load CallLinkRecord that must exist!")
                }()
            } catch {
                owsFail("Couldn't load CallLinkRecord that must exist: \(error)")
            }
        }()

        if let callLinkRecord {
            return CallViewModel(
                reference: .callLink(rowId: callLinkRecord.id),
                callRecords: callRecords,
                title: callLinkRecord.state.localizedName,
                recipientType: .callLink(callLinkRecord.rootKey),
                direction: .callLink,
                medium: .link,
                state: { () -> CallViewModel.State in
                    if let activeCallId = callLinkRecord.activeCallId {
                        if deps.callService.callServiceState.currentCall?.callId == activeCallId {
                            return .participating
                        }
                        return .active
                    }
                    return .inactive
                }()
            )
        }

        // If it's not a CallLink, we MUST have at least one CallRecord.
        let callRecord = callRecords.first!

        let callDirection: CallViewModel.Direction = {
            if callRecord.callStatus.isMissedCall {
                return .missed
            }

            switch callRecord.callDirection {
            case .incoming: return .incoming
            case .outgoing: return .outgoing
            }
        }()

        /// The call state may be different between the primary and the
        /// coalesced calls. For the view model's state, we use the primary.
        let callState: CallViewModel.State = {
            let currentCallId: UInt64? = deps.callService.callServiceState.currentCall?.callId

            switch callRecord.callStatus {
            case .individual:
                if callRecord.callId == currentCallId {
                    // We can have at most one 1:1 call active at a time, and if
                    // we have an active 1:1 call we must be in it. All other
                    // 1:1 calls must have ended.
                    return .participating
                }
            case .group:
                guard
                    let groupCallInteraction: OWSGroupCallMessage = deps.interactionStore
                        .fetchAssociatedInteraction(callRecord: callRecord, tx: tx.asV2Read)
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
            case .callLink:
                owsFail("Can't reach this point because we've already handled Call Links.")
            }

            return .inactive
        }()

        let title: String
        let medium: CallViewModel.Medium
        let recipientType: CallViewModel.RecipientType

        switch callRecord.conversationId {
        case .thread(let threadRowId):
            guard let callThread = deps.threadStore.fetchThread(
                rowId: threadRowId,
                tx: tx.asV2Read
            ) else {
                owsFail("Missing thread for call record! This should be impossible, per the DB schema.")
            }
            switch callThread {
            case let contactThread as TSContactThread:
                title = deps.contactsManager.displayName(for: contactThread.contactAddress, tx: tx).resolvedValue()
                let callType: CallViewModel.RecipientType.IndividualCallType
                switch callRecords.first!.callType {
                case .audioCall:
                    medium = .audio
                    callType = .audio
                case .adHocCall, .groupCall:
                    owsFailDebug("Had group call type for 1:1 call!")
                    fallthrough
                case .videoCall:
                    medium = .video
                    callType = .video
                }
                recipientType = .individual(type: callType, contactThread: contactThread)
            case let groupThread as TSGroupThread:
                title = groupThread.groupModel.groupNameOrDefault
                medium = .video
                recipientType = .groupThread(groupId: groupThread.groupId)
            default:
                owsFail("Call thread was neither contact nor group! This should be impossible.")
            }
        case .callLink(_):
            owsFail("Can't reach this point because we've already handled Call Links.")
        }

        return CallViewModel(
            reference: .callRecords(oldestId: callRecords.last!.id),
            callRecords: callRecords,
            title: title,
            recipientType: recipientType,
            direction: callDirection,
            medium: medium,
            state: callState
        )
    }

    // MARK: - Peeking

    /// Fires when active calls should be checked again. Also replenishes
    /// `peekAllowance`. May be nonnil even when `isPeekingEnabled` is false to
    /// handle rapid tab switching.
    private var peekTimer: Timer?

    /// Remaining peeks that can be performed. Replenishes every 30 seconds.
    private var peekAllowance = 10

    /// If true, call links & active calls should be peeked periodically.
    private var isPeekingEnabled = false

    /// An ordered list of groups & call links that would be useful to peek.
    private var peekQueue = [Peekable]()

    /// Identifiers that have been scheduled in this 30 second interval. We
    /// remove items when `peekTimer` fires to avoid peeking the same values
    /// repeatedly when scrolling.
    private var peekQueueIdentifiers = Set<Data>()

    /// Timestamps when call links were recently peeked.
    private var callLinkPeekDates = [Data: MonotonicDate]()

    private enum Peekable {
        case groupThread(groupId: GroupIdentifier)
        case callLink(rootKey: CallLinkRootKey)

        var identifier: Data {
            switch self {
            case .groupThread(let groupId): groupId.serialize().asData
            case .callLink(let rootKey): rootKey.deriveRoomId()
            }
        }
    }

    /// Schedules a peeks if there's no peek scheduled.
    private func addToPeekQueue(_ peekable: Peekable) {
        guard peekQueueIdentifiers.insert(peekable.identifier).inserted else {
            return
        }
        peekQueue.append(peekable)
        peekIfPossible()
    }

    /// Peeks `peekAllowance` items from `peekQueue`.
    ///
    /// It will often be the case that items added via `addToPeekQueue` are
    /// peeked immediately. However, if more than 10 items are added, they'll
    /// queue up until the next 30 second interval.
    private func peekIfPossible() {
        guard self.isPeekingEnabled else {
            return
        }
        let peekBatch = self.peekQueue.prefix(peekAllowance)
        self.peekQueue.removeFirst(peekBatch.count)
        for peekable in peekBatch {
            switch peekable {
            case .groupThread(let groupId):
                Task { [deps] in
                    await deps.groupCallManager.peekGroupCallAndUpdateThread(forGroupId: groupId, peekTrigger: .localEvent())
                }
            case .callLink(let rootKey):
                self.callLinkPeekDates[rootKey.deriveRoomId()] = MonotonicDate()
                Task { [deps] in
                    do {
                        try await Self.peekCallLink(rootKey: rootKey, deps: deps)
                    } catch {
                        Logger.warn("\(error)")
                    }
                }
            }
        }
        self.peekAllowance -= peekBatch.count
    }

    private static nonisolated func peekCallLink(rootKey: CallLinkRootKey, deps: Dependencies) async throws {
        guard let localIdentifiers = deps.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            throw OWSGenericError("Not registered.")
        }
        let authCredential = try await deps.callService.authCredentialManager.fetchCallLinkAuthCredential(localIdentifiers: localIdentifiers)
        let eraId: String?
        do {
            eraId = try await deps.callService.callLinkManager.peekCallLink(rootKey: rootKey, authCredential: authCredential)
        } catch CallLinkManagerImpl.PeekError.expired, CallLinkManagerImpl.PeekError.invalid {
            eraId = nil
        }
        try await deps.db.awaitableWrite { tx in
            try deps.adHocCallRecordManager.handlePeekResult(eraId: eraId, rootKey: rootKey, tx: tx)
        }
    }

    /// Performs the relevant peek steps when the view appears.
    private func peekOnAppear() {
        if viewModelLoader == nil {
            return
        }
        if !viewModelLoader.isEmpty, viewModelLoader.viewModels().compacted().isEmpty {
            _ = viewModelLoader.viewModel(at: 0, sneakyTransactionDb: self.deps.db)
        }
        peekActiveCalls()
        peekInactiveCallLinks()
    }

    /// Schedules periodic operations: replinishing & active call re-peeking.
    private func schedulePeekTimerIfNeeded() {
        if self.peekTimer != nil {
            return
        }
        self.peekTimer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true,
            block: { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.peekAllowance = 10
                self.peekQueueIdentifiers = Set(self.peekQueue.map(\.identifier))
                guard self.isPeekingEnabled else {
                    timer.invalidate()
                    self.peekTimer = nil
                    return
                }
                self.peekActiveCalls()
                self.peekIfPossible()
            }
        )
    }

    private func peekActiveCalls() {
        for viewModel in viewModelLoader.viewModels() {
            guard let viewModel else {
                continue
            }
            peekIfActive(viewModel)
        }
    }

    private func peekIfActive(_ viewModel: CallViewModel) {
        guard viewModel.state == .active else {
            return
        }
        switch viewModel.recipientType {
        case .individual:
            break
        case .groupThread(groupId: let groupId):
            guard let groupId = try? GroupIdentifier(contents: [UInt8](groupId)) else {
                owsFailDebug("Can't peek group call with invalid group id.")
                break
            }
            addToPeekQueue(.groupThread(groupId: groupId))
        case .callLink(let rootKey):
            addToPeekQueue(.callLink(rootKey: rootKey))
        }
    }

    private func peekInactiveCallLinks() {
        for viewModel in viewModelLoader.viewModels() {
            guard let viewModel, viewModel.state == .inactive else {
                continue
            }
            switch viewModel.recipientType {
            case .individual, .groupThread:
                break
            case .callLink(let rootKey):
                // Skip any where the link is more than 10 days old.
                if
                    let timestamp = viewModel.callRecords.first?.callBeganTimestamp,
                    -Date(millisecondsSince1970: timestamp).timeIntervalSinceNow > 10 * kDayInterval
                {
                    continue
                }
                // Skip any that have been updated in the past 5 minutes.
                if
                    let peekDate = callLinkPeekDates[rootKey.deriveRoomId()],
                    (MonotonicDate() - peekDate) < 300 * NSEC_PER_SEC
                {
                    continue
                }
                addToPeekQueue(.callLink(rootKey: rootKey))
            }
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

    private var searchTermDebounceToken = 0

    private func searchTermDidChange() {
        self.searchTermDebounceToken += 1
        let debounceTokenSnapshot = self.searchTermDebounceToken

        Task {
            try await Task.sleep(nanoseconds: UInt64(Double(NSEC_PER_SEC) * Constants.searchDebounceInterval))

            guard self.searchTermDebounceToken == debounceTokenSnapshot else {
                /// The search term changed in the debounce period, so we'll
                /// bail out here in preference for the later-changed search
                /// term.
                return
            }

            await self.reinitializeLoadedViewModels(animated: true)
        }
    }

    // MARK: - Table view

    fileprivate enum Section: Int, Hashable {
        case createCallLink
        case existingCalls
    }

    fileprivate enum RowIdentifier: Hashable {
        case createCallLink
        case callViewModelReference(CallViewModel.Reference)
    }

    struct CallViewModel {
        enum Reference: Hashable {
            case callRecords(oldestId: CallRecord.ID)
            case callLink(rowId: Int64)
        }

        enum Direction {
            case outgoing
            case incoming
            case missed
            case callLink

            var label: String {
                switch self {
                case .outgoing:
                    return Strings.callDirectionLabelOutgoing
                case .incoming:
                    return Strings.callDirectionLabelIncoming
                case .missed:
                    return Strings.callDirectionLabelMissed
                case .callLink:
                    return CallStrings.callLink
                }
            }
        }

        enum Medium {
            case audio
            case video
            case link
        }

        enum State {
            /// This call is active, but the user is not in it.
            case active
            /// The user is currently in this call.
            case participating
            /// The call is no longer active or was never active (eg, an upcoming Call Link).
            case inactive
        }

        enum RecipientType {
            case individual(type: IndividualCallType, contactThread: TSContactThread)
            case groupThread(groupId: Data)
            case callLink(CallLinkRootKey)

            enum IndividualCallType {
                case audio
                case video
            }
        }

        let reference: Reference
        let callRecords: [CallRecord]

        let title: String
        let recipientType: RecipientType
        let direction: Direction
        let medium: Medium
        let state: State

        init(
            reference: Reference,
            callRecords: [CallRecord],
            title: String,
            recipientType: RecipientType,
            direction: Direction,
            medium: Medium,
            state: State
        ) {
            self.reference = reference
            self.callRecords = callRecords
            self.title = title
            self.recipientType = recipientType
            self.direction = direction
            self.medium = medium
            self.state = state
        }

        var isMissed: Bool {
            switch direction {
            case .outgoing, .incoming, .callLink:
                return false
            case .missed:
                return true
            }
        }
    }

    let tableView = UITableView(frame: .zero, style: .plain)

    private static let createCallLinkReuseIdentifier = "createCallLink"
    private static let callCellReuseIdentifier = "callCell"

    private lazy var dataSource = DiffableDataSource(
        tableView: tableView
    ) { [weak self] tableView, indexPath, _ -> UITableViewCell? in
        return self?.buildTableViewCell(tableView: tableView, indexPath: indexPath) ?? UITableViewCell()
    }

    private func buildTableViewCell(tableView: UITableView, indexPath: IndexPath) -> UITableViewCell? {
        switch Section(rawValue: indexPath.section) {
        case .createCallLink:
            if let createCallLinkCell = tableView.dequeueReusableCell(
                withIdentifier: Self.createCallLinkReuseIdentifier,
                for: indexPath
            ) as? CreateCallLinkCell {
                return createCallLinkCell
            }
            return nil
        case .existingCalls:
            guard
                let callCell = tableView.dequeueReusableCell(
                    withIdentifier: Self.callCellReuseIdentifier
                ) as? CallCell
            else {
                return nil
            }
            // These loads should be sufficiently fast that doing them here,
            // synchronously, is fine.
            self.loadMoreCallsIfNecessary(indexToBeDisplayed: indexPath.row)
            if let viewModel = viewModelLoader.viewModel(at: indexPath.row, sneakyTransactionDb: deps.db) {
                callCell.delegate = self
                callCell.viewModel = viewModel

                self.peekIfActive(viewModel)

                return callCell
            }
            owsFailDebug("Missing cached view model – how did this happen?")
            /// Return an empty table cell, rather than a ``CallCell`` that's
            /// gonna be incorrectly configured.
        case .none:
            break
        }
        return nil
    }

    private func getSnapshot() -> Snapshot {
        var snapshot = Snapshot()
        snapshot.appendSections([.createCallLink])
        snapshot.appendItems([.createCallLink])
        snapshot.appendSections([.existingCalls])
        snapshot.appendItems(viewModelLoader.viewModelReferences().map { .callViewModelReference($0) })
        return snapshot
    }

    private func updateSnapshot(updatedReferences: Set<CallViewModel.Reference>, animated: Bool) {
        var snapshot = getSnapshot()
        if #available(iOS 18.0, *) {
            snapshot.reloadItems(updatedReferences.map { .callViewModelReference($0) })
            dataSource.apply(snapshot, animatingDifferences: animated)
        } else {
            // On iOS 17 and lower, moving & reloading a row at the same time may
            // result in the wrong row being reloaded. Mitigate this by scheduling
            // these as two separate operations.
            dataSource.apply(snapshot, animatingDifferences: animated)
            if !updatedReferences.isEmpty {
                snapshot.reloadItems(updatedReferences.map { .callViewModelReference($0) })
                dataSource.apply(snapshot, animatingDifferences: animated)
            }
        }
        updateEmptyStateMessage()
        cancelMultiselectIfEmpty()
    }

    /// Reload any rows containing one of the given call record IDs.
    private func reloadRows(callRecordIds callRecordIdsToReload: [CallRecord.ID]) {
        if callRecordIdsToReload.isEmpty {
            return
        }

        /// Invalidate the view models, so when the data source reloads the rows,
        /// it'll reflect the new underlying state for that row.
        let referencesToReload = viewModelLoader.invalidate(
            callLinkRowIds: [],
            callRecordIds: Set(callRecordIdsToReload)
        )

        if referencesToReload.isEmpty {
            return
        }

        if DebugFlags.internalLogging {
            logger.info("Reloading \(referencesToReload.count) rows.")
        }

        var snapshot = getSnapshot()
        snapshot.reloadItems(referencesToReload.map { .callViewModelReference($0) })
        dataSource.apply(snapshot)
    }

    private func reloadAllRows() {
        var snapshot = getSnapshot()
        snapshot.reloadSections([.createCallLink, .existingCalls])
        dataSource.apply(snapshot)
    }

    private func cancelMultiselectIfEmpty() {
        if tableView.isEditing, viewModelLoader.isEmpty {
            cancelMultiselect()
        }
    }

    private func updateEmptyStateMessage() {
        switch (viewModelLoader.isEmpty, searchTerm) {
        case (true, .some(let searchTerm)) where !searchTerm.isEmpty:
            noSearchResultsView.text = String(
                format: Strings.searchNoResultsFoundLabelFormat,
                arguments: [searchTerm]
            )
            noSearchResultsView.layer.opacity = 1
            emptyStateMessageView.layer.opacity = 0
        case (true, _):
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
            section: CallsListViewController.Section.existingCalls.rawValue
        )
    }
}

private extension SignalCall {
    var callId: UInt64? {
        switch mode {
        case .individual(let individualCall):
            return individualCall.callId
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            return call.ringRtcCall.peekInfo?.eraId.map { callIdFromEra($0) }
        }
    }
}

private extension CallRecordStore {
    func fetch(
        callRecordId: CallRecord.ID,
        tx: SDSAnyReadTransaction
    ) -> CallRecordStore.MaybeDeletedFetchResult {
        return fetch(
            callId: callRecordId.callId,
            conversationId: callRecordId.conversationId,
            tx: tx.asV2Read
        )
    }
}

// MARK: - Data Source

extension CallsListViewController {
    fileprivate class DiffableDataSource: UITableViewDiffableDataSource<Section, RowIdentifier> {
        override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
            switch Section(rawValue: indexPath.section) {
            case .createCallLink:
                return false
            case .existingCalls, .none:
                return true
            }
        }
    }
}

// MARK: - UITableViewDelegate

extension CallsListViewController: UITableViewDelegate {

    private func viewModelWithSneakyTransaction(at indexPath: IndexPath) -> CallViewModel? {
        owsPrecondition(
            indexPath.section == Section.existingCalls.rawValue,
            "Unexpected section for index path: \(indexPath.section)"
        )

        guard let viewModel = viewModelLoader.viewModel(at: indexPath.row, sneakyTransactionDb: deps.db) else {
            owsFailBeta("Missing view model for index path. How did this happen?")
            return nil
        }

        return viewModel
    }

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        switch Section(rawValue: indexPath.section) {
        case .createCallLink:
            if tableView.isEditing {
                return nil
            }
        case .existingCalls, .none:
            break
        }
        return indexPath
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            updateMultiselectToolbarButtons()
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section) {
        case .createCallLink:
            createCallLink()
        case .existingCalls, .none:
            guard let viewModel = viewModelWithSneakyTransaction(at: indexPath) else {
                return
            }
            startCall(from: viewModel)
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            updateMultiselectToolbarButtons()
        }
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        switch Section(rawValue: indexPath.section) {
        case .createCallLink:
            return false
        case .existingCalls, .none:
            return true
        }
    }

    func tableView(_ tableView: UITableView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        updateBarButtonItems()
        showToolbar()
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        switch Section(rawValue: indexPath.section) {
        case .createCallLink:
            return nil
        case .existingCalls, .none:
            break
        }

        return self.longPressActions(forRowAt: indexPath)
            .map { actions in UIMenu.init(children: actions) }
            .map { menu in
                UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { _ in menu }
            }
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        switch Section(rawValue: indexPath.section) {
        case .createCallLink:
            return nil
        case .existingCalls, .none:
            break
        }

        guard let viewModel = viewModelWithSneakyTransaction(at: indexPath) else {
            return nil
        }

        guard let chatThread = goToChatThread(from: viewModel) else {
            return nil
        }

        let goToChatAction = makeContextualAction(
            style: .normal,
            color: .ows_accentBlue,
            image: "arrow-square-upright-fill",
            title: Strings.goToChatActionTitle
        ) { [weak self] in
            self?.goToChat(for: chatThread()!)
        }

        return .init(actions: [goToChatAction])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        switch Section(rawValue: indexPath.section) {
        case .createCallLink:
            return nil
        case .existingCalls, .none:
            break
        }

        let modelReferences = viewModelLoader.modelReferences(at: indexPath.row)

        let deleteAction = makeContextualAction(
            style: .destructive,
            color: .ows_accentRed,
            image: "trash-fill",
            title: CommonStrings.deleteButton
        ) { [weak self] in
            self?.promptToDeleteCallIfNeeded(modelReferences: modelReferences)
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
        guard let viewModel = viewModelWithSneakyTransaction(at: indexPath) else {
            return nil
        }
        let modelReferences = viewModelLoader.modelReferences(at: indexPath.row)

        var actions = [UIAction]()

        switch viewModel.state {
        case .active:
            let joinCallTitle: String
            let joinCallIconName: String
            switch viewModel.medium {
            case .audio:
                joinCallTitle = Strings.joinVoiceCallActionTitle
                joinCallIconName = Theme.iconName(.contextMenuVoiceCall)
            case .video, .link:
                // [CallLink] TODO: Use "Start Call" instead of "Start Video Call".
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
            switch viewModel.medium {
            case .audio:
                returnToCallIconName = Theme.iconName(.contextMenuVoiceCall)
            case .video, .link:
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
        case .inactive:
            switch viewModel.recipientType {
            case .individual:
                let audioCallAction = UIAction(
                    title: Strings.startVoiceCallActionTitle,
                    image: Theme.iconImage(.contextMenuVoiceCall),
                    attributes: []
                ) { [weak self] _ in
                    self?.startCall(from: viewModel, withVideo: false)
                }
                actions.append(audioCallAction)
            case .groupThread, .callLink:
                break
            }

            let videoCallAction = UIAction(
                title: Strings.startVideoCallActionTitle,
                image: Theme.iconImage(.contextMenuVideoCall),
                attributes: []
            ) { [weak self] _ in
                self?.startCall(from: viewModel, withVideo: true)
            }
            actions.append(videoCallAction)
        }

        if let chatThread = goToChatThread(from: viewModel) {
            let goToChatAction = UIAction(
                title: Strings.goToChatActionTitle,
                image: Theme.iconImage(.contextMenuOpenInChat),
                attributes: []
            ) { [weak self] _ in
                self?.goToChat(for: chatThread()!)
            }
            actions.append(goToChatAction)
        }

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
        case .active, .inactive:
            let deleteAction = UIAction(
                title: Strings.deleteCallActionTitle,
                image: Theme.iconImage(.contextMenuDelete),
                attributes: .destructive
            ) { [weak self] _ in
                self?.promptToDeleteCallIfNeeded(modelReferences: modelReferences)
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

    private var callStarterContext: CallStarter.Context {
        .init(
            blockingManager: deps.blockingManager,
            databaseStorage: deps.databaseStorage,
            callService: deps.callService
        )
    }

    private func startCall(from viewModel: CallViewModel, withVideo: Bool? = nil) {
        switch viewModel.recipientType {
        case let .individual(type, contactThread):
            CallStarter(
                contactThread: contactThread,
                withVideo: withVideo ?? (type == .video),
                context: self.callStarterContext
            ).startCall(from: self)
        case let .groupThread(groupId):
            owsPrecondition(withVideo != false, "Can't start voice call.")
            let groupId = try! GroupIdentifier(contents: [UInt8](groupId))
            CallStarter(
                groupId: groupId,
                context: self.callStarterContext
            ).startCall(from: self)
        case .callLink(let rootKey):
            owsPrecondition(withVideo != false, "Can't start voice call.")
            CallStarter(
                callLink: rootKey,
                context: self.callStarterContext
            ).startCall(from: self)
        }
    }

    private func promptToDeleteMultiple(count: Int, proceedAction: @escaping @MainActor () async -> Void) {
        OWSActionSheets.showConfirmationAlert(
            title: String.localizedStringWithFormat(Strings.deleteMultipleTitleFormat, count),
            message: Strings.deleteMultipleMessage,
            proceedTitle: Strings.deleteCallActionTitle,
            proceedStyle: .destructive,
            proceedAction: { _ in Task { await proceedAction() } },
            fromViewController: self
        )
    }

    private func presentSomeCallLinkDeletionError() {
        let actionSheet = ActionSheetController(message: Strings.deleteMultipleError)
        actionSheet.addAction(OWSActionSheets.okayAction)
        self.presentActionSheet(actionSheet)
    }

    private func promptToDeleteCallIfNeeded(modelReferences: ViewModelLoader.ModelReferences) {
        // If we're the admin for this link, we need to show a warning that other
        // people won't be able to use it.
        if isAdmin(forCallLinkRowId: modelReferences.callLinkRowId) {
            CallLinkDeleter.promptToDelete(fromViewController: self) { [weak self] in
                do {
                    try await self?.deleteCalls(modelReferenceses: [modelReferences])
                    self?.presentToast(text: CallLinkDeleter.successText)
                } catch {
                    Logger.warn("\(error)")
                    self?.presentToast(text: CallLinkDeleter.failureText)
                }
            }
        } else {
            // Otherwise, we can just delete it.
            Task {
                do {
                    try await self.deleteCalls(modelReferenceses: [modelReferences])
                } catch {
                    owsFailDebug("\(error)")
                }
            }
        }
    }

    private func isAdmin(forCallLinkRowId callLinkRowId: Int64?) -> Bool {
        return deps.databaseStorage.read { tx in
            guard let callLinkRowId else {
                return false
            }
            do {
                let callLinkRecord = try self.deps.callLinkStore.fetch(rowId: callLinkRowId, tx: tx.asV2Read) ?? {
                    throw OWSAssertionError("Couldn't fetch CallLink that must exist.")
                }()
                return callLinkRecord.adminPasskey != nil
            } catch {
                owsFailDebug("\(error)")
                return false
            }
        }
    }

    private func deleteCalls(modelReferenceses: [ViewModelLoader.ModelReferences]) async throws {
        let callLinksToDelete: [(rootKey: CallLinkRootKey, adminPasskey: Data)]

        // First, delete everything that's local only. This includes thread-based
        // calls & any call link calls for which we're not the admin. These
        // deletions never fail (except for db corruption-level failures).
        callLinksToDelete = try await deps.databaseStorage.awaitableWrite { tx in
            var callLinksToDelete = [(rootKey: CallLinkRootKey, adminPasskey: Data)]()
            var callRecordIdsWithInteractions = [CallRecord.ID]()
            for modelReferences in modelReferenceses {
                if let callLinkRowId = modelReferences.callLinkRowId {
                    let callLinkRecord = try self.deps.callLinkStore.fetch(rowId: callLinkRowId, tx: tx.asV2Read) ?? {
                        throw OWSAssertionError("Couldn't fetch CallLink that must exist.")
                    }()
                    if let adminPasskey = callLinkRecord.adminPasskey {
                        callLinksToDelete.append((callLinkRecord.rootKey, adminPasskey))
                    } else {
                        try self.deleteCallRecords(forCallLinkRowId: callLinkRecord.id, tx: tx.asV2Write)
                    }
                } else {
                    callRecordIdsWithInteractions.append(contentsOf: modelReferences.callRecordRowIds)
                }
            }
            let callRecordsWithInteractions = callRecordIdsWithInteractions.compactMap { callRecordId -> CallRecord? in
                return self.deps.callRecordStore.fetch(callRecordId: callRecordId, tx: tx).unwrapped
            }

            /// Deleting these call records will trigger a ``CallRecordStoreNotification``,
            /// which we're listening for in this view and will in turn lead us
            /// to update the UI as appropriate.
            self.deps.interactionDeleteManager.delete(
                alongsideAssociatedCallRecords: callRecordsWithInteractions,
                sideEffects: .default(),
                tx: tx.asV2Write
            )

            return callLinksToDelete
        }

        // Then, delete any call links we found for which we're the admin. Each of
        // these may independently fail.
        try await deleteCallLinks(callLinksToDelete: callLinksToDelete)
    }

    private nonisolated func deleteCallRecords(forCallLinkRowId callLinkRowId: Int64, tx: DBWriteTransaction) throws {
        let callRecords = try deps.callRecordStore.fetchExisting(conversationId: .callLink(callLinkRowId: callLinkRowId), limit: nil, tx: tx)
        deps.callRecordDeleteManager.deleteCallRecords(callRecords, sendSyncMessageOnDelete: true, tx: tx)
    }

    private func deleteCallLinks(callLinksToDelete: [(rootKey: CallLinkRootKey, adminPasskey: Data)]) async throws {
        let callLinkStateUpdater = deps.callService.callLinkStateUpdater
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for callLinkToDelete in callLinksToDelete {
                taskGroup.addTask {
                    try await CallLinkDeleter.deleteCallLink(
                        stateUpdater: callLinkStateUpdater,
                        storageServiceManager: SSKEnvironment.shared.storageServiceManagerRef,
                        rootKey: callLinkToDelete.rootKey,
                        adminPasskey: callLinkToDelete.adminPasskey
                    )
                }
            }
            var anyError: (any Error)?
            while let result = await taskGroup.nextResult() {
                switch result {
                case .success:
                    break
                case .failure(let error):
                    Logger.warn("Couldn't delete call link: \(error)")
                    anyError = error
                }
            }
            if let anyError {
                throw anyError
            }
        }
    }

    private func selectCall(forRowAt indexPath: IndexPath) {
        startMultiselect()
        tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
    }

    // MARK: CallCellDelegate

    fileprivate func joinCall(from viewModel: CallViewModel) {
        startCall(from: viewModel)
    }

    fileprivate func returnToCall(from viewModel: CallViewModel) {
        guard AppEnvironment.shared.windowManagerRef.hasCall else { return }
        AppEnvironment.shared.windowManagerRef.returnToCallView()
    }

    fileprivate func showCallInfo(from viewModel: CallViewModel) {
        AssertIsOnMainThread()

        switch viewModel.recipientType {
        case .individual(type: _, let thread):
            showCallInfo(forThread: thread, callRecords: viewModel.callRecords)
        case .groupThread(let groupId):
            let thread = deps.db.read { tx in deps.threadStore.fetchGroupThread(groupId: groupId, tx: tx)! }
            showCallInfo(forThread: thread, callRecords: viewModel.callRecords)
        case .callLink(let rootKey):
            showCallInfo(forRootKey: rootKey, callRecords: viewModel.callRecords)
        }
    }

    private func showCallInfo(forThread thread: TSThread, callRecords: [CallRecord]) {
        let (threadViewModel, isSystemContact) = deps.databaseStorage.read { tx in
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
            callRecords: callRecords
        )

        showCallInfo(viewController: callDetailsView)
    }

    private func showCallInfo(forRootKey rootKey: CallLinkRootKey, callRecords: [CallRecord]) {
        let callLinkRecord = deps.db.read { tx -> CallLinkRecord in
            do {
                return try deps.callLinkStore.fetch(roomId: rootKey.deriveRoomId(), tx: tx) ?? {
                    owsFail("Can't fetch CallLinkRecord that must exist.")
                }()
            } catch {
                owsFail("Can't fetch CallLinkRecord: \(error)")
            }
        }
        showCallInfo(viewController: CallLinkViewController.forExisting(callLinkRecord: callLinkRecord, callRecords: callRecords))
    }

    private func showCallInfo(viewController: UIViewController) {
        viewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(viewController, animated: true)
    }

    // MARK: NewCallViewControllerDelegate

    private func goToChatThread(from viewModel: CallViewModel) -> (() -> TSThread?)? {
        switch viewModel.recipientType {
        case .individual(type: _, let thread):
            return { thread }
        case .groupThread(let groupId):
            return { [deps] in
                return deps.db.read { tx in deps.threadStore.fetchGroupThread(groupId: groupId, tx: tx) }
            }
        case .callLink(_):
            return nil
        }
    }

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

        Task { await reinitializeLoadedViewModels(animated: false) }
        reloadAllRows()
    }

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard let rowIds = databaseChanges.tableRowIds[CallLinkRecord.databaseTableName] else {
            return
        }
        reloadUpcomingCallLinks()
        let updatedReferences = viewModelLoader.invalidate(callLinkRowIds: rowIds, callRecordIds: [])
        updateSnapshot(updatedReferences: updatedReferences, animated: true)
    }

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
            button.ows_contentEdgeInsets.trailing = Self.horizontalMargin
            button.ows_contentEdgeInsets.leading = 8
            // The join button is a separate subview and should be `joinButtonMargin` from the edge
            button.layoutMargins.trailing = Self.joinButtonMargin
            return button
        }()

        private var joinPill: UIView?

        private func makeJoinPill() -> UIView? {
            guard let viewModel else { return nil }

            let icon: UIImage
            switch viewModel.medium {
            case .audio:
                icon = Theme.iconImage(.phoneFill16)
            case .video, .link:
                icon = Theme.iconImage(.videoFill16)
            }

            let text: String
            switch viewModel.state {
            case .active:
                text = Strings.joinCallButtonTitle
            case .participating:
                text = Strings.returnToCallButtonTitle
            case .inactive:
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
            button.ows_contentEdgeInsets = .init(hMargin: 12, vMargin: 4)
            button.setCompressionResistanceHigh()
            button.isUserInteractionEnabled = false
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
                case .inactive:
                    return viewModel.callRecords.first?.callBeganDate
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
                switch viewModel.recipientType {
                case .individual(type: _, let thread):
                    configuration.dataSource = .thread(thread)
                case .groupThread(let groupId):
                    configuration.setGroupIdWithSneakyTransaction(groupId: groupId)
                case .callLink(let rootKey):
                    configuration.dataSource = .asset(avatar: CommonCallLinksUI.callLinkIcon(rootKey: rootKey), badge: nil)
                }
            }

            let titleText: String = {
                if viewModel.callRecords.count <= 1 {
                    return viewModel.title
                } else {
                    return String(format: Strings.coalescedCallsTitleFormat, viewModel.title, "\(viewModel.callRecords.count)")
                }
            }()
            self.titleLabel.text = titleText

            switch viewModel.direction {
            case .incoming, .outgoing, .callLink:
                titleLabel.textColor = Theme.primaryTextColor
            case .missed:
                titleLabel.textColor = .ows_accentRed
            }

            self.subtitleLabel.attributedText = {
                let icon: ThemeIcon
                switch viewModel.medium {
                case .audio:
                    icon = .phone16
                case .video:
                    icon = .video16
                case .link:
                    icon = .link16
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
            case .inactive:
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
            case .inactive:
                delegate.showCallInfo(from: viewModel)
            }
        }
    }
}

private extension CallsListViewController {
    class CreateCallLinkCell: UITableViewCell {
        private enum Constants {
            static let iconDimension: CGFloat = 24
            static let spacing: CGFloat = 18
            static let hMargin: CGFloat = 26
            static let vMargin: CGFloat = 15
        }

        private lazy var iconView: UIImageView = {
            let imageView = UIImageView(image: UIImage(named: "link"))
            imageView.tintColor = Theme.primaryIconColor
            imageView.autoSetDimensions(to: CGSize(square: Constants.iconDimension))
            return imageView
        }()

        private lazy var label: UILabel = {
            let label = UILabel()
            label.font = .dynamicTypeHeadline
            label.textColor = Theme.primaryTextColor
            label.numberOfLines = 3
            label.lineBreakMode = .byTruncatingTail
            label.text = OWSLocalizedString(
                "CREATE_CALL_LINK_LABEL",
                comment: "Label for button that enables you to make a new call link."
            )
            return label
        }()

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)

            let stackView = UIStackView(arrangedSubviews: [iconView, label])
            stackView.axis = .horizontal
            stackView.spacing = Constants.spacing
            stackView.alignment = .center

            self.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(hMargin: Constants.hMargin, vMargin: Constants.vMargin))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func prepareForReuse() {
            iconView.tintColor = Theme.primaryIconColor
            label.textColor = Theme.primaryTextColor
        }
    }
}
