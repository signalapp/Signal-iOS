// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

// MARK: - PagedDatabaseObserver

/// This type manages observation and paging for the provided dataQuery
///
/// **Note:** We **MUST** have accurate `filterSQL` and `orderSQL` values otherwise the indexing won't work
public class PagedDatabaseObserver<ObservedTable, T>: TransactionObserver where ObservedTable: TableRecord & ColumnExpressible & Identifiable, T: FetchableRecordWithRowId & Identifiable {
    // MARK: - Variables
    
    private let pagedTableName: String
    private let idColumnName: String
    public var pageInfo: Atomic<PagedData.PageInfo>
    
    private let observedTableChangeTypes: [String: PagedData.ObservedChanges]
    private let allObservedTableNames: Set<String>
    private let observedInserts: Set<String>
    private let observedUpdateColumns: [String: Set<String>]
    private let observedDeletes: Set<String>
    
    private let joinSQL: SQL?
    private let filterSQL: SQL
    private let groupSQL: SQL?
    private let orderSQL: SQL
    private let dataQuery: ([Int64]) -> AdaptedFetchRequest<SQLRequest<T>>
    private let associatedRecords: [ErasedAssociatedRecord]
    
    private var dataCache: Atomic<DataCache<T>> = Atomic(DataCache())
    private var isLoadingMoreData: Atomic<Bool> = Atomic(false)
    private let changesInCommit: Atomic<Set<PagedData.TrackedChange>> = Atomic([])
    private let onChangeUnsorted: (([T], PagedData.PageInfo) -> ())
    
    // MARK: - Initialization
    
    public init(
        pagedTable: ObservedTable.Type,
        pageSize: Int,
        idColumn: ObservedTable.Columns,
        observedChanges: [PagedData.ObservedChanges],
        joinSQL: SQL? = nil,
        filterSQL: SQL,
        groupSQL: SQL? = nil,
        orderSQL: SQL,
        dataQuery: @escaping ([Int64]) -> AdaptedFetchRequest<SQLRequest<T>>,
        associatedRecords: [ErasedAssociatedRecord] = [],
        onChangeUnsorted: @escaping ([T], PagedData.PageInfo) -> ()
    ) {
        let associatedTables: Set<String> = associatedRecords.map { $0.databaseTableName }.asSet()
        assert(!associatedTables.contains(pagedTable.databaseTableName), "The paged table cannot also exist as an associatedRecord")
        
        self.pagedTableName = pagedTable.databaseTableName
        self.idColumnName = idColumn.name
        self.pageInfo = Atomic(PagedData.PageInfo(pageSize: pageSize))
        self.joinSQL = joinSQL
        self.filterSQL = filterSQL
        self.groupSQL = groupSQL
        self.orderSQL = orderSQL
        self.dataQuery = dataQuery
        self.associatedRecords = associatedRecords
            .map { $0.settingPagedTableName(pagedTableName: pagedTable.databaseTableName) }
        self.onChangeUnsorted = onChangeUnsorted
        
        // Combine the various observed changes into a single set
        self.observedTableChangeTypes = observedChanges
            .reduce(into: [:]) { result, next in result[next.databaseTableName] = next }
        let allObservedChanges: [PagedData.ObservedChanges] = observedChanges
            .appending(contentsOf: associatedRecords.flatMap { $0.observedChanges })
        self.allObservedTableNames = allObservedChanges
            .map { $0.databaseTableName }
            .asSet()
        self.observedInserts = allObservedChanges
            .filter { $0.events.contains(.insert) }
            .map { $0.databaseTableName }
            .asSet()
        self.observedUpdateColumns = allObservedChanges
            .filter { $0.events.contains(.update) }
            .reduce(into: [:]) { (prev: inout [String: Set<String>], next: PagedData.ObservedChanges) in
                guard !next.columns.isEmpty else { return }
                
                prev[next.databaseTableName] = next.columns.asSet()
            }
        self.observedDeletes = allObservedChanges
            .filter { $0.events.contains(.delete) }
            .map { $0.databaseTableName }
            .asSet()
    }
    
    // MARK: - TransactionObserver
    
    public func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        switch eventKind {
            case .insert(let tableName): return self.observedInserts.contains(tableName)
            case .delete(let tableName): return self.observedDeletes.contains(tableName)
            
            case .update(let tableName, let columnNames):
                return (self.observedUpdateColumns[tableName]?
                    .intersection(columnNames)
                    .isEmpty == false)
        }
    }
    
    public func databaseDidChange(with event: DatabaseEvent) {
        // This will get called whenever the `observes(eventsOfKind:)` returns
        // true and will include all changes which occurred in the commit so we
        // need to ignore any non-observed tables, unfortunately we also won't
        // know if the changes to observed tables are actually relevant yet as
        // changes only include table and column info at this stage
        guard allObservedTableNames.contains(event.tableName) else { return }
        
        // When generating the tracked change we need to check if the change was
        // a deletion to a related table (if so then once the change is performed
        // there won't be a way to associated the deleted related record to the
        // original so we need to retrieve the association in here)
        let trackedChange: PagedData.TrackedChange = {
            guard
                event.tableName != pagedTableName,
                event.kind == .delete,
                let observedChange: PagedData.ObservedChanges = observedTableChangeTypes[event.tableName],
                let joinToPagedType: SQL = observedChange.joinToPagedType
            else { return PagedData.TrackedChange(event: event) }
            
            // Retrieve the pagedRowId for the related value that is
            // getting deleted
            let pagedRowIds: [Int64] = Storage.shared
                .read { db in
                    PagedData.pagedRowIdsForRelatedRowIds(
                        db,
                        tableName: event.tableName,
                        pagedTableName: pagedTableName,
                        relatedRowIds: [event.rowID],
                        joinToPagedType: joinToPagedType
                    )
                }
                .defaulting(to: [])
            
            return PagedData.TrackedChange(event: event, pagedRowIdsForRelatedDeletion: pagedRowIds)
        }()
        
        // The 'event' object only exists during this method so we need to copy the info
        // from it, otherwise it will cease to exist after this metod call finishes
        changesInCommit.mutate { $0.insert(trackedChange) }
    }
    
    // Note: We will process all updates which come through this method even if
    // 'onChange' is null because if the UI stops observing and then starts again
    // later we don't want to have missed any changes which happened while the UI
    // wasn't subscribed (and doing a full re-query seems painful...)
    public func databaseDidCommit(_ db: Database) {
        var committedChanges: Set<PagedData.TrackedChange> = []
        self.changesInCommit.mutate { cachedChanges in
            committedChanges = cachedChanges
            cachedChanges.removeAll()
        }
        
        // Note: This method will be called regardless of whether there were actually changes
        // in the areas we are observing so we want to early-out if there aren't any relevant
        // updated rows
        guard !committedChanges.isEmpty else { return }
        
        let joinSQL: SQL? = self.joinSQL
        let orderSQL: SQL = self.orderSQL
        let filterSQL: SQL = self.filterSQL
        let associatedRecords: [ErasedAssociatedRecord] = self.associatedRecords
        
        let updateDataAndCallbackIfNeeded: (DataCache<T>, PagedData.PageInfo, Bool) -> () = { [weak self] updatedDataCache, updatedPageInfo, cacheHasChanges in
            let associatedDataInfo: [(hasChanges: Bool, data: ErasedAssociatedRecord)] = associatedRecords
                .map { associatedRecord in
                    let hasChanges: Bool = associatedRecord.tryUpdateForDatabaseCommit(
                        db,
                        changes: committedChanges,
                        joinSQL: joinSQL,
                        orderSQL: orderSQL,
                        filterSQL: filterSQL,
                        pageInfo: updatedPageInfo
                    )
                    
                    return (hasChanges, associatedRecord)
                }
            
            // Check if we need to trigger a change callback
            guard cacheHasChanges || associatedDataInfo.contains(where: { hasChanges, _ in hasChanges }) else {
                return
            }
            
            // If the associated data changed then update the updatedCachedData with the
            // updated associated data
            var finalUpdatedDataCache: DataCache<T> = updatedDataCache
            
            associatedDataInfo.forEach { hasChanges, associatedData in
                guard cacheHasChanges || hasChanges else { return }
                
                finalUpdatedDataCache = associatedData.updateAssociatedData(to: finalUpdatedDataCache)
            }
            
            // Update the cache, pageInfo and the change callback
            self?.dataCache.mutate { $0 = finalUpdatedDataCache }
            self?.pageInfo.mutate { $0 = updatedPageInfo }
            self?.onChangeUnsorted(finalUpdatedDataCache.values, updatedPageInfo)
        }
        
        // Determing if there were any direct or related data changes
        let directChanges: Set<PagedData.TrackedChange> = committedChanges
            .filter { $0.tableName == pagedTableName }
        let relatedChanges: [String: [PagedData.TrackedChange]] = committedChanges
            .filter { $0.tableName != pagedTableName }
            .filter { $0.kind != .delete }
            .reduce(into: [:]) { result, next in
                guard observedTableChangeTypes[next.tableName] != nil else { return }
                
                result[next.tableName] = (result[next.tableName] ?? []).appending(next)
            }
        let relatedDeletions: [PagedData.TrackedChange] = committedChanges
            .filter { $0.tableName != pagedTableName }
            .filter { $0.kind == .delete }
        
        guard !directChanges.isEmpty || !relatedChanges.isEmpty || !relatedDeletions.isEmpty else {
            updateDataAndCallbackIfNeeded(self.dataCache.wrappedValue, self.pageInfo.wrappedValue, false)
            return
        }
        
        var updatedPageInfo: PagedData.PageInfo = self.pageInfo.wrappedValue
        var updatedDataCache: DataCache<T> = self.dataCache.wrappedValue
        let deletionChanges: [Int64] = directChanges
            .filter { $0.kind == .delete }
            .map { $0.rowId }
        let oldDataCount: Int = dataCache.wrappedValue.count
        
        // First remove any items which have been deleted
        if !deletionChanges.isEmpty {
            updatedDataCache = updatedDataCache.deleting(rowIds: deletionChanges)
            
            // Make sure there were actually changes
            if updatedDataCache.count != oldDataCount {
                let dataSizeDiff: Int = (updatedDataCache.count - oldDataCount)
                
                updatedPageInfo = PagedData.PageInfo(
                    pageSize: updatedPageInfo.pageSize,
                    pageOffset: updatedPageInfo.pageOffset,
                    currentCount: (updatedPageInfo.currentCount + dataSizeDiff),
                    totalCount: (updatedPageInfo.totalCount + dataSizeDiff)
                )
            }
        }
        
        // If there are no inserted/updated rows then trigger the update callback and stop here
        let changesToQuery: [PagedData.TrackedChange] = directChanges
            .filter { $0.kind != .delete }
        
        guard !changesToQuery.isEmpty || !relatedChanges.isEmpty || !relatedDeletions.isEmpty else {
            updateDataAndCallbackIfNeeded(updatedDataCache, updatedPageInfo, !deletionChanges.isEmpty)
            return
        }
        
        // First we need to get the rowIds for the paged data connected to any of the related changes
        let pagedRowIdsForRelatedChanges: Set<Int64> = {
            guard !relatedChanges.isEmpty else { return [] }
            
            return relatedChanges
                .reduce(into: []) { result, next in
                    guard
                        let observedChange: PagedData.ObservedChanges = observedTableChangeTypes[next.key],
                        let joinToPagedType: SQL = observedChange.joinToPagedType
                    else { return }
                    
                    let pagedRowIds: [Int64] = PagedData.pagedRowIdsForRelatedRowIds(
                        db,
                        tableName: next.key,
                        pagedTableName: pagedTableName,
                        relatedRowIds: Array(next.value.map { $0.rowId }.asSet()),
                        joinToPagedType: joinToPagedType
                    )
                    
                    result.append(contentsOf: pagedRowIds)
                }
                .asSet()
        }()
        
        guard !changesToQuery.isEmpty || !pagedRowIdsForRelatedChanges.isEmpty || !relatedDeletions.isEmpty else {
            updateDataAndCallbackIfNeeded(updatedDataCache, updatedPageInfo, !deletionChanges.isEmpty)
            return
        }
        
        // Fetch the indexes of the rowIds so we can determine whether they should be added to the screen
        let directRowIds: Set<Int64> = changesToQuery.map { $0.rowId }.asSet()
        let pagedRowIdsForRelatedDeletions: Set<Int64> = relatedDeletions
            .compactMap { $0.pagedRowIdsForRelatedDeletion }
            .flatMap { $0 }
            .asSet()
        let itemIndexes: [PagedData.RowIndexInfo] = PagedData.indexes(
            db,
            rowIds: Array(directRowIds),
            tableName: pagedTableName,
            requiredJoinSQL: joinSQL,
            orderSQL: orderSQL,
            filterSQL: filterSQL
        )
        let relatedChangeIndexes: [PagedData.RowIndexInfo] = PagedData.indexes(
            db,
            rowIds: Array(pagedRowIdsForRelatedChanges),
            tableName: pagedTableName,
            requiredJoinSQL: joinSQL,
            orderSQL: orderSQL,
            filterSQL: filterSQL
        )
        let relatedDeletionIndexes: [PagedData.RowIndexInfo] = PagedData.indexes(
            db,
            rowIds: Array(pagedRowIdsForRelatedDeletions),
            tableName: pagedTableName,
            requiredJoinSQL: joinSQL,
            orderSQL: orderSQL,
            filterSQL: filterSQL
        )
        
        // Determine if the indexes for the row ids should be displayed on the screen and remove any
        // which shouldn't - values less than 'currentCount' or if there is at least one value less than
        // 'currentCount' and the indexes are sequential (ie. more than the current loaded content was
        // added at once)
        func determineValidChanges(for indexInfo: [PagedData.RowIndexInfo]) -> [Int64] {
            let indexes: [Int64] = Array(indexInfo
                .map { $0.rowIndex }
                .sorted()
                .asSet())
            let indexesAreSequential: Bool = (indexes.map { $0 - 1 }.dropFirst() == indexes.dropLast())
            let hasOneValidIndex: Bool = indexInfo.contains(where: { info -> Bool in
                info.rowIndex >= updatedPageInfo.pageOffset && (
                    info.rowIndex < updatedPageInfo.currentCount || (
                        updatedPageInfo.currentCount < updatedPageInfo.pageSize &&
                        info.rowIndex <= (updatedPageInfo.pageOffset + updatedPageInfo.pageSize)
                    )
                )
            })
            
            return (indexesAreSequential && hasOneValidIndex ?
                indexInfo.map { $0.rowId } :
                indexInfo
                    .filter { info -> Bool in
                        info.rowIndex >= updatedPageInfo.pageOffset && (
                            info.rowIndex < updatedPageInfo.currentCount || (
                                updatedPageInfo.currentCount < updatedPageInfo.pageSize &&
                                info.rowIndex <= (updatedPageInfo.pageOffset + updatedPageInfo.pageSize)
                            )
                        )
                    }
                    .map { info -> Int64 in info.rowId }
            )
        }
        let validChangeRowIds: [Int64] = determineValidChanges(for: itemIndexes)
        let validRelatedChangeRowIds: [Int64] = determineValidChanges(for: relatedChangeIndexes)
        let validRelatedDeletionRowIds: [Int64] = determineValidChanges(for: relatedDeletionIndexes)
        let countBefore: Int = itemIndexes.filter { $0.rowIndex < updatedPageInfo.pageOffset }.count
        
        // If the number of indexes doesn't match the number of rowIds then it means something changed
        // resulting in an item being filtered out
        func performRemovalsIfNeeded(for rowIds: Set<Int64>, indexes: [PagedData.RowIndexInfo]) {
            let uniqueIndexes: Set<Int64> = indexes.map { $0.rowId }.asSet()
            
            // If they have the same count then nothin was filtered out so do nothing
            guard rowIds.count != uniqueIndexes.count else { return }
            
            // Otherwise something was probably removed so try to remove it from the cache
            let rowIdsRemoved: Set<Int64> = rowIds.subtracting(uniqueIndexes)
            let preDeletionCount: Int = updatedDataCache.count
            updatedDataCache = updatedDataCache.deleting(rowIds: Array(rowIdsRemoved))

            // Lastly make sure there were actually changes before updating the page info
            guard updatedDataCache.count != preDeletionCount else { return }
            
            let dataSizeDiff: Int = (updatedDataCache.count - preDeletionCount)

            updatedPageInfo = PagedData.PageInfo(
                pageSize: updatedPageInfo.pageSize,
                pageOffset: updatedPageInfo.pageOffset,
                currentCount: (updatedPageInfo.currentCount + dataSizeDiff),
                totalCount: (updatedPageInfo.totalCount + dataSizeDiff)
            )
        }
        
        // Actually perform any required removals
        performRemovalsIfNeeded(for: directRowIds, indexes: itemIndexes)
        performRemovalsIfNeeded(for: pagedRowIdsForRelatedChanges, indexes: relatedChangeIndexes)
        performRemovalsIfNeeded(for: pagedRowIdsForRelatedDeletions, indexes: relatedDeletionIndexes)
        
        // Update the offset and totalCount even if the rows are outside of the current page (need to
        // in order to ensure the 'load more' sections are accurate)
        updatedPageInfo = PagedData.PageInfo(
            pageSize: updatedPageInfo.pageSize,
            pageOffset: (updatedPageInfo.pageOffset + countBefore),
            currentCount: updatedPageInfo.currentCount,
            totalCount: (
                updatedPageInfo.totalCount +
                changesToQuery
                    .filter { $0.kind == .insert }
                    .filter { validChangeRowIds.contains($0.rowId) }
                    .count
            )
        )

        // If there are no valid row ids then stop here (trigger updates though since the page info
        // has changes)
        guard !validChangeRowIds.isEmpty || !validRelatedChangeRowIds.isEmpty || !validRelatedDeletionRowIds.isEmpty else {
            updateDataAndCallbackIfNeeded(updatedDataCache, updatedPageInfo, true)
            return
        }
        
        // Fetch the inserted/updated rows
        let targetRowIds: [Int64] = Array((validChangeRowIds + validRelatedChangeRowIds + validRelatedDeletionRowIds).asSet())
        let updatedItems: [T] = (try? dataQuery(targetRowIds)
            .fetchAll(db))
            .defaulting(to: [])

        // Process the upserted data
        updatedDataCache = updatedDataCache.upserting(items: updatedItems)
        
        // Update the currentCount for the upserted data
        let dataSizeDiff: Int = (updatedDataCache.count - oldDataCount)
        
        updatedPageInfo = PagedData.PageInfo(
            pageSize: updatedPageInfo.pageSize,
            pageOffset: updatedPageInfo.pageOffset,
            currentCount: (updatedPageInfo.currentCount + dataSizeDiff),
            totalCount: updatedPageInfo.totalCount
        )
        
        updateDataAndCallbackIfNeeded(updatedDataCache, updatedPageInfo, true)
    }
    
    public func databaseDidRollback(_ db: Database) {}
    
    // MARK: - Functions
    
    fileprivate func load(_ target: PagedData.PageInfo.InternalTarget) {
        // Only allow a single page load at a time
        guard !self.isLoadingMoreData.wrappedValue else { return }

        // Prevent more fetching until we have completed adding the page
        self.isLoadingMoreData.mutate { $0 = true }
        
        let currentPageInfo: PagedData.PageInfo = self.pageInfo.wrappedValue
        
        if case .initialPageAround(_) = target, currentPageInfo.currentCount > 0 {
            SNLog("Unable to load initialPageAround if there is already data")
            return
        }
        
        // Store locally to avoid giant capture code
        let pagedTableName: String = self.pagedTableName
        let idColumnName: String = self.idColumnName
        let joinSQL: SQL? = self.joinSQL
        let filterSQL: SQL = self.filterSQL
        let groupSQL: SQL? = self.groupSQL
        let orderSQL: SQL = self.orderSQL
        let dataQuery: ([Int64]) -> AdaptedFetchRequest<SQLRequest<T>> = self.dataQuery
        
        let loadedPage: (data: [T]?, pageInfo: PagedData.PageInfo, failureCallback: (() -> ())?)? = Storage.shared.read { [weak self] db in
            typealias QueryInfo = (limit: Int, offset: Int, updatedCacheOffset: Int)
            let totalCount: Int = PagedData.totalCount(
                db,
                tableName: pagedTableName,
                requiredJoinSQL: joinSQL,
                filterSQL: filterSQL
            )
            
            let (queryInfo, callback): (QueryInfo?, (() -> ())?) = {
                switch target {
                    case .initialPageAround(let targetId):
                        // If we want to focus on a specific item then we need to find it's index in
                        // the queried data
                        let maybeIndex: Int? = PagedData.index(
                            db,
                            for: targetId,
                            tableName: pagedTableName,
                            idColumn: idColumnName,
                            requiredJoinSQL: joinSQL,
                            orderSQL: orderSQL,
                            filterSQL: filterSQL
                        )
                        
                        // If we couldn't find the targetId then just load the first page
                        guard let targetIndex: Int = maybeIndex else {
                            return ((currentPageInfo.pageSize, 0, 0), nil)
                        }
                        
                        let updatedOffset: Int = {
                            // If the focused item is within the first or last half of the page
                            // then we still want to retrieve a full page so calculate the offset
                            // needed to do so (snapping to the ends)
                            let halfPageSize: Int = Int(floor(Double(currentPageInfo.pageSize) / 2))
                            
                            guard targetIndex > halfPageSize else { return 0 }
                            guard targetIndex < (totalCount - halfPageSize) else {
                                return max(0, (totalCount - currentPageInfo.pageSize))
                            }

                            return (targetIndex - halfPageSize)
                        }()

                        return ((currentPageInfo.pageSize, updatedOffset, updatedOffset), nil)
                        
                    case .pageBefore:
                        let updatedOffset: Int = max(0, (currentPageInfo.pageOffset - currentPageInfo.pageSize))
                        
                        return (
                            (
                                currentPageInfo.pageSize,
                                updatedOffset,
                                updatedOffset
                            ),
                            nil
                        )
                        
                    case .pageAfter:
                        return (
                            (
                                currentPageInfo.pageSize,
                                (currentPageInfo.pageOffset + currentPageInfo.currentCount),
                                currentPageInfo.pageOffset
                            ),
                            nil
                        )
                    
                    case .untilInclusive(let targetId, let padding):
                        // If we want to focus on a specific item then we need to find it's index in
                        // the queried data
                        let maybeIndex: Int? = PagedData.index(
                            db,
                            for: targetId,
                            tableName: pagedTableName,
                            idColumn: idColumnName,
                            requiredJoinSQL: joinSQL,
                            orderSQL: orderSQL,
                            filterSQL: filterSQL
                        )
                        let cacheCurrentEndIndex: Int = (currentPageInfo.pageOffset + currentPageInfo.currentCount)
                        
                        // If we couldn't find the targetId or it's already in the cache then do nothing
                        guard
                            let targetIndex: Int = maybeIndex.map({ max(0, min(totalCount, $0)) }),
                            (
                                targetIndex < currentPageInfo.pageOffset ||
                                targetIndex >= cacheCurrentEndIndex
                            )
                        else { return (nil, nil) }
                        
                        // If the target is before the cached data then load before
                        if targetIndex < currentPageInfo.pageOffset {
                            let finalIndex: Int = max(0, (targetIndex - abs(padding)))
                            
                            return (
                                (
                                    (currentPageInfo.pageOffset - finalIndex),
                                    finalIndex,
                                    finalIndex
                                ),
                                nil
                            )
                        }
                        
                        // Otherwise load after (targetIndex is 0-indexed so we need to add 1 for this to
                        // have the correct 'limit' value)
                        let finalIndex: Int = min(totalCount, (targetIndex + 1 + abs(padding)))
                        
                        return (
                            (
                                (finalIndex - cacheCurrentEndIndex),
                                cacheCurrentEndIndex,
                                currentPageInfo.pageOffset
                            ),
                            nil
                        )
                        
                    case .jumpTo(let targetId, let paddingForInclusive):
                        // If we want to focus on a specific item then we need to find it's index in
                        // the queried data
                        let maybeIndex: Int? = PagedData.index(
                            db,
                            for: targetId,
                            tableName: pagedTableName,
                            idColumn: idColumnName,
                            requiredJoinSQL: joinSQL,
                            orderSQL: orderSQL,
                            filterSQL: filterSQL
                        )
                        let cacheCurrentEndIndex: Int = (currentPageInfo.pageOffset + currentPageInfo.currentCount)
                        
                        // If we couldn't find the targetId or it's already in the cache then do nothing
                        guard
                            let targetIndex: Int = maybeIndex.map({ max(0, min(totalCount, $0)) }),
                            (
                                targetIndex < currentPageInfo.pageOffset ||
                                targetIndex >= cacheCurrentEndIndex
                            )
                        else { return (nil, nil) }
                        
                        // If the target id is within a single page of the current cached data
                        // then trigger the `untilInclusive` behaviour instead
                        guard
                            abs(targetIndex - cacheCurrentEndIndex) > currentPageInfo.pageSize ||
                            abs(targetIndex - currentPageInfo.pageOffset) > currentPageInfo.pageSize
                        else {
                            let callback: () -> () = {
                                self?.load(.untilInclusive(id: targetId, padding: paddingForInclusive))
                            }
                            return (nil, callback)
                        }
                        
                        // If the targetId is further than 1 pageSize away then discard the current
                        // cached data and trigger a fresh `initialPageAround`
                        let callback: () -> () = {
                            self?.dataCache.mutate { $0 = DataCache() }
                            self?.associatedRecords.forEach { $0.clearCache(db) }
                            self?.pageInfo.mutate {
                                $0 = PagedData.PageInfo(
                                    pageSize: currentPageInfo.pageSize,
                                    pageOffset: 0,
                                    currentCount: 0,
                                    totalCount: 0
                                )
                            }
                            self?.load(.initialPageAround(id: targetId))
                        }
                        
                        return (nil, callback)
                        
                    case .reloadCurrent:
                        return (
                            (
                                currentPageInfo.currentCount,
                                currentPageInfo.pageOffset,
                                currentPageInfo.pageOffset
                            ),
                            nil
                        )
                }
            }()
            
            // If there is no queryOffset then we already have the data we need so
            // early-out (may as well update the 'totalCount' since it may be relevant)
            guard let queryInfo: QueryInfo = queryInfo else {
                return (
                    nil,
                    PagedData.PageInfo(
                        pageSize: currentPageInfo.pageSize,
                        pageOffset: currentPageInfo.pageOffset,
                        currentCount: currentPageInfo.currentCount,
                        totalCount: totalCount
                    ),
                    callback
                )
            }
            
            // Fetch the desired data
            let pageRowIds: [Int64] = PagedData.rowIds(
                db,
                tableName: pagedTableName,
                requiredJoinSQL: joinSQL,
                filterSQL: filterSQL,
                groupSQL: groupSQL,
                orderSQL: orderSQL,
                limit: queryInfo.limit,
                offset: queryInfo.offset
            )
            let newData: [T]
            
            do { newData = try dataQuery(pageRowIds).fetchAll(db) }
            catch {
                SNLog("PagedDatabaseObserver threw exception: \(error)")
                throw error
            }
            
            let updatedLimitInfo: PagedData.PageInfo = PagedData.PageInfo(
                pageSize: currentPageInfo.pageSize,
                pageOffset: queryInfo.updatedCacheOffset,
                currentCount: (currentPageInfo.currentCount + newData.count),
                totalCount: totalCount
            )
            
            // Update the associatedRecords for the newly retrieved data
            self?.associatedRecords.forEach { record in
                record.updateCache(
                    db,
                    rowIds: PagedData.associatedRowIds(
                        db,
                        tableName: record.databaseTableName,
                        pagedTableName: pagedTableName,
                        pagedTypeRowIds: newData.map { $0.rowId },
                        joinToPagedType: record.joinToPagedType
                    ),
                    hasOtherChanges: false
                )
            }

            return (newData, updatedLimitInfo, nil)
        }
        
        // Unwrap the updated data
        guard
            let loadedPageData: [T] = loadedPage?.data,
            let updatedPageInfo: PagedData.PageInfo = loadedPage?.pageInfo
        else {
            // It's possible to get updated page info without having updated data, in that case
            // we do want to update the cache but probably don't need to trigger the change callback
            if let updatedPageInfo: PagedData.PageInfo = loadedPage?.pageInfo {
                self.pageInfo.mutate { $0 = updatedPageInfo }
            }
            self.isLoadingMoreData.mutate { $0 = false }
            loadedPage?.failureCallback?()
            return
        }
        
        // Attach any associated data to the loadedPageData
        var associatedLoadedData: DataCache<T> = DataCache(items: loadedPageData)
        
        self.associatedRecords.forEach { record in
            associatedLoadedData = record.updateAssociatedData(to: associatedLoadedData)
        }
        
        // Update the cache and pageInfo
        self.dataCache.mutate { $0 = $0.upserting(items: associatedLoadedData.values) }
        self.pageInfo.mutate { $0 = updatedPageInfo }
        
        let triggerUpdates: () -> () = { [weak self, dataCache = self.dataCache.wrappedValue] in
            self?.onChangeUnsorted(dataCache.values, updatedPageInfo)
            self?.isLoadingMoreData.mutate { $0 = false }
        }
        
        triggerUpdates()
    }
    
    public func reload() {
        self.load(.reloadCurrent)
    }
}

// MARK: - Convenience

public extension PagedDatabaseObserver {
    convenience init(
        pagedTable: ObservedTable.Type,
        pageSize: Int,
        idColumn: ObservedTable.Columns,
        observedChanges: [PagedData.ObservedChanges],
        joinSQL: SQL? = nil,
        filterSQL: SQL,
        groupSQL: SQL? = nil,
        orderSQL: SQL,
        dataQuery: @escaping ([Int64]) -> SQLRequest<T>,
        associatedRecords: [ErasedAssociatedRecord] = [],
        onChangeUnsorted: @escaping ([T], PagedData.PageInfo) -> ()
    ) {
        self.init(
            pagedTable: pagedTable,
            pageSize: pageSize,
            idColumn: idColumn,
            observedChanges: observedChanges,
            joinSQL: joinSQL,
            filterSQL: filterSQL,
            groupSQL: groupSQL,
            orderSQL: orderSQL,
            dataQuery: { rowIds in dataQuery(rowIds).adapted { _ in ScopeAdapter([:]) } },
            associatedRecords: associatedRecords,
            onChangeUnsorted: onChangeUnsorted
        )
    }
    
    func load(_ target: PagedData.PageInfo.Target<ObservedTable.ID>) where ObservedTable.ID: SQLExpressible {
        self.load(target.internalTarget)
    }
    
    func load<ID>(_ target: PagedData.PageInfo.Target<ID>) where ObservedTable.ID == Optional<ID>, ID: SQLExpressible {
        self.load(target.internalTarget)
    }
}

// MARK: - FetchableRecordWithRowId

public protocol FetchableRecordWithRowId: FetchableRecord {
    var rowId: Int64 { get }
}

// MARK: - ErasedAssociatedRecord

public protocol ErasedAssociatedRecord {
    var databaseTableName: String { get }
    var pagedTableName: String { get }
    var observedChanges: [PagedData.ObservedChanges] { get }
    var joinToPagedType: SQL { get }
    
    func settingPagedTableName(pagedTableName: String) -> Self
    func tryUpdateForDatabaseCommit(
        _ db: Database,
        changes: Set<PagedData.TrackedChange>,
        joinSQL: SQL?,
        orderSQL: SQL,
        filterSQL: SQL,
        pageInfo: PagedData.PageInfo
    ) -> Bool
    @discardableResult func updateCache(_ db: Database, rowIds: [Int64], hasOtherChanges: Bool) -> Bool
    func clearCache(_ db: Database)
    func updateAssociatedData<O>(to unassociatedCache: DataCache<O>) -> DataCache<O>
}

// MARK: - DataCache

public struct DataCache<T: FetchableRecordWithRowId & Identifiable> {
    /// This is a map of `[RowId: Value]`
    public let data: [Int64: T]
    
    /// This is a map of `[(Identifiable)id: RowId]` and can be used to find the RowId for
    /// a cached value given it's `Identifiable` `id` value
    public let lookup: [AnyHashable: Int64]
    
    public var count: Int { data.count }
    public var values: [T] { Array(data.values) }
    
    // MARK: - Initialization
    
    public init(
        data: [Int64: T] = [:],
        lookup: [AnyHashable: Int64] = [:]
    ) {
        self.data = data
        self.lookup = lookup
    }
    
    fileprivate init(items: [T]) {
        self = DataCache().upserting(items: items)
    }

    // MARK: - Functions
    
    public func deleting(rowIds: [Int64]) -> DataCache<T> {
        var updatedData: [Int64: T] = self.data
        var updatedLookup: [AnyHashable: Int64] = self.lookup
        
        rowIds.forEach { rowId in
            if let cachedItem: T = updatedData.removeValue(forKey: rowId) {
                updatedLookup.removeValue(forKey: cachedItem.id)
            }
        }
        
        return DataCache(
            data: updatedData,
            lookup: updatedLookup
        )
    }
    
    public func upserting(_ item: T) -> DataCache<T> {
        return upserting(items: [item])
    }
    
    public func upserting(items: [T]) -> DataCache<T> {
        guard !items.isEmpty else { return self }
        
        var updatedData: [Int64: T] = self.data
        var updatedLookup: [AnyHashable: Int64] = self.lookup
        
        items.forEach { item in
            updatedData[item.rowId] = item
            updatedLookup[item.id] = item.rowId
        }
        
        return DataCache(
            data: updatedData,
            lookup: updatedLookup
        )
    }
}

// MARK: - PagedData

public enum PagedData {
    public static let autoLoadNextPageDelay: DispatchTimeInterval = .milliseconds(400)
    
    // MARK: - PageInfo
    
    public struct PageInfo {
        /// This type is identical to the 'Target' type but has it's 'SQLExpressible' requirement removed
        fileprivate enum InternalTarget {
            case initialPageAround(id: SQLExpression)
            case pageBefore
            case pageAfter
            case untilInclusive(id: SQLExpression, padding: Int)
            case jumpTo(id: SQLExpression, paddingForInclusive: Int)
            case reloadCurrent
        }
        
        public enum Target<ID: SQLExpressible> {
            /// This will attempt to load a page of data around a specified id
            ///
            /// **Note:** This target will only work if there is no other data in the cache
            case initialPageAround(id: ID)
            
            /// This will attempt to load a page of data before the first item in the cache
            case pageBefore
            
            /// This will attempt to load a page of data after the last item in the cache
            case pageAfter
            
            /// This will attempt to load all data between what is currently in the cache until the
            /// specified id (plus the padding amount)
            ///
            /// **Note:** If the id is already within the cache then this will do nothing (even if
            /// the padding would mean more data should be loaded)
            case untilInclusive(id: ID, padding: Int)
            
            /// This will jump to the specified id, loading a page around it and clearing out any
            /// data that was previously cached
            ///
            /// **Note:** If the id is within 1 pageSize of the currently cached data then this
            /// will behave as per the `untilInclusive(id:padding:)` type
            case jumpTo(id: ID, paddingForInclusive: Int)
            
            fileprivate var internalTarget: InternalTarget {
                switch self {
                    case .initialPageAround(let id): return .initialPageAround(id: id.sqlExpression)
                    case .pageBefore: return .pageBefore
                    case .pageAfter: return .pageAfter
                    case .untilInclusive(let id, let padding):
                        return .untilInclusive(id: id.sqlExpression, padding: padding)
                    
                    case .jumpTo(let id, let paddingForInclusive):
                        return .jumpTo(id: id.sqlExpression, paddingForInclusive: paddingForInclusive)
                }
            }
        }
        
        public let pageSize: Int
        public let pageOffset: Int
        public let currentCount: Int
        public let totalCount: Int
        
        // MARK: - Initizliation
        
        public init(
            pageSize: Int,
            pageOffset: Int = 0,
            currentCount: Int = 0,
            totalCount: Int = 0
        ) {
            self.pageSize = pageSize
            self.pageOffset = pageOffset
            self.currentCount = currentCount
            self.totalCount = totalCount
        }
    }
    
    // MARK: - ObservedChanges

    /// This type contains the information needed to define what changes should be included when observing
    /// changes to a database
    ///
    /// - Parameters:
    ///   - table: The table whose changes should be observed
    ///   - events: The database events which should be observed
    ///   - columns: The specific columns which should trigger changes (**Note:** These only apply to `update` changes)
    public struct ObservedChanges {
        public let databaseTableName: String
        public let events: [DatabaseEvent.Kind]
        public let columns: [String]
        public let joinToPagedType: SQL?
        
        public init<T: TableRecord & ColumnExpressible>(
            table: T.Type,
            events: [DatabaseEvent.Kind] = [.insert, .update, .delete],
            columns: [T.Columns],
            joinToPagedType: SQL? = nil
        ) {
            self.databaseTableName = table.databaseTableName
            self.events = events
            self.columns = columns.map { $0.name }
            self.joinToPagedType = joinToPagedType
        }
    }

    // MARK: - TrackedChange

    public struct TrackedChange: Hashable {
        let tableName: String
        let kind: DatabaseEvent.Kind
        let rowId: Int64
        let pagedRowIdsForRelatedDeletion: [Int64]?
        
        init(event: DatabaseEvent, pagedRowIdsForRelatedDeletion: [Int64]? = nil) {
            self.tableName = event.tableName
            self.kind = event.kind
            self.rowId = event.rowID
            self.pagedRowIdsForRelatedDeletion = pagedRowIdsForRelatedDeletion
        }
    }
    
    fileprivate struct RowIndexInfo: Decodable, FetchableRecord {
        let rowId: Int64
        let rowIndex: Int64
    }
    
    // MARK: - Internal Functions
    
    fileprivate static func totalCount(
        _ db: Database,
        tableName: String,
        requiredJoinSQL: SQL? = nil,
        filterSQL: SQL
    ) -> Int {
        let tableNameLiteral: SQL = SQL(stringLiteral: tableName)
        let finalJoinSQL: SQL = (requiredJoinSQL ?? "")
        let request: SQLRequest<Int> = """
            SELECT \(tableNameLiteral).rowId
            FROM \(tableNameLiteral)
            \(finalJoinSQL)
            WHERE \(filterSQL)
        """
        
        return (try? request.fetchCount(db))
            .defaulting(to: 0)
    }
    
    fileprivate static func rowIds(
        _ db: Database,
        tableName: String,
        requiredJoinSQL: SQL? = nil,
        filterSQL: SQL,
        groupSQL: SQL? = nil,
        orderSQL: SQL,
        limit: Int,
        offset: Int
    ) -> [Int64] {
        let tableNameLiteral: SQL = SQL(stringLiteral: tableName)
        let finalJoinSQL: SQL = (requiredJoinSQL ?? "")
        let finalGroupSQL: SQL = (groupSQL ?? "")
        let request: SQLRequest<Int64> = """
            SELECT \(tableNameLiteral).rowId
            FROM \(tableNameLiteral)
            \(finalJoinSQL)
            WHERE \(filterSQL)
            \(finalGroupSQL)
            ORDER BY \(orderSQL)
            LIMIT \(limit) OFFSET \(offset)
        """
        
        return (try? request.fetchAll(db))
            .defaulting(to: [])
    }
    
    fileprivate static func index<ID: SQLExpressible>(
        _ db: Database,
        for id: ID,
        tableName: String,
        idColumn: String,
        requiredJoinSQL: SQL? = nil,
        orderSQL: SQL,
        filterSQL: SQL
    ) -> Int? {
        let tableNameLiteral: SQL = SQL(stringLiteral: tableName)
        let idColumnLiteral: SQL = SQL(stringLiteral: idColumn)
        let finalJoinSQL: SQL = (requiredJoinSQL ?? "")
        let request: SQLRequest<Int> = """
            SELECT
                (data.rowIndex - 1) AS rowIndex -- Converting from 1-Indexed to 0-indexed
            FROM (
                SELECT
                    \(tableNameLiteral).\(idColumnLiteral) AS \(idColumnLiteral),
                    ROW_NUMBER() OVER (ORDER BY \(orderSQL)) AS rowIndex
                FROM \(tableNameLiteral)
                \(finalJoinSQL)
                WHERE \(filterSQL)
            ) AS data
            WHERE \(SQL("data.\(idColumnLiteral) = \(id)"))
        """
        
        return try? request.fetchOne(db)
    }

    /// Returns the indexes the requested rowIds will have in the paged query
    ///
    /// **Note:** If the `associatedRecord` is null then the index for the rowId of the paged data type will be returned
    fileprivate static func indexes(
        _ db: Database,
        rowIds: [Int64],
        tableName: String,
        requiredJoinSQL: SQL? = nil,
        orderSQL: SQL,
        filterSQL: SQL
    ) -> [RowIndexInfo] {
        guard !rowIds.isEmpty else { return [] }
        
        let tableNameLiteral: SQL = SQL(stringLiteral: tableName)
        let finalJoinSQL: SQL = (requiredJoinSQL ?? "")
        let request: SQLRequest<RowIndexInfo> = """
            SELECT
                data.rowId AS rowId,
                (data.rowIndex - 1) AS rowIndex -- Converting from 1-Indexed to 0-indexed
            FROM (
                SELECT
                    \(tableNameLiteral).rowid AS rowid,
                    ROW_NUMBER() OVER (ORDER BY \(orderSQL)) AS rowIndex
                FROM \(tableNameLiteral)
                \(finalJoinSQL)
                WHERE \(filterSQL)
            ) AS data
            WHERE \(SQL("data.rowid IN \(rowIds)"))
        """
        
        return (try? request.fetchAll(db))
            .defaulting(to: [])
    }
    
    /// Returns the rowIds for the associated types based on the specified pagedTypeRowIds
    fileprivate static func associatedRowIds(
        _ db: Database,
        tableName: String,
        pagedTableName: String,
        pagedTypeRowIds: [Int64],
        joinToPagedType: SQL
    ) -> [Int64] {
        guard !pagedTypeRowIds.isEmpty else { return [] }
        
        let tableNameLiteral: SQL = SQL(stringLiteral: tableName)
        let pagedTableNameLiteral: SQL = SQL(stringLiteral: pagedTableName)
        let request: SQLRequest<Int64> = """
            SELECT \(tableNameLiteral).rowid AS rowid
            FROM \(pagedTableNameLiteral)
            \(joinToPagedType)
            WHERE \(pagedTableNameLiteral).rowId IN \(pagedTypeRowIds)
        """
        
        return (try? request.fetchAll(db))
            .defaulting(to: [])
    }
    
    /// Returns the rowIds for the paged type based on the specified relatedRowIds
    fileprivate static func pagedRowIdsForRelatedRowIds(
        _ db: Database,
        tableName: String,
        pagedTableName: String,
        relatedRowIds: [Int64],
        joinToPagedType: SQL
    ) -> [Int64] {
        guard !relatedRowIds.isEmpty else { return [] }
        
        let tableNameLiteral: SQL = SQL(stringLiteral: tableName)
        let pagedTableNameLiteral: SQL = SQL(stringLiteral: pagedTableName)
        let request: SQLRequest<Int64> = """
            SELECT \(pagedTableNameLiteral).rowid AS rowid
            FROM \(pagedTableNameLiteral)
            \(joinToPagedType)
            WHERE \(tableNameLiteral).rowId IN \(relatedRowIds)
        """
        
        return (try? request.fetchAll(db))
            .defaulting(to: [])
    }
}

// MARK: - AssociatedRecord

public class AssociatedRecord<T, PagedType>: ErasedAssociatedRecord where T: FetchableRecordWithRowId & Identifiable, PagedType: FetchableRecordWithRowId & Identifiable {
    public let databaseTableName: String
    public private(set) var pagedTableName: String = ""
    public let observedChanges: [PagedData.ObservedChanges]
    public let joinToPagedType: SQL
    
    fileprivate let dataCache: Atomic<DataCache<T>> = Atomic(DataCache())
    fileprivate let dataQuery: (SQL?) -> AdaptedFetchRequest<SQLRequest<T>>
    fileprivate let associateData: (DataCache<T>, DataCache<PagedType>) -> DataCache<PagedType>
    
    // MARK: - Initialization
    
    public init<Table: TableRecord>(
        trackedAgainst: Table.Type,
        observedChanges: [PagedData.ObservedChanges],
        dataQuery: @escaping (SQL?) -> AdaptedFetchRequest<SQLRequest<T>>,
        joinToPagedType: SQL,
        associateData: @escaping (DataCache<T>, DataCache<PagedType>) -> DataCache<PagedType>
    ) {
        self.databaseTableName = trackedAgainst.databaseTableName
        self.observedChanges = observedChanges
        self.dataQuery = dataQuery
        self.joinToPagedType = joinToPagedType
        self.associateData = associateData
    }
    
    public convenience init<Table: TableRecord>(
        trackedAgainst: Table.Type,
        observedChanges: [PagedData.ObservedChanges],
        dataQuery: @escaping (SQL?) -> SQLRequest<T>,
        joinToPagedType: SQL,
        associateData: @escaping (DataCache<T>, DataCache<PagedType>) -> DataCache<PagedType>
    ) {
        self.init(
            trackedAgainst: trackedAgainst,
            observedChanges: observedChanges,
            dataQuery: { additionalFilters in
                dataQuery(additionalFilters).adapted { _ in ScopeAdapter([:]) }
            },
            joinToPagedType: joinToPagedType,
            associateData: associateData
        )
    }
    
    // MARK: - AssociatedRecord
    
    public func settingPagedTableName(pagedTableName: String) -> Self {
        self.pagedTableName = pagedTableName
        return self
    }
    
    public func tryUpdateForDatabaseCommit(
        _ db: Database,
        changes: Set<PagedData.TrackedChange>,
        joinSQL: SQL?,
        orderSQL: SQL,
        filterSQL: SQL,
        pageInfo: PagedData.PageInfo
    ) -> Bool {
        // Ignore any changes which aren't relevant to this type
        let relevantChanges: Set<PagedData.TrackedChange> = changes
            .filter { $0.tableName == databaseTableName }
        
        guard !relevantChanges.isEmpty else { return false }
        
        // First remove any items which have been deleted
        let oldCount: Int = self.dataCache.wrappedValue.count
        let deletionChanges: [Int64] = relevantChanges
            .filter { $0.kind == .delete }
            .map { $0.rowId }
        
        dataCache.mutate { $0 = $0.deleting(rowIds: deletionChanges) }
        
        // Get an updated count to avoid locking the dataCache unnecessarily
        let countAfterDeletions: Int = self.dataCache.wrappedValue.count
        
        // If there are no inserted/updated rows then trigger the update callback and stop here
        let rowIdsToQuery: [Int64] = relevantChanges
            .filter { $0.kind != .delete }
            .map { $0.rowId }
        
        guard !rowIdsToQuery.isEmpty else { return (oldCount != countAfterDeletions) }
        
        // Fetch the indexes of the rowIds so we can determine whether they should be added to the screen
        let pagedRowIds: [Int64] = PagedData.pagedRowIdsForRelatedRowIds(
            db,
            tableName: databaseTableName,
            pagedTableName: pagedTableName,
            relatedRowIds: rowIdsToQuery,
            joinToPagedType: joinToPagedType
        )
        
        // If the associated data change isn't related to the paged type then no need to continue
        guard !pagedRowIds.isEmpty else { return (oldCount != countAfterDeletions) }
        
        let pagedItemIndexes: [PagedData.RowIndexInfo] = PagedData.indexes(
            db,
            rowIds: pagedRowIds,
            tableName: pagedTableName,
            requiredJoinSQL: joinSQL,
            orderSQL: orderSQL,
            filterSQL: filterSQL
        )
        
        // If we can't get the item indexes for the paged row ids then it's likely related to data
        // which was filtered out (eg. message attachment related to a different thread)
        guard !pagedItemIndexes.isEmpty else { return (oldCount != countAfterDeletions) }
        
        /// **Note:** The `PagedData.indexes` works by returning the index of a row in a given query, unfortunately when
        /// dealing with associated data its possible for multiple associated data values to connect to an individual paged result,
        /// this throws off the indexes so we can't actually tell what `rowIdsToQuery` value is associated to which
        /// `pagedItemIndexes` value
        ///
        /// Instead of following the pattern the `PagedDatabaseObserver` does where we get the proper `validRowIds` we
        /// basically have to check if there is a single valid index, and if so retrieve and store all data related to the changes for this
        /// commit - this will mean in some cases we cache data which is actually unrelated to the filtered paged data
        let hasOneValidIndex: Bool = pagedItemIndexes.contains(where: { info -> Bool in
            info.rowIndex >= pageInfo.pageOffset && (
                info.rowIndex < pageInfo.currentCount || (
                    pageInfo.currentCount < pageInfo.pageSize &&
                    info.rowIndex <= (pageInfo.pageOffset + pageInfo.pageSize)
                )
            )
        })
        
        // Don't bother continuing if we don't have a valid index
        guard hasOneValidIndex else { return (oldCount != countAfterDeletions) }

        // Attempt to update the cache with the `validRowIds` array
        return updateCache(
            db,
            rowIds: rowIdsToQuery,
            hasOtherChanges: (oldCount != countAfterDeletions)
        )
    }
    
    @discardableResult public func updateCache(_ db: Database, rowIds: [Int64], hasOtherChanges: Bool = false) -> Bool {
        // If there are no rowIds then stop here
        guard !rowIds.isEmpty else { return hasOtherChanges }
        
        // Fetch the inserted/updated rows
        let additionalFilters: SQL = SQL(rowIds.contains(Column.rowID))
        let updatedItems: [T] = (try? dataQuery(additionalFilters)
            .fetchAll(db))
            .defaulting(to: [])
        
        // If the inserted/updated rows we irrelevant (eg. associated to another thread, a quote or a link
        // preview) then trigger the update callback (if there were deletions) and stop here
        guard !updatedItems.isEmpty else { return hasOtherChanges }
        
        // Process the upserted data (assume at least one value changed)
        dataCache.mutate { $0 = $0.upserting(items: updatedItems) }
        
        return true
    }
    
    public func clearCache(_ db: Database) {
        dataCache.mutate { $0 = DataCache() }
    }
    
    public func updateAssociatedData<O>(to unassociatedCache: DataCache<O>) -> DataCache<O> {
        guard let typedCache: DataCache<PagedType> = unassociatedCache as? DataCache<PagedType> else {
            return unassociatedCache
        }
        
        return (associateData(dataCache.wrappedValue, typedCache) as? DataCache<O>)
            .defaulting(to: unassociatedCache)
    }
}
