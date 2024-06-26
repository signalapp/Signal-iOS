//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class WallpaperStore {
    public static let wallpaperDidChangeNotification = NSNotification.Name("wallpaperDidChangeNotification")

    private enum Constants {
        static let globalPersistenceKey = "global"
    }

    private let enumStore: KeyValueStore
    private let dimmingStore: KeyValueStore
    private let notificationScheduler: Scheduler

    init(keyValueStoreFactory: KeyValueStoreFactory, notificationScheduler: Scheduler) {
        self.enumStore = keyValueStoreFactory.keyValueStore(collection: "Wallpaper+Enum")
        self.dimmingStore = keyValueStoreFactory.keyValueStore(collection: "Wallpaper+Dimming")
        self.notificationScheduler = notificationScheduler
    }

    // MARK: - Persistence Keys

    private static func persistenceKey(for threadUniqueId: String?) -> String {
        return threadUniqueId ?? Constants.globalPersistenceKey
    }

    private static func threadUniqueId(for persistenceKey: String) -> String? {
        if persistenceKey == Constants.globalPersistenceKey {
            return nil
        }
        return persistenceKey
    }

    // MARK: - Getters & Setters

    public func setWallpaper(_ rawValue: String?, for threadUniqueId: String?, tx: DBWriteTransaction) {
        enumStore.setString(rawValue, key: Self.persistenceKey(for: threadUniqueId), transaction: tx)
        postWallpaperDidChangeNotification(for: threadUniqueId, tx: tx)
    }

    public func fetchWallpaper(for threadUniqueId: String?, tx: DBReadTransaction) -> String? {
        return enumStore.getString(Self.persistenceKey(for: threadUniqueId), transaction: tx)
    }

    public func fetchUniqueThreadIdsWithWallpaper(tx: DBReadTransaction) -> [String?] {
        return enumStore.allKeys(transaction: tx).map { Self.threadUniqueId(for: $0) }
    }

    public func setDimInDarkMode(_ dimInDarkMode: Bool, for threadUniqueId: String?, tx: DBWriteTransaction) {
        dimmingStore.setBool(dimInDarkMode, key: Self.persistenceKey(for: threadUniqueId), transaction: tx)
        postWallpaperDidChangeNotification(for: threadUniqueId, tx: tx)
    }

    public func fetchDimInDarkMode(for threadUniqueId: String?, tx: DBReadTransaction) -> Bool? {
        return dimmingStore.getBool(Self.persistenceKey(for: threadUniqueId), transaction: tx)
    }

    // MARK: - Resetting Values

    public func reset(for thread: TSThread?, tx: DBWriteTransaction) throws {
        let threadUniqueId = thread?.uniqueId
        enumStore.removeValue(forKey: Self.persistenceKey(for: threadUniqueId), transaction: tx)
        dimmingStore.removeValue(forKey: Self.persistenceKey(for: threadUniqueId), transaction: tx)
        postWallpaperDidChangeNotification(for: threadUniqueId, tx: tx)
    }

    public func resetAll(tx: DBWriteTransaction) throws {
        enumStore.removeAll(transaction: tx)
        dimmingStore.removeAll(transaction: tx)
        postWallpaperDidChangeNotification(for: nil, tx: tx)
    }

    private func postWallpaperDidChangeNotification(for threadUniqueId: String?, tx: DBWriteTransaction) {
        tx.addAsyncCompletion(on: notificationScheduler) {
            NotificationCenter.default.post(name: Self.wallpaperDidChangeNotification, object: threadUniqueId)
        }
    }
}
