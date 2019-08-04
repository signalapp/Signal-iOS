//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

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

    private typealias RowId = Int64

    private var _pendingChanges: Set<RowId> = Set()
    private var pendingChanges: Set<RowId> {
        get {
            AssertIsOnUIDatabaseObserverSerialQueue()
            return _pendingChanges
        }
        set {
            AssertIsOnUIDatabaseObserverSerialQueue()
            _pendingChanges = newValue
        }
    }

    private var _committedChanges: Set<RowId>?
    private var committedChanges: Set<RowId>? {
        get {
            AssertIsOnMainThread()
            return _committedChanges
        }
        set {
            AssertIsOnMainThread()
            _committedChanges = newValue
        }
    }

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

extension MediaGalleryDatabaseObserver: TransactionObserver {

    public func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        switch eventKind {
        case .delete(tableName: let tableName):
            return tableName == AttachmentRecord.databaseTableName
        default:
            return false
        }
    }

    public func databaseDidChange(with event: DatabaseEvent) {
        Logger.verbose("")
        assert(event.tableName == AttachmentRecord.databaseTableName)
        UIDatabaseObserver.serializedSync {
            _ = pendingChanges.insert(event.rowID)
        }
    }

    public func databaseDidCommit(_ db: Database) {
        // no - op

        // Although this class is a TransactionObserver, it is also a delegate
        // (DatabaseSnapshotDelegate) of another TransactionObserver, the UIDatabaseObserver.
        //
        // We use our own TransactionObserver methods to collect details about the changes,
        // but we wait for the UIDatabaseObserver's TransactionObserver methods to inform our own
        // delegate of these details in sync with when the UI DB Snapshot is updated
        // (via DatabaseSnapshotDelegate).
    }

    public func databaseDidRollback(_ db: Database) {
        owsFailDebug("we should verify this works if we ever start to use rollbacks")
        UIDatabaseObserver.serializedSync {
            pendingChanges = Set()
        }
    }
}

extension MediaGalleryDatabaseObserver: DatabaseSnapshotDelegate {

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

    public func databaseSnapshotSourceDidCommit(db: Database) {
        AssertIsOnUIDatabaseObserverSerialQueue()
        let pendingChanges = self.pendingChanges
        self.pendingChanges = Set()

        DispatchQueue.main.async {
            self.committedChanges = pendingChanges
        }
    }

    var databaseStorage: GRDBDatabaseStorageAdapter {
        return SDSDatabaseStorage.shared.grdbStorage
    }

    public func databaseSnapshotWillUpdate() {
        AssertIsOnMainThread()

        do {
            guard let committedChanges = self.committedChanges else {
                throw OWSErrorMakeAssertionError("committedChanges were unexpectedly nil")
            }
            self.committedChanges = nil

            assert(self.deletedAttachmentIds == nil)
            try databaseStorage.uiReadThrows { transaction in
                self.deletedAttachmentIds = try self.attachmentIds(forRowIds: committedChanges, transaction: transaction)
            }
            for delegate in snapshotDelegates {
                delegate.mediaGalleryDatabaseSnapshotWillUpdate()
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    public func databaseSnapshotDidUpdate() {
        AssertIsOnMainThread()
        do {
            guard let deletedAttachmentIds = self.deletedAttachmentIds else {
                throw OWSErrorMakeAssertionError("deletedAttachmentIds were unexpectedly nil")
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
}
