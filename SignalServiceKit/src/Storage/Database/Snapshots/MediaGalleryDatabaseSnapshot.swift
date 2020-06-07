//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public protocol MediaGalleryDatabaseSnapshotDelegate: AnyObject {
    func mediaGalleryDatabaseSnapshotWillUpdate()
    func mediaGalleryDatabaseSnapshotDidUpdate(deletedAttachmentIds: Set<String>)
    func mediaGalleryDatabaseSnapshotDidUpdateExternally()
    func mediaGalleryDatabaseSnapshotDidReset()
}

@objc
public class MediaGalleryDatabaseObserver: NSObject {

    private var _snapshotDelegates: [Weak<MediaGalleryDatabaseSnapshotDelegate>] = []
    private var snapshotDelegates: [MediaGalleryDatabaseSnapshotDelegate] {
        return _snapshotDelegates.compactMap { $0.value }
    }

    @objc
    public func appendSnapshotDelegate(_ snapshotDelegate: MediaGalleryDatabaseSnapshotDelegate) {
        _snapshotDelegates = _snapshotDelegates.filter { $0.value != nil} + [Weak(value: snapshotDelegate)]
    }

    // NOTE: This observer only tracks deleted attachment rowIds in ObservedDatabaseChanges.
    fileprivate typealias RowId = Int64
    fileprivate var pendingChanges = ObservedDatabaseChanges<RowId>(concurrencyMode: .uiDatabaseObserverSerialQueue)
    fileprivate var committedChanges = ObservedDatabaseChanges<RowId>(concurrencyMode: .mainThread)

    var _deletedAttachmentIds: Set<String>?
    var deletedAttachmentIds: Set<String>? {
        get {
            AssertIsOnMainThread()
            return _deletedAttachmentIds
        }
        set {
            AssertIsOnMainThread()
            _deletedAttachmentIds = newValue
        }
    }
}

extension MediaGalleryDatabaseObserver: DatabaseSnapshotDelegate {

    // MARK: - Transaction Lifecycle

    public func snapshotTransactionDidChange(with event: DatabaseEvent) {
        AssertIsOnUIDatabaseObserverSerialQueue()
        if event.kind == .delete && event.tableName == AttachmentRecord.databaseTableName {
            pendingChanges.append(attachmentChange: event.rowID)
        }
    }

    public func snapshotTransactionDidCommit(db: Database) {
        AssertIsOnUIDatabaseObserverSerialQueue()

        let attachmentChanges = pendingChanges.attachmentChanges
        pendingChanges.reset()

        DispatchQueue.main.async {
            self.committedChanges.append(attachmentChanges: attachmentChanges)
        }
    }

    public func snapshotTransactionDidRollback(db: Database) {
        owsFailDebug("we should verify this works if we ever start to use rollbacks")
        AssertIsOnUIDatabaseObserverSerialQueue()
        pendingChanges.reset()
    }

    // MARK: - Snapshot LifeCycle (Post Commit)

    public func databaseSnapshotWillUpdate() {
        AssertIsOnMainThread()

        defer {
            committedChanges.reset()
        }

        let notifyReset = {
            for delegate in self.snapshotDelegates {
                delegate.mediaGalleryDatabaseSnapshotDidReset()
            }
        }

        // We don't yet use lastError in this snapshot, but we might eventually.
        if let error = self.committedChanges.lastError {
            owsFailDebug("Error: \(error)")
            return notifyReset()
        }

        do {
            let deletedAttachmentRowIds = committedChanges.attachmentChanges

            assert(self.deletedAttachmentIds == nil)
            try databaseStorage.uiReadThrows { transaction in
                self.deletedAttachmentIds = try self.attachmentIds(forRowIds: deletedAttachmentRowIds, transaction: transaction)
            }
            for delegate in snapshotDelegates {
                delegate.mediaGalleryDatabaseSnapshotWillUpdate()
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return notifyReset()
        }
    }

    public func databaseSnapshotDidUpdate() {
        AssertIsOnMainThread()
        do {
            guard let deletedAttachmentIds = self.deletedAttachmentIds else {
                throw OWSAssertionError("deletedAttachmentIds were unexpectedly nil")
            }
            self.deletedAttachmentIds = nil

            for delegate in snapshotDelegates {
                delegate.mediaGalleryDatabaseSnapshotDidUpdate(deletedAttachmentIds: deletedAttachmentIds)
            }
        } catch DatabaseObserverError.changeTooLarge {
            for delegate in snapshotDelegates {
                delegate.mediaGalleryDatabaseSnapshotDidReset()
            }
        } catch {
            owsFailDebug("unknown error: \(error)")
            for delegate in snapshotDelegates {
                delegate.mediaGalleryDatabaseSnapshotDidReset()
            }
        }
    }

    public func databaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()
        for delegate in snapshotDelegates {
            delegate.mediaGalleryDatabaseSnapshotDidUpdateExternally()
        }
    }

    // MARK: - Private Helpers

    private var databaseStorage: GRDBDatabaseStorageAdapter {
        return SDSDatabaseStorage.shared.grdbStorage
    }

    private func attachmentIds(forRowIds rowIds: Set<RowId>, transaction: GRDBReadTransaction) throws -> Set<String> {
        guard rowIds.count > 0 else {
            return Set()
        }

        let commaSeparatedRowIds = rowIds.map { String($0) }.joined(separator: ", ")
        let rowIdsSQL = "(\(commaSeparatedRowIds))"

        let sql = """
        SELECT \(attachmentColumn: .uniqueId)
        FROM \(AttachmentRecord.databaseTableName)
        WHERE rowid IN \(rowIdsSQL)
        """

        let uniqueIds = try String.fetchAll(transaction.database, sql: sql)
        return Set(uniqueIds)
    }
}
