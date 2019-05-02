//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

/// Anything 
public protocol DatabaseSnapshotDelegate: AnyObject {
    // Called on the Database serial write queue before `databaseSnapshotWillUpdate`
    //
    // Use this callback to prepare state from the just-committed
    // database which will be passed along in your DidUpdate hooks
    func databaseSnapshotSourceDidCommit(db: Database)

    // The following are called on the Main Thread
    func databaseSnapshotWillUpdate()
    func databaseSnapshotDidUpdate()
    func databaseSnapshotDidUpdateExternally()
}

@objc
public protocol ObjCDatabaseSnapshotDelegate: AnyObject {
    func databaseSnapshotWillUpdate()
    func databaseSnapshotDidUpdate()
    func databaseSnapshotDidUpdateExternally()
}

enum DatabaseObserverError: Error {
    case changeTooLarge
}

func AssertIsOnUIDatabaseObserverSerialQueue() {
    #if DEBUG
    assertOnQueue(UIDatabaseObserver.serialQueue)
    #endif
}

@objc
public class UIDatabaseObserver: NSObject {

    public static let kMaxIncrementalRowChanges = 200
    public static let serialQueue = DispatchQueue(label: "UIDatabaseObserver.serialQueue")

    private var _snapshotDelegates: [Weak<DatabaseSnapshotDelegate>] = []
    private var snapshotDelegates: [DatabaseSnapshotDelegate] {
        return _snapshotDelegates.compactMap { $0.value }
    }

    @objc
    public func appendSnapshotDelegate(_ snapshotDelegate: ObjCDatabaseSnapshotDelegate) {
        let wrapper: DatabaseSnapshotDelegate = ObjCDatabaseSnapshotDelegateWrapper(snapshotDelegate)
        _snapshotDelegates = _snapshotDelegates.filter { $0.value != nil} + [Weak(value: wrapper)]
    }

    public func appendSnapshotDelegate(_ snapshotDelegate: DatabaseSnapshotDelegate) {
        _snapshotDelegates = _snapshotDelegates.filter { $0.value != nil} + [Weak(value: snapshotDelegate)]
    }

    private var observer: TransactionObserver?
    internal var latestSnapshot: DatabaseSnapshot {
        didSet {
            AssertIsOnMainThread()
        }
    }

    init(pool: DatabasePool) throws {
        self.latestSnapshot = try pool.makeSnapshot()
        super.init()

        let observation = DatabaseRegionObservation(tracking: DatabaseRegion.fullDatabase)
        self.observer = try observation.start(in: pool) { [weak self] (database: Database) in
            guard let self = self else { return }

            UIDatabaseObserver.serialQueue.sync {
                for delegate in self.snapshotDelegates {
                    delegate.databaseSnapshotSourceDidCommit(db: database)
                }
            }

            let newSnapshot = try! pool.makeSnapshot()

            DispatchQueue.main.async {
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

private class ObjCDatabaseSnapshotDelegateWrapper {
    let objCDatabaseSnapshotDelegate: ObjCDatabaseSnapshotDelegate
    init(_ objCDatabaseSnapshotDelegate: ObjCDatabaseSnapshotDelegate) {
        self.objCDatabaseSnapshotDelegate = objCDatabaseSnapshotDelegate
    }
}

extension ObjCDatabaseSnapshotDelegateWrapper: DatabaseSnapshotDelegate {
    func databaseSnapshotSourceDidCommit(db: Database) {
        // Currently no objc delegates will need to handle the commit
        // Doing so would be slightly complicated since `Database` is Swift only.
        owsFailDebug("not implemented.")
    }

    func databaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
        objCDatabaseSnapshotDelegate.databaseSnapshotWillUpdate()
    }

    func databaseSnapshotDidUpdate() {
        AssertIsOnMainThread()
        objCDatabaseSnapshotDelegate.databaseSnapshotDidUpdate()
    }

    func databaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()
        objCDatabaseSnapshotDelegate.databaseSnapshotDidUpdateExternally()
    }
}
