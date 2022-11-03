//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalServiceKit

protocol StoryListDataSourceDelegate: AnyObject {

    // If null, will still load data but won't update the tableview.
    var tableViewIfLoaded: UITableView? { get }

    func tableViewDidUpdate()
}

class StoryListDataSource: NSObject, Dependencies {

    private let loadingQueue = DispatchQueue(label: "StoryListDataSource.loadingQueue", qos: .userInitiated)

    private lazy var syncingModels = SyncingStoryListViewModel(loadingQueue: loadingQueue)

    private var tableView: UITableView? {
        return delegate?.tableViewIfLoaded
    }

    private weak var delegate: StoryListDataSourceDelegate?

    init(delegate: StoryListDataSourceDelegate) {
        self.delegate = delegate
        super.init()
    }

    enum Section: Int {
        case myStory = 0
        case visibleStories = 1
        case hiddenStories = 2
    }

    // MARK: - Getting Data

    var isEmpty: Bool {
        return allStories.isEmpty && (myStory?.messages.isEmpty ?? true)
    }

    var myStory: MyStoryViewModel? {
        return syncingModels.exposedModel.myStory
    }

    var allStories: [StoryViewModel] {
        return syncingModels.exposedModel.unfilteredStories
    }

    var visibleStories: [StoryViewModel] {
        return syncingModels.exposedModel.stories.filter(\.isHidden.negated)
    }

    var hiddenStories: [StoryViewModel] {
        return syncingModels.exposedModel.stories.filter(\.isHidden)
    }

    var threadSafeStoryContexts: [StoryContext] {
        return syncingModels.threadSafeStoryContexts
    }

    var threadSafeVisibleStoryContexts: [StoryContext] {
        return syncingModels.threadSafeVisibleStoryContexts
    }

    var threadSafeHiddenStoryContexts: [StoryContext] {
        return syncingModels.threadSafeHiddenStoryContexts
    }

    public var shouldDisplayMyStory: Bool {
        return syncingModels.exposedModel.shouldDisplayMyStory
    }

    public var shouldDisplayHiddenStoriesHeader: Bool {
        return syncingModels.exposedModel.shouldDisplayHiddenStoriesHeader
    }

    public var isHiddenStoriesSectionCollapsed: Bool {
        get {
            return syncingModels.exposedModel.isHiddenStoriesSectionCollapsed
        }
        set {
            updateStories(isHiddenStorySectionCollapsed: newValue)
        }
    }

    public var shouldDisplayHiddenStories: Bool {
        return syncingModels.exposedModel.shouldDisplayHiddenStories
    }

    public func setSearchText(_ text: String?) {
        updateStoriesForSearchText(text)
    }

    // MARK: - Reload

    func reloadStories() {
        loadingQueue.async {
            self.syncingModels.mutate { oldModel -> StoryChanges? in
                let (listStories, myStoryModel) = Self.databaseStorage.read { transaction -> ([StoryViewModel], MyStoryViewModel) in
                    let storiesForList = StoryFinder.storiesForListView(transaction: transaction)
                    let groupedMessages = Dictionary(grouping: storiesForList) { $0.context }
                    let storyListModels = groupedMessages.compactMap { _, messages -> StoryViewModel? in
                        return try? StoryViewModel(messages: messages, transaction: transaction)
                    }
                    let outgoingStories = StoryFinder.outgoingStories(transaction: transaction)
                    let myStoryModel = MyStoryViewModel(messages: outgoingStories, transaction: transaction)

                    return (storyListModels, myStoryModel)
                }
                let newModel = StoryListViewModel(
                    myStory: myStoryModel,
                    stories: listStories.sorted(by: Self.sortStoryModels),
                    searchText: oldModel.searchText,
                    isHiddenStoriesSectionCollapsed: oldModel.isHiddenStoriesSectionCollapsed
                )
                // Note everything but the new model gets ignored since we reload data
                // rather than apply individual row updates.
                return StoryChanges(
                    oldModel: oldModel,
                    newModel: newModel,
                    visibleStoryUpdates: [], // is ignored
                    hiddenStoryUpdates: [], // is ignored
                    myStoryChanged: true // is ignored
                )
            } sync: { _ in
                self.tableView?.reloadData()
                self.observeAssociatedDataChangesForAvailableModels()
                self.delegate?.tableViewDidUpdate()
            }
        }
    }

    // MARK: - Partial Update

    private func updateStories(forRowIds rowIds: Set<Int64>) {
        guard !rowIds.isEmpty else { return }

        updateStories { oldModel in
            do {
                let changes = try self.buildBatchUpdates(
                    oldViewModel: oldModel,
                    changedMessageRowIds: rowIds
                )
                return changes
            } catch {
                owsFailDebug("Failed to build new models, hard reloading: \(error)")
                return nil
            }
        }
    }

    private func updateStories(changedHiddenStateContexts: Set<StoryContext>) {
        guard !changedHiddenStateContexts.isEmpty else { return }

        updateStories { oldModel in
            do {
                var changedContextsDict = [StoryContext: StoryContextChanges]()
                changedHiddenStateContexts.forEach {
                    changedContextsDict[$0] = .hiddenStateChanged
                }

                let changes = try self.buildBatchUpdates(
                    oldViewModel: oldModel,
                    changedContexts: changedContextsDict,
                    deletedRowIds: .init(),
                    myStoryModel: nil
                )
                return changes
            } catch {
                owsFailDebug("Failed to build new models, hard reloading: \(error)")
                return nil
            }
        }
    }

    private func updateStories(isHiddenStorySectionCollapsed: Bool) {
        updateStories { oldModel in
            let newModel = oldModel.copy(isHiddenStoriesSectionCollapsed: isHiddenStorySectionCollapsed)
            return StoryChanges(
                oldModel: oldModel,
                newModel: newModel,
                visibleStoryUpdates: [],
                hiddenStoryUpdates: [],
                myStoryChanged: false
            )
        }
    }

    private func updateStoriesForSearchText(_ searchText: String?) {
        loadingQueue.async {
            self.syncingModels.mutate { oldModel -> StoryChanges? in
                let newModel = StoryListViewModel(
                    myStory: oldModel.myStory,
                    stories: oldModel.unfilteredStories,
                    searchText: searchText,
                    isHiddenStoriesSectionCollapsed: oldModel.isHiddenStoriesSectionCollapsed
                )
                // Note everything but the new model gets ignored since we reload data
                // rather than apply individual row updates.
                return StoryChanges(
                    oldModel: oldModel,
                    newModel: newModel,
                    visibleStoryUpdates: [], // is ignored
                    hiddenStoryUpdates: [], // is ignored
                    myStoryChanged: true // is ignored
                )
            } sync: { _ in
                self.tableView?.reloadData()
                self.observeAssociatedDataChangesForAvailableModels()
                self.delegate?.tableViewDidUpdate()
            }
        }
    }

    private func updateStories(_ mutate: @escaping (StoryListViewModel) -> StoryChanges?) {
        AssertIsOnMainThread()

        loadingQueue.async {
            let ok = self.syncingModels.mutate(
                mutate,
                sync: { (changes) in
                    self.applyChangesToTableView(changes)
                    self.observeAssociatedDataChangesForAvailableModels()
                }
            )

            if !ok {
                // If we encouter any errors, just hard reload everything.
                DispatchQueue.main.async { self.reloadStories() }
                return
            }
        }
    }

    // MARK: - Database Observation

    public func beginObservingDatabase() {
        Self.databaseStorage.appendDatabaseChangeDelegate(self)
        Self.systemStoryManager.addStateChangedObserver(self)
        // NOTE: hidden state lives on StoryContextAssociatedData, so we observe changes on that.
        // But we need to know which thread IDs to observe, so first we load messages and then
        // we begin observing the contexts those messages are a part of.
    }

    private var associatedDataObservation: DatabaseCancellable?
    private var observedAssociatedDataContexts = Set<StoryContextAssociatedData.SourceContext>()

    /// Observe the StoryContextAssociatedData(s) for the threads of the stories we are currently showing.
    /// Diffs against what we were already observing to avoid overhead.
    private func observeAssociatedDataChangesForAvailableModels() {
        let models = self.syncingModels.exposedModel.stories
        var associatedDataContexts = Set<StoryContextAssociatedData.SourceContext>()
        var contactUuids = Set<String>()
        var groupIds = Set<Data>()
        models.forEach {
            guard let associatedDataContext = $0.context.asAssociatedDataContext else { return }
            owsAssertDebug(!associatedDataContexts.contains(associatedDataContext), "Have two story models on the same context!")
            associatedDataContexts.insert(associatedDataContext)
            switch associatedDataContext {
            case .contact(let contactUuid):
                contactUuids.insert(contactUuid.uuidString)
            case .group(let groupId):
                groupIds.insert(groupId)
            }
        }

        if observedAssociatedDataContexts == associatedDataContexts {
            // We are already observing this set.
            return
        }
        observedAssociatedDataContexts = associatedDataContexts

        let observation = ValueObservation.tracking { db in
            try StoryContextAssociatedData
                .filter(
                    contactUuids.contains(Column(StoryContextAssociatedData.columnName(.contactUuid)))
                    || groupIds.contains(Column(StoryContextAssociatedData.columnName(.groupId)))
                )
                .fetchAll(db)
        }
        // Ignore the first emission that fires right away, we
        // want subsequent updates only.
        var hasEmitted = false
        associatedDataObservation?.cancel()
        associatedDataObservation = observation.start(
            in: databaseStorage.grdbStorage.pool,
            onError: { error in
                owsFailDebug("Failed to observe story hidden state: \(error))")
            }, onChange: { [weak self] changedModels in
                guard hasEmitted else {
                    hasEmitted = true
                    return
                }
                var changedContexts = Set<StoryContext>()
                changedModels
                    .lazy
                    .compactMap { [weak self] associatedData -> StoryContext? in
                        let context = associatedData.sourceContext.asStoryContext
                        guard
                            let storyModel = self?.syncingModels.exposedModel.stories.first(where: { context == $0.context }),
                            // If the hidden state didn't change, skip over this context.
                            storyModel.isHidden != associatedData.isHidden
                        else {
                            return nil
                        }
                        return context
                    }
                    .forEach {
                        changedContexts.insert($0)
                    }
                self?.updateStories(changedHiddenStateContexts: changedContexts)
            }
        )
    }

    // MARK: - Batch Updates

    private func buildBatchUpdates(
        oldViewModel: StoryListViewModel,
        changedMessageRowIds: Set<Int64>
    ) throws -> StoryChanges {
        let updatedListMessages = Self.databaseStorage.read {
            StoryFinder.listStoriesWithRowIds(Array(changedMessageRowIds), transaction: $0)
        }
        // If we see rows we thought updated but which don't exist anymore, that means they're deleted.
        let deletedRowIds = changedMessageRowIds.subtracting(updatedListMessages.lazy.map { $0.id! })

        // Group the freshly fetched messages by their context.
        // Some of these will be totally new, some will be updates to contexts we knew about.
        let changedContexts = Dictionary(grouping: updatedListMessages) {
            $0.context
        }.mapValues {
            StoryContextChanges.messagesChanged($0)
        }

        let myStoryModel = self.buildMyStoryModel(
            oldModel: oldViewModel,
            changedMessageRowIds: changedMessageRowIds
        )

        return try buildBatchUpdates(
            oldViewModel: oldViewModel,
            changedContexts: changedContexts,
            deletedRowIds: deletedRowIds,
            myStoryModel: myStoryModel
        )
    }

    private enum StoryContextChanges {
        case messagesChanged([StoryMessage])
        case hiddenStateChanged

        var changedMessages: [StoryMessage] {
            switch self {
            case .messagesChanged(let array):
                return array
            case .hiddenStateChanged:
                return []
            }
        }
    }

    private func buildBatchUpdates(
        oldViewModel: StoryListViewModel,
        changedContexts: [StoryContext: StoryContextChanges],
        deletedRowIds: Set<Int64>,
        myStoryModel: MyStoryViewModel?
    ) throws -> StoryChanges {
        // Some of these will be totally new, some will be updates to contexts we knew about.
        // Below we start removing contexts from here when we find them in the old model.
        var newContexts = changedContexts

        var deletedRowIds = deletedRowIds

        var changedVisibleContexts = [StoryContext]()
        var changedHiddenContexts = [StoryContext]()

        let newModels = try Self.databaseStorage.read { transaction -> [StoryViewModel] in
            let changedModels = try oldViewModel.unfilteredStories.compactMap { oldModel -> StoryViewModel? in
                guard let latestMessage = oldModel.messages.first else { return oldModel }

                let modelDeletedRowIds: [Int64] = oldModel.messages.lazy.compactMap(\.id).filter { deletedRowIds.contains($0) }
                deletedRowIds.subtract(modelDeletedRowIds)

                // Remove any contexts from the list of new contexts if we had them in the old models;
                // those are changes not new additions.
                let contextChanges = newContexts.removeValue(forKey: latestMessage.context)

                // Check if the hidden state has changed.
                let isHidden = oldModel.context.isHidden(transaction: transaction)
                let hiddenStateChanged = isHidden != oldModel.isHidden

                let hasChanges =
                    !modelDeletedRowIds.isEmpty
                    || contextChanges != nil
                    || hiddenStateChanged

                guard hasChanges else {
                    // If there are no changes, just return the model we have.
                    return oldModel
                }

                if isHidden {
                    changedHiddenContexts.append(oldModel.context)
                } else {
                    changedVisibleContexts.append(oldModel.context)
                }

                return try oldModel.copy(
                    updatedMessages: contextChanges?.changedMessages ?? [],
                    deletedMessageRowIds: modelDeletedRowIds,
                    isHidden: isHidden,
                    transaction: transaction
                )
            }
            // At this point all that remains is new contexts, any update ones got
            // removed when we looped over old models above.
            let modelsFromNewContexts = try newContexts.compactMap { (context: StoryContext, contextChanges: StoryContextChanges) throws -> StoryViewModel? in
                switch contextChanges {
                case .hiddenStateChanged:
                    // At this point, all remaining contexts are new (not in old models) but we should only
                    // be observing hidden changes for contexts we already knew about, so this should be impossible.
                    owsFailDebug("Got story hidden state changed for a previously-unknown context.")
                    return nil
                case .messagesChanged(let messages):
                    return try StoryViewModel(messages: messages, transaction: transaction)
                }
            }
            return changedModels + modelsFromNewContexts
        }.sorted(by: Self.sortStoryModels)

        let newIsHiddenStoriesSectionCollapsed: Bool
        if !oldViewModel.isHiddenStoriesSectionCollapsed {
            newIsHiddenStoriesSectionCollapsed = false
        } else if oldViewModel.unfilteredHiddenStories.isEmpty && newModels.contains(where: \.isHidden) {
            newIsHiddenStoriesSectionCollapsed = false
        } else {
            newIsHiddenStoriesSectionCollapsed = true
        }

        let newViewModel = StoryListViewModel(
            myStory: myStoryModel ?? oldViewModel.myStory,
            stories: newModels,
            searchText: oldViewModel.searchText,
            isHiddenStoriesSectionCollapsed: newIsHiddenStoriesSectionCollapsed
        )

        let visibleBatchUpdates = try BatchUpdate.build(
            viewType: .uiTableView,
            oldValues: oldViewModel.visibleStories.map(\.context),
            newValues: newViewModel.visibleStories.map(\.context),
            changedValues: changedVisibleContexts
        )
        let hiddenBatchUpdates = try BatchUpdate.build(
            viewType: .uiTableView,
            oldValues: oldViewModel.hiddenStories.map(\.context),
            newValues: newViewModel.hiddenStories.map(\.context),
            changedValues: changedHiddenContexts
        )

        return StoryChanges(
            oldModel: oldViewModel,
            newModel: newViewModel,
            visibleStoryUpdates: visibleBatchUpdates,
            hiddenStoryUpdates: hiddenBatchUpdates,
            myStoryChanged: myStoryModel != nil
        )
    }

    // Sort story models for display.
    // * We show unviewed stories first, sorted by their sent timestamp, with the most recently sent at the top
    //   * Any system story context with all its stories unviewed is always sorted at the top.
    // * We then show viewed stories, sorted by when they were viewed, with the most recently viewed at the top
    private static func sortStoryModels(lhs: StoryViewModel, rhs: StoryViewModel) -> Bool {
        if lhs.isSystemStory && lhs.messages.allSatisfy(\.isViewed.negated) {
            return true
        } else if rhs.isSystemStory && rhs.messages.allSatisfy(\.isViewed.negated) {
            return false
        } else if
            let lhsViewedTimestamp = lhs.latestMessageViewedTimestamp,
            let rhsViewedTimestamp = rhs.latestMessageViewedTimestamp
        {
            return lhsViewedTimestamp > rhsViewedTimestamp
        } else if lhs.latestMessageViewedTimestamp != nil {
            return false
        } else if rhs.latestMessageViewedTimestamp != nil {
            return true
        } else {
            return lhs.latestMessageTimestamp > rhs.latestMessageTimestamp
        }
    }

    // MARK: - My Story Updates

    /// Fetches my stories from the database, builds MyStoryModel, and returns it if there were any changes
    /// or nil if there were no changes.
    private func buildMyStoryModel(
        oldModel: StoryListViewModel,
        changedMessageRowIds: Set<Int64>
    ) -> MyStoryViewModel? {
        let oldStoryModel = oldModel.myStory
        let outgoingStories = Self.databaseStorage.read {
            StoryFinder.outgoingStories(transaction: $0)
        }
        let myStoryChanged = changedMessageRowIds.intersection(outgoingStories.map { $0.id! }).count > 0
            || Set(oldStoryModel?.messages.map { $0.uniqueId } ?? []) != Set(outgoingStories.map { $0.uniqueId })

        guard myStoryChanged else {
            return nil
        }
        return Self.databaseStorage.read { MyStoryViewModel(messages: outgoingStories, transaction: $0) }
    }

    // MARK: - Applying updates to TableView

    private func applyChangesToTableView(_ changes: StoryChanges) {
        guard let tableView = tableView else {
            return
        }

        tableView.beginUpdates()
        defer {
            tableView.endUpdates()
            self.delegate?.tableViewDidUpdate()
        }

        if !changes.oldModel.shouldDisplayMyStory, changes.newModel.shouldDisplayMyStory {
            tableView.insertRows(at: [IndexPath(row: 0, section: Section.myStory.rawValue)], with: .fade)
        } else if changes.oldModel.shouldDisplayMyStory, !changes.newModel.shouldDisplayMyStory {
            tableView.deleteRows(at: [IndexPath(row: 0, section: Section.myStory.rawValue)], with: .fade)
        } else if changes.myStoryChanged, changes.newModel.shouldDisplayMyStory {
            tableView.reloadRows(at: [IndexPath(row: 0, section: Section.myStory.rawValue)], with: .fade)
        }

        // Visible stories section is always visible, directly apply changes.
        applyTableViewBatchUpdates(changes.visibleStoryUpdates, toSection: .visibleStories, models: changes.newModel.visibleStories)

        applyHiddenStoryUpdates(changes)
    }

    /// Hidden stories section can be expanded and collapsed, so here we handle that as well as changes to the actual contents.
    private func applyHiddenStoryUpdates(_ changes: StoryChanges) {
        guard let tableView = tableView else {
            return
        }

        // Header
        switch (changes.oldModel.shouldDisplayHiddenStoriesHeader, changes.newModel.shouldDisplayHiddenStoriesHeader) {

        case (false, false):
            // No need to do anything.
            break

        case (true, true):
            // Just reload the header row if we have to.
            if changes.oldModel.isHiddenStoriesSectionCollapsed != changes.newModel.isHiddenStoriesSectionCollapsed {
                // If the cell is visible, reconfigure it directly without reloading.
                let path = IndexPath(row: 0, section: Section.hiddenStories.rawValue)
                if
                    (tableView.indexPathsForVisibleRows ?? []).contains(path),
                    let visibleCell = tableView.cellForRow(at: path) as? HiddenStoryHeaderCell
                {
                    visibleCell.configure(isCollapsed: changes.newModel.isHiddenStoriesSectionCollapsed)
                } else {
                    tableView.reloadRows(at: [path], with: .none)
                }
            }

        case (false, true):
            tableView.insertRows(at: [IndexPath(row: 0, section: Section.hiddenStories.rawValue)], with: .fade)
        case (true, false):
            tableView.deleteRows(at: [IndexPath(row: 0, section: Section.hiddenStories.rawValue)], with: .fade)
        }

        // Offset by 1 to account for the header cell.
        let oldHeaderOffset = changes.oldModel.shouldDisplayHiddenStoriesHeader ? 1 : 0
        let newHeaderOffset = changes.newModel.shouldDisplayHiddenStoriesHeader ? 1 : 0

        switch (changes.oldModel.shouldDisplayHiddenStories, changes.newModel.shouldDisplayHiddenStories) {

        case (true, true):
            // Update the hidden section, it was shown before and after
            applyTableViewBatchUpdates(
                changes.hiddenStoryUpdates.map {
                    switch $0.updateType {
                    case let .update(oldIndex, newIndex):
                        return .init(
                            value: $0.value,
                            updateType: .update(
                                oldIndex: oldIndex + oldHeaderOffset,
                                newIndex: newIndex + newHeaderOffset
                            )
                        )
                    case let .move(oldIndex, newIndex):
                        return .init(
                            value: $0.value,
                            updateType: .move(
                                oldIndex: oldIndex + oldHeaderOffset,
                                newIndex: newIndex + newHeaderOffset
                            )
                        )
                    case let .insert(newIndex):
                        return .init(
                            value: $0.value,
                            updateType: .insert(
                                newIndex: newIndex + newHeaderOffset
                            )
                        )
                    case let .delete(oldIndex):
                        return .init(
                            value: $0.value,
                            updateType: .delete(
                                oldIndex: oldIndex + oldHeaderOffset
                            )
                        )
                    }
                },
                toSection: .hiddenStories,
                models: [changes.newModel.hiddenStories.first].compactMap({
                    changes.newModel.shouldDisplayHiddenStoriesHeader ? $0 : nil
                }) + changes.newModel.hiddenStories
            )

        case (false, true):
            // Was hidden and is now shown, reload.
            applyTableViewBatchUpdates(
                changes.newModel.hiddenStories.lazy.enumerated().map {
                    return .init(value: $1.context, updateType: .insert(newIndex: $0 + newHeaderOffset))
                },
                toSection: .hiddenStories,
                models: changes.newModel.hiddenStories
            )

        case (true, false):
            // Was shown and is now hidden, everything counts as a delete.
            applyTableViewBatchUpdates(
                changes.oldModel.hiddenStories.lazy.enumerated().map {
                    return .init(value: $1.context, updateType: .delete(oldIndex: $0 + oldHeaderOffset))
                },
                toSection: .hiddenStories,
                models: changes.oldModel.hiddenStories
            )

        case (false, false):
            // Was hidden and is hidden, so can just ignore any updates.
            break
        }
    }

    /// Apply batch updates to a section of the table view.
    private func applyTableViewBatchUpdates(
        _ updates: [BatchUpdate<StoryContext>.Item],
        toSection section: Section,
        models: [StoryViewModel]
    ) {
        guard let tableView = tableView else {
            return
        }

        for update in updates {
            switch update.updateType {
            case .delete(let oldIndex):
                tableView.deleteRows(at: [IndexPath(row: oldIndex, section: section.rawValue)], with: .fade)
            case .insert(let newIndex):
                tableView.insertRows(at: [IndexPath(row: newIndex, section: section.rawValue)], with: .fade)
            case .move(let oldIndex, let newIndex):
                tableView.deleteRows(at: [IndexPath(row: oldIndex, section: section.rawValue)], with: .fade)
                tableView.insertRows(at: [IndexPath(row: newIndex, section: section.rawValue)], with: .fade)
            case .update(let oldIndex, let newIndex):
                // If the cell is visible, reconfigure it directly without reloading.
                let path = IndexPath(row: oldIndex, section: section.rawValue)
                if
                    (tableView.indexPathsForVisibleRows ?? []).contains(path),
                    let visibleCell = tableView.cellForRow(at: path) as? StoryCell
                {
                    guard let model = models[safe: newIndex] else {
                        return owsFailDebug("Missing model for story")
                    }
                    visibleCell.configure(with: model)
                } else {
                    tableView.reloadRows(at: [path], with: .none)
                }
            }
        }
    }
}

extension StoryListDataSource: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        updateStories(forRowIds: databaseChanges.storyMessageRowIds)
    }

    func databaseChangesDidUpdateExternally() {
        reloadStories()
    }

    func databaseChangesDidReset() {
        reloadStories()
    }
}

extension StoryListDataSource: SystemStoryStateChangeObserver {

    func systemStoryHiddenStateDidChange(rowIds: [Int64]) {
        updateStories(forRowIds: Set(rowIds))
    }
}

// MARK: - SyncingStoryListViewModel

private class SyncingStoryListViewModel {

    private let loadingQueue: DispatchQueue

    // This is always the most up-to-date collection of models.
    private lazy var trueModel = ThreadBoundValue(wrappedValue: StoryListViewModel.empty, queue: loadingQueue)

    // This may lag behind `trueModel` and is eventually consistent. It is exposed to UITableView.
    @ThreadBoundValue(wrappedValue: .empty, queue: .main)
    private(set) var exposedModel: StoryListViewModel

    // These are held separately so they can be accessed off the main thread, which happens with some
    // callbacks in the story viewer.
    private var _threadSafeStoryContexts = AtomicArray<StoryContext>()

    private var _threadSafeVisibleStoryContexts = AtomicArray<StoryContext>()
    private var _threadSafeHiddenStoryContexts = AtomicArray<StoryContext>()

    init(loadingQueue: DispatchQueue) {
        self.loadingQueue = loadingQueue
    }

    /// Safely modify the list of models. This method must be called on the loading queue.
    ///
    /// - Parameters
    ///   - closure: Called synchronously. Returns nil to abort mutation without side-effects. Otherwise, it returns the new values for the models array and user data to pass to `sync`.
    ///   - models: The existing array of models.
    ///   - sync: Runs asynchronously on the main queue after `closure` returns.
    ///   - changes: The changes applied by `closure`.
    ///
    /// - Returns whether the closure returned a nonnil list of models.
    @discardableResult
    func mutate(
        _ closure: (_ models: StoryListViewModel) -> StoryChanges?,
        sync: @escaping (StoryChanges) -> Void
    ) -> Bool {
        dispatchPrecondition(condition: .onQueue(loadingQueue))

        guard let changes = closure(trueModel.wrappedValue) else {
            return false
        }
        trueModel.wrappedValue = changes.newModel
        DispatchQueue.main.async {
            self._threadSafeStoryContexts.set(changes.newModel.stories.map(\.context))
            self._threadSafeVisibleStoryContexts.set(changes.newModel.stories.lazy.filter(\.isHidden.negated).map(\.context))
            self._threadSafeHiddenStoryContexts.set(changes.newModel.stories.lazy.filter(\.isHidden).map(\.context))
            self.exposedModel = changes.newModel
            sync(changes)
        }

        return true
    }

    var threadSafeStoryContexts: [StoryContext] { _threadSafeStoryContexts.get() }
    var threadSafeVisibleStoryContexts: [StoryContext] { _threadSafeVisibleStoryContexts.get() }
    var threadSafeHiddenStoryContexts: [StoryContext] { _threadSafeHiddenStoryContexts.get() }
}

// MARK: - StoryContexts

// MARK: - View Model

/// Pre-computed array partitions into hidden/visible and their contexts
/// so we have fixed ordering and don't recompute on the fly.
private struct StoryListViewModel {

    let myStory: MyStoryViewModel?
    let unfilteredStories: [StoryViewModel]
    let searchText: String?
    let isHiddenStoriesSectionCollapsed: Bool

    let stories: [StoryViewModel]

    init(
        myStory: MyStoryViewModel?,
        stories: [StoryViewModel],
        searchText: String?,
        isHiddenStoriesSectionCollapsed: Bool
    ) {
        self.myStory = myStory
        self.unfilteredStories = stories
        self.searchText = searchText
        self.isHiddenStoriesSectionCollapsed = isHiddenStoriesSectionCollapsed

        self.stories = {
            guard let searchText = searchText else {
                return stories
            }
            return stories.filter {
                $0.latestMessageName.localizedCaseInsensitiveContains(searchText)
            }
        }()
    }

    static var empty: Self {
        return .init(myStory: nil, stories: [], searchText: nil, isHiddenStoriesSectionCollapsed: true)
    }

    func copy(isHiddenStoriesSectionCollapsed: Bool) -> Self {
        return  .init(
            myStory: myStory,
            stories: unfilteredStories,
            searchText: searchText,
            isHiddenStoriesSectionCollapsed: isHiddenStoriesSectionCollapsed
        )
    }

    var shouldDisplayMyStory: Bool {
        return myStory != nil && searchText.isEmptyOrNil
    }

    var visibleStories: [StoryViewModel] {
        return stories.lazy.filter(\.isHidden.negated)
    }

    // MARK: Hidden stories

    var hiddenStories: [StoryViewModel] {
        return stories.lazy.filter(\.isHidden)
    }

    var unfilteredHiddenStories: [StoryViewModel] {
        return unfilteredStories.lazy.filter(\.isHidden)
    }

    var shouldDisplayHiddenStoriesHeader: Bool {
        return !hiddenStories.isEmpty && searchText.isEmptyOrNil
    }

    var shouldDisplayHiddenStories: Bool {
        if shouldDisplayHiddenStoriesHeader {
            return !isHiddenStoriesSectionCollapsed
        } else {
            return !hiddenStories.isEmpty
        }
    }
}

/// Encapsulates a set of changes to be applied when story list state changes.
private struct StoryChanges {
    let oldModel: StoryListViewModel
    let newModel: StoryListViewModel
    let visibleStoryUpdates: [BatchUpdate<StoryContext>.Item]
    let hiddenStoryUpdates: [BatchUpdate<StoryContext>.Item]
    let myStoryChanged: Bool
}

// MARK: - Thread Safe Wrapper

@propertyWrapper
struct ThreadBoundValue<T> {
    private var value: T
    private var queue: DispatchQueue

    var wrappedValue: T {
        get {
            dispatchPrecondition(condition: .onQueue(queue))
            return value
        }
        set {
            dispatchPrecondition(condition: .onQueue(queue))
            value = newValue
        }
    }

    init(wrappedValue: T, queue: DispatchQueue) {
        self.value = wrappedValue
        self.queue = queue
    }
}
