//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public class WallpaperStore {
    public static let wallpaperDidChangeNotification = NSNotification.Name("wallpaperDidChangeNotification")

    private enum Constants {
        static let globalPersistenceKey = "global"
    }

    private let enumStore: KeyValueStore
    private let dimmingStore: KeyValueStore
    private let notificationScheduler: Scheduler

    public let customPhotoDirectory = URL(
        fileURLWithPath: "Wallpapers",
        isDirectory: true,
        relativeTo: URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
    )

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

    public static func customPhotoFilename(for threadUniqueId: String?) throws -> String {
        let persistenceKey = Self.persistenceKey(for: threadUniqueId)
        guard let filename = persistenceKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            throw OWSAssertionError("Failed to percent encode filename")
        }
        return filename
    }

    public func customPhotoUrl(for threadUniqueId: String?) throws -> URL {
        let filename = try Self.customPhotoFilename(for: threadUniqueId)
        return URL(fileURLWithPath: filename, isDirectory: false, relativeTo: customPhotoDirectory)
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

    public func removeCustomPhoto(for threadUniqueId: String?) throws {
        try OWSFileSystem.deleteFileIfExists(url: customPhotoUrl(for: threadUniqueId))
    }

    public func reset(for thread: TSThread?, tx: DBWriteTransaction) throws {
        let threadUniqueId = thread?.uniqueId
        enumStore.removeValue(forKey: Self.persistenceKey(for: threadUniqueId), transaction: tx)
        dimmingStore.removeValue(forKey: Self.persistenceKey(for: threadUniqueId), transaction: tx)
        try removeCustomPhoto(for: threadUniqueId)
        postWallpaperDidChangeNotification(for: threadUniqueId, tx: tx)
    }

    public func resetAll(tx: DBWriteTransaction) throws {
        enumStore.removeAll(transaction: tx)
        dimmingStore.removeAll(transaction: tx)
        try OWSFileSystem.deleteFileIfExists(url: customPhotoDirectory)
        postWallpaperDidChangeNotification(for: nil, tx: tx)
    }

    private func postWallpaperDidChangeNotification(for threadUniqueId: String?, tx: DBWriteTransaction) {
        tx.addAsyncCompletion(on: notificationScheduler) {
            NotificationCenter.default.post(name: Self.wallpaperDidChangeNotification, object: threadUniqueId)
        }
    }
}
