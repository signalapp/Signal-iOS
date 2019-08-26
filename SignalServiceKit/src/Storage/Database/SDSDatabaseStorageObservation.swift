//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

@objc
public class SDSDatabaseStorageChange: NSObject {

    // MARK: - Dependencies

    private var primaryStorage: OWSPrimaryStorage? {
        return SSKEnvironment.shared.primaryStorage
    }

    // MARK: -

    // In the GRDB case, we collect modified collections and interactions.
    let updatedCollections: Set<String>
    let updatedInteractionIds: Set<String>

    // In the YDB case, we use notifications to lazy-evaluate.
    let ydbNotifications: [Notification]?

    // OWSPrimaryStorage sometimes posts notifications even if
    // no write has occurred.  The tests (only) need to ignore these.
    #if DEBUG
    @objc
    public var isEmptyYDBChange: Bool {
        guard let ydbNotifications = ydbNotifications,
                ydbNotifications.isEmpty else {
                    return false
        }
        return true
    }
    #endif

    required init(updatedCollections: Set<String>,
                  updatedInteractionIds: Set<String>,
                  ydbNotifications: [Notification]? = nil) {
        self.updatedCollections = updatedCollections
        self.updatedInteractionIds = updatedInteractionIds
        self.ydbNotifications = ydbNotifications
    }

    @objc
    public var didUpdateInteractions: Bool {
        return didUpdate(collection: TSInteraction.collection())
    }

    @objc
    public var didUpdateThreads: Bool {
        return didUpdate(collection: TSThread.collection())
    }

    @objc
    public var didUpdateInteractionsOrThreads: Bool {
        return didUpdateInteractions || didUpdateThreads
    }

    private func didUpdate(collection: String) -> Bool {
        if updatedCollections.contains(collection) {
            return true
        }
        guard let ydbNotifications = ydbNotifications else {
            return false
        }
        guard let primaryStorage = self.primaryStorage else {
            owsFailDebug("Missing primaryStorage.")
            return false
        }
        let connection = primaryStorage.uiDatabaseConnection
        return connection.hasChange(forCollection: collection, in: ydbNotifications) ||
            connection.didClearCollection(collection, in: ydbNotifications)
    }

    // Note that this method should only be used for model
    // collections, not key-value stores.
    @objc(didUpdateModelWithCollection:)
    public func didUpdateModel(collection: String) -> Bool {
        return didUpdate(collection: collection)
    }

    // Note: In GRDB, this will return true for _any_ key-value write.
    //       This should be acceptable.
    @objc(didUpdateKeyValueStore:)
    public func didUpdate(keyValueStore: SDSKeyValueStore) -> Bool {
        // YDB: keyValueStore.collection
        // GRDB: SDSKeyValueStore.dataStoreCollection
        return (didUpdate(collection: keyValueStore.collection) ||
                didUpdate(collection: SDSKeyValueStore.dataStoreCollection))
    }

    @objc(didUpdateInteractionId:)
    public func didUpdate(interactionId: String) -> Bool {
        if updatedInteractionIds.contains(interactionId) {
            return true
        }
        guard let ydbNotifications = ydbNotifications else {
            return false
        }
        guard let primaryStorage = self.primaryStorage else {
            owsFailDebug("Missing primaryStorage.")
            return false
        }
        let connection = primaryStorage.uiDatabaseConnection
        return connection.hasChange(forKey: interactionId,
                                    inCollection: TSInteraction.collection(),
                                    in: ydbNotifications)
    }
}

// This protocol offers a simple mechanism to observe
// all (YDB + GRDB) database changes.
//
// * These methods won't necessarily be called after _every_ transaction.
// * These methods will be called every time the YDB uiDatabaseConnection
//   or GRDB "snapshot" is updated (afterward).
// * These methods will always be called on the main thread.
// * These methods will not be called until the app is "ready."
@objc
public protocol SDSDatabaseStorageObserver: AnyObject {
    func databaseStorageDidUpdate(change: SDSDatabaseStorageChange)
    func databaseStorageDidUpdateExternally()
    func databaseStorageDidReset()
}

// MARK: -

// Only SDSDatabaseStorage should interact with this class.
//
// If you wish to observe "generic" data store changes, use:
// SDSDatabaseStorage.add(databaseStorageObserver:)
class SDSDatabaseStorageObservation {

    init() {
        self.addYDBObservers()
    }

    private func addYDBObservers() {
        guard ![.grdb, .grdbThrowawayIfMigrating ].contains(FeatureFlags.storageMode) else {
            return
        }

        NotificationCenter.default.addObserver(forName: .OWSUIDatabaseConnectionDidUpdate, object: nil, queue: nil) { [weak self] notification in
            self?.ydbDidUpdate(notification: notification)
        }
        NotificationCenter.default.addObserver(forName: .OWSUIDatabaseConnectionDidUpdateExternally, object: nil, queue: nil) { [weak self] notification in
            self?.ydbDidUpdateExternally(notification: notification)
        }
    }

    func set(grdbStorage: GRDBDatabaseStorageAdapter) {
        guard ![.ydb ].contains(FeatureFlags.storageMode) else {
            return
        }
        guard let genericDatabaseObserver = grdbStorage.genericDatabaseObserver else {
            owsFailDebug("Missing genericDatabaseObserver.")
            return
        }
        genericDatabaseObserver.appendSnapshotDelegate(self)
    }

    // MARK: - Notify

    private func notifyDidUpdate(change: SDSDatabaseStorageChange) {
        AssertIsOnMainThread()

        notifyIfNecessary {
            for databaseStorageObserver in self.databaseStorageObservers {
                databaseStorageObserver.databaseStorageDidUpdate(change: change)
            }
        }
    }

    private func notifyDidUpdateExternally() {
        AssertIsOnMainThread()

        notifyIfNecessary {
            for databaseStorageObserver in self.databaseStorageObservers {
                databaseStorageObserver.databaseStorageDidUpdateExternally()
            }
        }
    }

    private func notifyDidReset() {
        AssertIsOnMainThread()

        notifyIfNecessary {
            for databaseStorageObserver in self.databaseStorageObservers {
                databaseStorageObserver.databaseStorageDidReset()
            }
        }
    }

    private func notifyIfNecessary(block: @escaping () -> Void) {
        AssertIsOnMainThread()

        let notifyIfNecessary = {
            DispatchQueue.main.async {
                block()
            }
        }

        if CurrentAppContext().isRunningTests {
            notifyIfNecessary()
        } else {
            // Don't notify until the app is ready.
            AppReadiness.runNowOrWhenAppDidBecomeReady(notifyIfNecessary)
        }
    }

    // MARK: - Observers

    private var _databaseStorageObservers: [Weak<SDSDatabaseStorageObserver>] = []
    private var databaseStorageObservers: [SDSDatabaseStorageObserver] {
        return _databaseStorageObservers.compactMap { $0.value }
    }

    func add(databaseStorageObserver: SDSDatabaseStorageObserver) {
        AssertIsOnMainThread()

        _databaseStorageObservers = _databaseStorageObservers.filter { $0.value != nil} + [Weak(value: databaseStorageObserver)]
    }
}

// MARK: - YDB

extension SDSDatabaseStorageObservation {

    private func ydbDidUpdate(notification: Notification) {
        AssertIsOnMainThread()

        guard let notifications = notification.userInfo?[OWSUIDatabaseConnectionNotificationsKey] as? [Notification] else {
            owsFailDebug("notifications was unexpectedly nil")
            return
        }

        let updatedCollections = Set<String>()
        let updatedInteractionIds = Set<String>()
        let change = SDSDatabaseStorageChange(updatedCollections: updatedCollections,
                                              updatedInteractionIds: updatedInteractionIds,
                                              ydbNotifications: notifications)
        notifyDidUpdate(change: change)
    }

    private func ydbDidUpdateExternally(notification: Notification) {
        AssertIsOnMainThread()

        Logger.verbose("")

        notifyDidUpdateExternally()
    }
}

// MARK: - GRDB

extension SDSDatabaseStorageObservation: GRDBGenericDatabaseObserverDelegate {
    func genericDatabaseSnapshotWillUpdate() {
        // Do nothing.
    }

    func genericDatabaseSnapshotDidUpdate(updatedCollections: Set<String>,
                                          updatedInteractionIds: Set<String>) {
        AssertIsOnMainThread()

        let change = SDSDatabaseStorageChange(updatedCollections: updatedCollections,
                                              updatedInteractionIds: updatedInteractionIds)
        notifyDidUpdate(change: change)
    }

    func genericDatabaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()

        notifyDidUpdateExternally()
    }

    func genericDatabaseSnapshotDidReset() {
        AssertIsOnMainThread()

        notifyDidReset()
    }
}
