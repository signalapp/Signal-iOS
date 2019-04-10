//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

@objc
public class SDSObserver: NSObject {

    private let observer: TransactionObserver

    private let callback : () -> Void

    private init(_ observer: TransactionObserver,
                 callback : @escaping () -> Void) {
        self.observer = observer
        self.callback = callback

        super.init()

        listenToNotifications()
    }

    private func listenToNotifications() {

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(crossProcessNotification),
                                               name: SDSDatabaseStorage.didReceiveCrossProcessNotification,
                                               object: nil)
    }

    deinit {
        Logger.verbose("")

        NotificationCenter.default.removeObserver(self)
    }

    @objc func crossProcessNotification() {
        AssertIsOnMainThread()

        // SQLite won't inform us of writes made by other processes.
        //
        // SDSDataStore will inform us of when it updates
        // in response to cross process writes.  This might
        // not involve write to the table(s) we're observing,
        // but SDSDataStore will try not to do this too often.
        callback()
    }

// MARK: -

    @objc
    public class func observe(tableMetadata: SDSTableMetadata,
                              databaseStorage: SDSDatabaseStorage,
                              callback : @escaping () -> Void) -> SDSObserver? {
        AssertIsOnMainThread()

        tableMetadata.ensureTableExistsIfNecessary(databaseStorage: databaseStorage)

        // TODO: Reconcile this with SDSDatabaseStorage.

//        let region = DatabaseRegion(table: tableMetadata.tableName)
//
//        do {
//            // TODO:
//            //
//            /// The selection defaults to all columns. This default can be changed for
//            /// all requests by the `TableRecord.databaseSelection` property, or
//            /// for individual requests with the `TableRecord.select` method.
//            let observation = DatabaseRegionObservation(tracking: region)
//            let observer = try databaseStorage.observe(observation: observation, callback: callback)
//            return SDSObserver(observer, callback: callback)
//        } catch let error {
//            // TODO:
//            owsFail("Observation failed: \(error)")
//        }
        return nil
    }
}
