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

class CallsListViewController: OWSViewController, HomeTabViewController {

    private typealias DiffableDataSource = UITableViewDiffableDataSource<Section, CallViewModel.ID>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, CallViewModel.ID>

    // MARK: - Dependencies

    private struct Dependencies {
        let callService: CallService
        let callRecordQuerier: CallRecordQuerier
        let contactsManager: ContactsManagerProtocol
        let db: SDSDatabaseStorage
        let fullTextSearchFinder: CallRecordLoader.Shims.FullTextSearchFinder
        let interactionStore: InteractionStore
        let threadStore: ThreadStore
    }

    private lazy var deps: Dependencies = Dependencies(
        callService: NSObject.callService,
        callRecordQuerier: DependenciesBridge.shared.callRecordQuerier,
        contactsManager: NSObject.contactsManager,
        db: NSObject.databaseStorage,
        fullTextSearchFinder: CallRecordLoader.Wrappers.FullTextSearchFinder(),
        interactionStore: DependenciesBridge.shared.interactionStore,
        threadStore: DependenciesBridge.shared.threadStore
    )

    // MARK: - Lifecycle

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

        navigationItem.titleView = tabPicker
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
        loadCallRecordsAnew()

        // [CallsTab] TODO: make ourselves a CallServiceObserver, so we know when calls change
    }

    override func themeDidChange() {
        super.themeDidChange()
        applyTheme()
        reloadAllRows()
    }

    private func updateBarButtonItems() {
        if tableView.isEditing {
            navigationItem.leftBarButtonItem = cancelMultiselectButton()
            navigationItem.rightBarButtonItem = nil
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
                        title: "Select", // [CallsTab] TODO: Localize
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

        tabController.setTabBarHidden(true, animated: true, duration: 0.1) { _ in
            // See ChatListViewController.showToolbar for why this is async
            DispatchQueue.main.async {
                self.updateMultiselectToolbarButtons()
            }
            UIView.animate(withDuration: 0.25) {
                toolbarContainer.alpha = 1
            } completion: { _ in
                self.tableView.contentSize.height += toolbarContainer.height
            }
        }
    }

    private func updateMultiselectToolbarButtons() {
        guard let multiselectToolbar else { return }

        let selectedRows = tableView.indexPathsForSelectedRows ?? []
        let areAllEntriesSelected = selectedRows.count == tableView.numberOfRows(inSection: 0)
        let hasSelectedEntries = !selectedRows.isEmpty

        let selectAllButtonTitle = areAllEntriesSelected ? "Deselect all" : "Select all" // [CallsTab] TODO: Localize
        let selectAllButton = UIBarButtonItem(
            title: selectAllButtonTitle,
            style: .plain,
            target: self,
            action: #selector(selectAllCalls)
        )

        let deleteButton = UIBarButtonItem(
            title: CommonStrings.deleteButton,
            style: .plain,
            target: self,
            action: #selector(deleteSelectedCalls)
        )
        deleteButton.isEnabled = hasSelectedEntries

        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        multiselectToolbar.setItems(
            [selectAllButton, spacer, deleteButton],
            animated: false
        )
    }

    @objc
    private func selectAllCalls() {
        let selectedRows = tableView.indexPathsForSelectedRows ?? []
        let numberOfRows = tableView.numberOfRows(inSection: 0)
        let areAllEntriesSelected = selectedRows.count == numberOfRows

        if areAllEntriesSelected {
            selectedRows.forEach { tableView.deselectRow(at: $0, animated: false) }
        } else {
            (0..<numberOfRows)
                .lazy
                .map { IndexPath(row: $0, section: 0) }
                .forEach { tableView.selectRow(at: $0, animated: false, scrollPosition: .none) }
        }
        updateMultiselectToolbarButtons()
    }

    @objc
    private func deleteSelectedCalls() {
        Logger.debug("Detele selected calls")
    }

    // MARK: New call button

    private func newCallButton() -> UIBarButtonItem {
        let barButtonItem = UIBarButtonItem(
            image: Theme.iconImage(.buttonNewCall),
            style: .plain,
            target: self,
            action: #selector(newCall)
        )
        // [CallsTab] TODO: Accessibility label
        return barButtonItem
    }

    @objc
    private func newCall() {
        Logger.debug("New call")
        let viewController = NewCallViewController()
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
        Logger.debug("Cancel selecting calls")
        tableView.setEditing(false, animated: true)
        updateBarButtonItems()
        hideToolbar()
    }

    private func hideToolbar() {
        guard let multiselectToolbarContainer else { return }
        UIView.animate(withDuration: 0.25) {
            multiselectToolbarContainer.alpha = 0
            self.tableView.contentSize.height = self.tableView.sizeThatFitsMaxSize.height
        } completion: { _ in
            multiselectToolbarContainer.removeFromSuperview()
            guard let tabController = self.tabBarController as? HomeTabBarController else { return }
            tabController.setTabBarHidden(false, animated: true, duration: 0.1)
        }
    }

    // MARK: Tab picker

    private enum FilterMode: Int {
        case all = 0
        case missed = 1
    }

    private lazy var tabPicker: UISegmentedControl = {
        let segmentedControl = UISegmentedControl(items: ["All", "Missed"]) // [CallsTab] TODO: Localize
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        return segmentedControl
    }()

    @objc
    private func tabChanged() {
        loadCallRecordsAnew()
        updateMultiselectToolbarButtons()
    }

    private var currentFilterMode: FilterMode {
        FilterMode(rawValue: tabPicker.selectedSegmentIndex) ?? .all
    }

    // MARK: - Call Record Loading

    /// Loads call records that we convert to ``CallViewModel``s. Configured on
    /// init with the current UI state of this view, e.g. filter mode and/or
    /// search term.
    private var callRecordLoader: CallRecordLoader!

    /// Recreates ``callRecordLoader`` with the current UI state, and kicks off
    /// an initial load.
    private func loadCallRecordsAnew() {
        AssertIsOnMainThread()

        let onlyLoadMissedCalls: Bool = {
            switch currentFilterMode {
            case .all: return false
            case .missed: return true
            }
        }()

        // Rebuild the loader.
        callRecordLoader = CallRecordLoader(
            callRecordQuerier: deps.callRecordQuerier,
            fullTextSearchFinder: deps.fullTextSearchFinder,
            configuration: CallRecordLoader.Configuration(
                onlyLoadMissedCalls: onlyLoadMissedCalls,
                searchTerm: searchTerm
            )
        )

        // Load the initial page of records.
        loadMoreCalls(direction: .older)
    }

    /// Load more calls and add them to the table.
    private func loadMoreCalls(direction: CallRecordLoader.LoadDirection) {
        deps.db.read { tx in
            _ = callRecordLoader.loadCallRecords(
                loadDirection: direction,
                tx: tx.asV2Read
            )

            calls = callRecordLoader.loadedCallRecords.map { callRecord -> CallViewModel in
                createCallViewModel(callRecord: callRecord, tx: tx)
            }
        }

        updateSnapshot()
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

        let callId = callRecord.callId

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
            let currentCallId: UInt64? = {
                guard let currentCall = deps.callService.currentCall else { return nil }

                switch currentCall.mode {
                case .individual(let individualCall):
                    return individualCall.callId
                case .group(let groupCall):
                    return groupCall.peekInfo?.eraId.map { callIdFromEra($0) }
                }
            }()

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

            return .ended(callStartedAt: callRecord.callBeganAtDate)
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
                callId: callId,
                title: deps.contactsManager.displayName(
                    for: contactThread.contactAddress,
                    transaction: tx
                ),
                recipientType: .individual(
                    type: callType,
                    contactThread: contactThread
                ),
                direction: callDirection,
                state: callState
            )
        } else if let groupThread = callThread as? TSGroupThread {
            return CallViewModel(
                callId: callId,
                title: groupThread.groupModel.groupNameOrDefault,
                recipientType: .group(groupThread: groupThread),
                direction: callDirection,
                state: callState
            )
        } else {
            owsFail("Call thread was neither contact nor group! This should be impossible.")
        }
    }

    // MARK: - Table view

    enum Section: Hashable {
        case primary
    }

    struct CallViewModel: Hashable, Identifiable {
        enum Direction: Hashable {
            case outgoing
            case incoming
            case missed

            var label: String {
                switch self {
                case .outgoing:
                    return "Outgoing" // [CallsTab] TODO: Localize
                case .incoming:
                    return "Incoming" // [CallsTab] TODO: Localize
                case .missed:
                    return "Missed" // [CallsTab] TODO: Localize
                }
            }
        }

        enum State: Hashable {
            /// This call is active, but the user is not in it.
            case active
            /// The user is currently in this call.
            case participating
            /// The call is no longer active.
            case ended(callStartedAt: Date)
        }

        enum RecipientType: Hashable {
            case individual(type: CallType, contactThread: TSContactThread)
            case group(groupThread: TSGroupThread)

            enum CallType: Hashable {
                case audio
                case video
            }
        }

        var callId: ID
        var title: String
        var recipientType: RecipientType
        var direction: Direction
        var image: UIImage?
        var state: State

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

        // MARK: Identifiable

        typealias ID = UInt64
        var id: UInt64 { callId }
    }

    let tableView = UITableView(frame: .zero, style: .plain)

    /// - Important
    /// Don't use this directly – use ``searchTerm``.
    private var _searchTerm: String? {
        didSet {
            guard oldValue != searchTerm else {
                // If the term hasn't changed, don't do anything.
                return
            }

            loadCallRecordsAnew()
        }
    }

    /// The user's current search term. Coalesces empty strings into `nil`.
    private var searchTerm: String? {
        get { _searchTerm?.nilIfEmpty }
        set { _searchTerm = newValue?.nilIfEmpty }
    }

    /// Ordered list of all call view models that might be displayed.
    private var calls: [CallViewModel] = [] {
        didSet {
            callViewModelsByID = Dictionary(
                calls.map { callViewModel in (callViewModel.id, callViewModel) },
                uniquingKeysWith: { _, new in new }
            )
        }
    }

    /// The view model for a given call ID.
    private var callViewModelsByID = [CallViewModel.ID: CallViewModel]()

    private static var callCellReuseIdentifier = "callCell"

    private lazy var dataSource = UITableViewDiffableDataSource<Section, CallViewModel.ID>(tableView: tableView) { [weak self] tableView, indexPath, modelID -> UITableViewCell? in
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.callCellReuseIdentifier)

        guard let callCell = cell as? CallCell else {
            owsFail("Unexpected cell type")
        }

        callCell.delegate = self
        callCell.viewModel = self?.callViewModelsByID[modelID]

        return callCell
    }

    private func getSnapshot() -> Snapshot {
        var snapshot = Snapshot()
        snapshot.appendSections([.primary])
        snapshot.appendItems(calls.map(\.id))
        return snapshot
    }

    // [CallsTab] TODO: Rename to something like "reload table"?
    private func updateSnapshot() {
        dataSource.apply(getSnapshot())
        updateEmptyStateMessage()
    }

    private func reloadAllRows() {
        var snapshot = getSnapshot()
        snapshot.reloadSections([.primary])
        dataSource.apply(snapshot)
    }

    private func updateEmptyStateMessage() {
        switch (calls.count, searchTerm) {
        case (0, .some(let searchTerm)) where !searchTerm.isEmpty:
            noSearchResultsView.text = "No results found for '\(searchTerm)'" // [CallsTab] TODO: Localize
            noSearchResultsView.layer.opacity = 1
            emptyStateMessageView.layer.opacity = 0
        case (0, _):
            emptyStateMessageView.attributedText = NSAttributedString.composed(of: {
                switch currentFilterMode {
                case .all:
                    return [
                        "No recent calls", // [CallsTab] TODO: Localize
                        "\n",
                        "Get started by calling a friend" // [CallsTab] TODO: Localize
                            .styled(with: .font(.dynamicTypeSubheadline)),
                    ]
                case .missed:
                    return [
                        "No missed calls" // [CallsTab] TODO: Localize
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

// MARK: UITableViewDelegate

extension CallsListViewController: UITableViewDelegate {

    private func viewModel(forRowAt indexPath: IndexPath) -> CallViewModel? {
        return calls[safe: indexPath.row]
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row == calls.count - 1 {
            // Try and load the next page if we're about to hit the bottom.
            DispatchQueue.main.async {
                self.loadMoreCalls(direction: .older)
            }
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            updateMultiselectToolbarButtons()
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)

        guard let viewModel = viewModel(forRowAt: indexPath) else {
            return owsFailDebug("Missing view model")
        }
        callBack(from: viewModel)
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            updateMultiselectToolbarButtons()
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        return self.longPressActions(forRowAt: indexPath)
            .map { actions in UIMenu.init(children: actions) }
            .map { menu in
                UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { _ in menu }
            }
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let viewModel = viewModel(forRowAt: indexPath) else {
            owsFailDebug("Missing call view model")
            return nil
        }

        let goToChatAction = makeContextualAction(
            style: .normal,
            color: .ows_accentBlue,
            image: "arrow-square-upright-fill",
            title: "Go to Chat" // [CallsTab] TODO: Localize
        ) { [weak self] in
            self?.goToChat(from: viewModel)
        }

        return .init(actions: [goToChatAction])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let viewModel = viewModel(forRowAt: indexPath) else {
            owsFailDebug("Missing call view model")
            return nil
        }

        let deleteAction = makeContextualAction(
            style: .destructive,
            color: .ows_accentRed,
            image: "trash-fill",
            title: CommonStrings.deleteButton
        ) { [weak self] in
            self?.deleteCall(from: viewModel)
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
        guard let viewModel = viewModel(forRowAt: indexPath) else {
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
                joinCallTitle = "Join Audio Call" // [CallsTab] TODO: Localize
                joinCallIconName = Theme.iconName(.contextMenuVoiceCall)
            case .video:
                joinCallTitle = "Join Video Call" // [CallsTab] TODO: Localize
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
                title: "Return to Call", // [CallsTab] TODO: Localize
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
                    title: "Audio Call", // [CallsTab] TODO: Localize
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
                title: "Video Call", // [CallsTab] TODO: Localize
                image: Theme.iconImage(.contextMenuVideoCall),
                attributes: []
            ) { [weak self] _ in
                self?.startVideoCall(from: viewModel)
            }
            actions.append(videoCallAction)
        }

        let goToChatAction = UIAction(
            title: "Go to Chat", // [CallsTab] TODO: Localize
            image: Theme.iconImage(.contextMenuOpenInChat),
            attributes: []
        ) { [weak self] _ in
            self?.goToChat(from: viewModel)
        }
        actions.append(goToChatAction)

        let infoAction = UIAction(
            title: "Info", // [CallsTab] TODO: Localize
            image: Theme.iconImage(.contextMenuInfo),
            attributes: []
        ) { [weak self] _ in
            self?.showCallInfo(from: viewModel)
        }
        actions.append(infoAction)

        let selectAction = UIAction(
            title: "Select", // [CallsTab] TODO: Localize
            image: Theme.iconImage(.contextMenuSelect),
            attributes: []
        ) { [weak self] _ in
            self?.selectCall(forRowAt: indexPath)
        }
        actions.append(selectAction)

        switch viewModel.state {
        case .active, .ended:
            let deleteAction = UIAction(
                title: "Delete", // [CallsTab] TODO: Localize
                image: Theme.iconImage(.contextMenuDelete),
                attributes: .destructive
            ) { [weak self] _ in
                self?.deleteCall(from: viewModel)
            }
            actions.append(deleteAction)
        case .participating:
            break
        }

        return actions
    }
}

// MARK: - Actions

extension CallsListViewController: CallCellDelegate {

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
        case let .group(groupThread):
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
        SignalApp.shared.presentConversationForThread(viewModel.thread, action: .compose, animated: false)
    }

    private func deleteCall(from viewModel: CallViewModel) {
        Logger.debug("Delete call")
    }

    private func selectCall(forRowAt indexPath: IndexPath) {
        startMultiselect()
        tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
    }

    // MARK: CallCellDelegate

    fileprivate func joinCall(from viewModel: CallViewModel) {
        Logger.debug("Join call")
    }

    fileprivate func returnToCall(from viewModel: CallViewModel) {
        Logger.debug("Return to call")
    }

    fileprivate func showCallInfo(from viewModel: CallViewModel) {
        Logger.debug("Show call info")
    }
}

// MARK: UISearchResultsUpdating

extension CallsListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        self.searchTerm = searchController.searchBar.text
    }
}

// MARK: - Call cell

extension CallsListViewController {
    fileprivate class CallCell: UITableViewCell {

        private static var verticalMargin: CGFloat = 11
        private static var horizontalMargin: CGFloat = 20
        private static var joinButtonMargin: CGFloat = 18
        // [CallsTab] TODO: Dynamic type?
        private static var subtitleIconSize: CGFloat = 16

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

        private lazy var subtitleIcon: UIImageView = UIImageView()
        private lazy var subtitleLabel: UILabel = {
            let label = UILabel()
            label.font = .dynamicTypeBody2
            return label
        }()

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

            let icon: UIImage?
            switch viewModel.callType {
            case .audio:
                icon = Theme.iconImage(.phoneFill16)
            case .video:
                icon = Theme.iconImage(.videoFill16)
            }

            let text: String
            switch viewModel.state {
            case .active:
                text = "Join" // [CallsTab] TODO: Localize
            case .participating:
                text = "Return" // [CallsTab] TODO: Localize
            case .ended:
                return nil
            }

            let iconView = UIImageView(image: icon)
            iconView.tintColor = .ows_white

            let label = UILabel()
            label.text = text
            label.font = .dynamicTypeBody2Clamped.bold()
            label.textColor = .ows_white

            let stackView = UIStackView(arrangedSubviews: [iconView, label])
            stackView.addPillBackgroundView(backgroundColor: .ows_accentGreen)
            stackView.layoutMargins = .init(hMargin: 12, vMargin: 4)
            stackView.isLayoutMarginsRelativeArrangement = true
            stackView.isUserInteractionEnabled = false
            stackView.spacing = 4
            return stackView
        }

        // MARK: Init

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)

            let subtitleHStack = UIStackView(arrangedSubviews: [subtitleIcon, subtitleLabel])
            subtitleHStack.axis = .horizontal
            subtitleHStack.spacing = 6
            subtitleIcon.autoSetDimensions(to: .square(Self.subtitleIconSize))

            let bodyVStack = UIStackView(arrangedSubviews: [
                titleLabel,
                subtitleHStack,
            ])
            bodyVStack.axis = .vertical
            bodyVStack.spacing = 2

            let leadingHStack = UIStackView(arrangedSubviews: [
                avatarView,
                bodyVStack,
            ])
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
            self.subtitleLabel.text = viewModel.direction.label

            switch viewModel.direction {
            case .incoming, .outgoing:
                titleLabel.textColor = Theme.primaryTextColor
            case .missed:
                titleLabel.textColor = .ows_accentRed
            }

            switch viewModel.callType {
            case .audio:
                subtitleIcon.image = Theme.iconImage(.phone16)
            case .video:
                subtitleIcon.image = Theme.iconImage(.video16)
            }

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

                timestampLabel.text = nil
            case .ended(let callBeganAtDate):
                // Info button
                detailsButton.setImage(imageName: "info")
                detailsButton.tintColor = Theme.primaryIconColor

                timestampLabel.text = DateUtil.formatDateShort(callBeganAtDate)
                // [CallsTab] TODO: Automatic updates
                // See ChatListCell.nextUpdateTimestamp
            }
        }

        private func applyTheme() {
            backgroundColor = Theme.backgroundColor
            selectedBackgroundView?.backgroundColor = Theme.tableCell2SelectedBackgroundColor
            multipleSelectionBackgroundView?.backgroundColor = Theme.tableCell2MultiSelectedBackgroundColor

            titleLabel.textColor = Theme.primaryTextColor
            subtitleIcon.tintColor = Theme.secondaryTextAndIconColor
            subtitleLabel.textColor = Theme.secondaryTextAndIconColor
            timestampLabel.textColor = Theme.secondaryTextAndIconColor
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

// MARK: -

private extension CallRecord {
    var callBeganAtDate: Date {
        Date(millisecondsSince1970: callBeganTimestamp)
    }
}
