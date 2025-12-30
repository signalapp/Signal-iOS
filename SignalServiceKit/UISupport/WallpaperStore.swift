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

    private let wallpaperImageStore: WallpaperImageStore
    private let enumStore: KeyValueStore
    private let dimmingStore: KeyValueStore

    init(
        wallpaperImageStore: WallpaperImageStore,
    ) {
        self.enumStore = KeyValueStore(collection: "Wallpaper+Enum")
        self.dimmingStore = KeyValueStore(collection: "Wallpaper+Dimming")
        self.wallpaperImageStore = wallpaperImageStore
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

    public func setBuiltIn(_ wallpaper: Wallpaper, for thread: TSThread? = nil) async throws {
        owsAssertDebug(wallpaper != .photo)

        try await _set(wallpaper, for: thread)
    }

    public func setPhoto(_ photo: UIImage, for thread: TSThread? = nil) async throws {
        try await _set(.photo, photo: photo, for: thread)
    }

    private func _set(_ wallpaper: Wallpaper?, photo: UIImage? = nil, for thread: TSThread?) async throws {
        owsAssertDebug(photo == nil || wallpaper == .photo)

        let onInsert = { [self] (tx: DBWriteTransaction) throws -> Void in
            self.setWallpaperType(wallpaper, for: thread?.uniqueId, tx: tx)
        }

        if let thread {
            try await wallpaperImageStore.setWallpaperImage(photo, for: thread, onInsert: onInsert)
        } else {
            try await wallpaperImageStore.setGlobalThreadWallpaperImage(photo, onInsert: onInsert)
        }
    }

    /// Set just the type; doesn't override any wallpaper image that may be set.
    public func setWallpaperType(_ wallpaper: Wallpaper?, for threadUniqueId: String?, tx: DBWriteTransaction) {
        enumStore.setString(wallpaper?.rawValue, key: Self.persistenceKey(for: threadUniqueId), transaction: tx)
        postWallpaperDidChangeNotification(for: threadUniqueId, tx: tx)
    }

    public func fetchWallpaper(for threadUniqueId: String?, tx: DBReadTransaction) -> Wallpaper? {
        guard let raw = enumStore.getString(Self.persistenceKey(for: threadUniqueId), transaction: tx) else {
            return nil
        }
        guard let wallpaper = Wallpaper(rawValue: raw) else {
            owsFailDebug("Unexpected wallpaper \(raw)")
            return nil
        }
        return wallpaper
    }

    /// Return either the per-thread wallpaper setting, or the global setting if none is set on the thread.
    public func fetchWallpaperForRendering(
        for threadUniqueId: String?,
        tx: DBReadTransaction,
    ) -> Wallpaper? {
        return Self.fetchResolvedValue(for: threadUniqueId) {
            return fetchWallpaper(for: $0, tx: tx)
        }
    }

    /// Fetches a thread-specific value (if set) or the global value.
    public static func fetchResolvedValue<ThreadType, ResultType>(for thread: ThreadType?, fetchBlock: (ThreadType?) -> ResultType?) -> ResultType? {
        if let thread, let threadValue = fetchBlock(thread) { return threadValue }
        return fetchBlock(nil)
    }

    public func fetchUniqueThreadIdsWithWallpaper(tx: DBReadTransaction) -> [String?] {
        return enumStore.allKeys(transaction: tx).map { Self.threadUniqueId(for: $0) }
    }

    public func setDimInDarkMode(_ dimInDarkMode: Bool?, for threadUniqueId: String?, tx: DBWriteTransaction) {
        let key = Self.persistenceKey(for: threadUniqueId)
        if let dimInDarkMode {
            dimmingStore.setBool(dimInDarkMode, key: key, transaction: tx)
        } else {
            dimmingStore.removeValue(forKey: key, transaction: tx)
        }
        postWallpaperDidChangeNotification(for: threadUniqueId, tx: tx)
    }

    public func fetchDimInDarkMode(for threadUniqueId: String?, tx: DBReadTransaction) -> Bool? {
        return dimmingStore.getBool(Self.persistenceKey(for: threadUniqueId), transaction: tx)
    }

    public func fetchDimInDarkModeForRendering(for threadUniqueId: String?, tx: DBReadTransaction) -> Bool {
        return Self.fetchResolvedValue(for: threadUniqueId) {
            return fetchDimInDarkMode(for: $0, tx: tx)
        } ?? Wallpaper.shouldDimInDarkModeDefaultValue
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
        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: Self.wallpaperDidChangeNotification, object: threadUniqueId)
        }
    }
}
