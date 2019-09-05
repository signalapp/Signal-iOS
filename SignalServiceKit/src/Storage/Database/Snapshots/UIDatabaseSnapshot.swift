//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

/// Anything 
public protocol DatabaseSnapshotDelegate: AnyObject {

    // MARK: - Transaction Lifecycle

    /// Called on the DatabaseSnapshotSerial queue durign the transaction
    /// so the DatabaseSnapshotDelegate can accrue information about changes
    /// as they occur.

    func snapshotTransactionDidChange(with event: DatabaseEvent)
    func snapshotTransactionDidCommit(db: Database)
    func snapshotTransactionDidRollback(db: Database)

    // MARK: - Snapshot LifeCycle (Post Commit)

    /// Called on the Main Thread after the transaction has committed

    func databaseSnapshotWillUpdate()
    func databaseSnapshotDidUpdate()
    func databaseSnapshotDidUpdateExternally()
}

enum DatabaseObserverError: Error {
    case changeTooLarge
}

@objc
public class AtomicBool: NSObject {
    private var value: Bool

    @objc
    public required init(_ value: Bool) {
        self.value = value
    }

    // All instances can share a single queue.
    private static let serialQueue = DispatchQueue(label: "AtomicBool")

    @objc
    public func get() -> Bool {
        return AtomicBool.serialQueue.sync {
            return self.value
        }
    }

    @objc
    public func set(_ value: Bool) {
        return AtomicBool.serialQueue.sync {
            self.value = value
        }
    }
}

func AssertIsOnUIDatabaseObserverSerialQueue() {
    assert(UIDatabaseObserver.isOnUIDatabaseObserverSerialQueue)
}

@objc
public class UIDatabaseObserver: NSObject {

    public static let kMaxIncrementalRowChanges = 200

    // tldr; Instead, of protecting UIDatabaseObserver state with a nested DispatchQueue,
    // which would break GRDB's SchedulingWatchDog, we use objc_sync
    //
    // Longer version:
    // Our snapshot observers manage state, which must not be accessed concurrently.
    // Using a serial DispatchQueue would seem straight forward, but...
    //
    // Some of our snapshot observers read from the database *while* accessing this
    // state. Note that reading from the db must be done on GRDB's DispatchQueue.
    private static var _isOnUIDatabaseObserverSerialQueue = AtomicBool(false)

    static var isOnUIDatabaseObserverSerialQueue: Bool {
        return _isOnUIDatabaseObserverSerialQueue.get()
    }

    public class func serializedSync(block: () -> Void) {
        objc_sync_enter(self)
        assert(!_isOnUIDatabaseObserverSerialQueue.get())
        _isOnUIDatabaseObserverSerialQueue.set(true)
        block()
        _isOnUIDatabaseObserverSerialQueue.set(false)
        objc_sync_exit(self)
    }

    private var _snapshotDelegates: [Weak<DatabaseSnapshotDelegate>] = []
    private var snapshotDelegates: [DatabaseSnapshotDelegate] {
        return _snapshotDelegates.compactMap { $0.value }
    }

    public func appendSnapshotDelegate(_ snapshotDelegate: DatabaseSnapshotDelegate) {
        _snapshotDelegates = _snapshotDelegates.filter { $0.value != nil} + [Weak(value: snapshotDelegate)]
    }

    let pool: DatabasePool
    internal var latestSnapshot: DatabaseSnapshot {
        didSet {
            AssertIsOnMainThread()
        }
    }

    init(pool: DatabasePool) throws {
        self.pool = pool
        self.latestSnapshot = try pool.makeSnapshot()
        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didReceiveCrossProcessNotification),
                                               name: SDSDatabaseStorage.didReceiveCrossProcessNotification,
                                               object: nil)
    }

    @objc
    func didReceiveCrossProcessNotification(_ notification: Notification) {
        AssertIsOnMainThread()
        Logger.verbose("")

        for delegate in snapshotDelegates {
            delegate.databaseSnapshotDidUpdateExternally()
        }
    }
}

extension UIDatabaseObserver: TransactionObserver {

    public func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        return true
    }

    public func databaseDidChange(with event: DatabaseEvent) {
        UIDatabaseObserver.serializedSync {
            for snapshotDelegate in snapshotDelegates {
                snapshotDelegate.snapshotTransactionDidChange(with: event)
            }
        }
    }

    public func databaseDidCommit(_ db: Database) {
        UIDatabaseObserver.serializedSync {
            for snapshotDelegate in snapshotDelegates {
                snapshotDelegate.snapshotTransactionDidCommit(db: db)
            }
        }

        let getNewSnapshot: () -> DatabaseSnapshot? = {
            do {
                return try self.pool.makeSnapshot()
            } catch {
                if CurrentAppContext().isRunningTests {
                    // SQLite error 14
                    ///Can happen during tests wherein we sometimes delete
                    // the db.
                    Logger.warn("failed to make new snapshot")
                } else {
                    owsFail("failed to make new snapshot")
                }
            }
            return nil
        }

        guard let newSnapshot = getNewSnapshot() else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            Logger.verbose("databaseSnapshotWillUpdate")
            for delegate in self.snapshotDelegates {
                delegate.databaseSnapshotWillUpdate()
            }

            self.latestSnapshot = newSnapshot

            Logger.verbose("databaseSnapshotDidUpdate")
            for delegate in self.snapshotDelegates {
                delegate.databaseSnapshotDidUpdate()
            }
        }
    }

    public func databaseDidRollback(_ db: Database) {
        UIDatabaseObserver.serializedSync {
            for snapshotDelegate in snapshotDelegates {
                snapshotDelegate.snapshotTransactionDidRollback(db: db)
            }
        }
    }
}
