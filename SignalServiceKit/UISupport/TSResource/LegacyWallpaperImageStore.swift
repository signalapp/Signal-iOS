//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class LegacyWallpaperImageStore {

    public static func setPhoto(_ photo: UIImage?, for thread: TSThread?) throws {
        guard let photo else {
            try removeCustomPhoto(for: thread?.uniqueId)
            return
        }

        owsAssertDebug(!Thread.isMainThread)
        guard let data = photo.jpegData(compressionQuality: 0.8) else {
            throw OWSAssertionError("Failed to get jpg data for wallpaper photo")
        }
        try ensureWallpaperDirectory()
        try data.write(to: customPhotoUrl(for: thread?.uniqueId), options: .atomic)
    }

    public static func loadPhoto(for thread: TSThread?) -> UIImage? {
        do {
            let customPhotoUrl = try customPhotoUrl(for: thread?.uniqueId)
            let customPhotoData = try Data(contentsOf: customPhotoUrl)
            guard let customPhoto = UIImage(data: customPhotoData) else {
                try removeCustomPhoto(for: thread?.uniqueId)
                throw OWSGenericError("Couldn't initialize wallpaper photo from data.")
            }
            return customPhoto
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile, POSIXError.ENOENT {
            // the file doesn't exist -- this is fine
            return nil
        } catch {
            Logger.warn("Couldn't load wallpaper photo.")
            return nil
        }
    }

    public static func copyPhoto(from fromThread: TSThread, to toThread: TSThread) throws {
        try removeCustomPhoto(for: toThread.uniqueId)
        try FileManager.default.copyItem(at: customPhotoUrl(for: fromThread.uniqueId), to: customPhotoUrl(for: toThread.uniqueId))
    }

    public static func resetAll() throws {
        try OWSFileSystem.deleteFileIfExists(url: customPhotoDirectory)
    }

    // MARK: - Private

    private enum Constants {
        static let globalPersistenceKey = "global"
    }

    private static func persistenceKey(for threadUniqueId: String?) -> String {
        return threadUniqueId ?? Constants.globalPersistenceKey
    }

    public static func customPhotoFilename(for threadUniqueId: String?) throws -> String {
        let persistenceKey = Self.persistenceKey(for: threadUniqueId)
        guard let filename = persistenceKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            throw OWSAssertionError("Failed to percent encode filename")
        }
        return filename
    }

    private static func customPhotoUrl(for threadUniqueId: String?) throws -> URL {
        let filename = try Self.customPhotoFilename(for: threadUniqueId)
        return URL(fileURLWithPath: filename, isDirectory: false, relativeTo: customPhotoDirectory)
    }

    private static func removeCustomPhoto(for threadUniqueId: String?) throws {
        try OWSFileSystem.deleteFileIfExists(url: customPhotoUrl(for: threadUniqueId))
    }

    private static func ensureWallpaperDirectory() throws {
        guard OWSFileSystem.ensureDirectoryExists(customPhotoDirectory.path) else {
            throw OWSAssertionError("Failed to create ensure wallpaper directory")
        }
    }

    // MARK: - Orphan Data Cleaner

    // Exposed for OrphanDataCleaner
    public static let customPhotoDirectory = URL(
        fileURLWithPath: "Wallpapers",
        isDirectory: true,
        relativeTo: URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
    )

    public static func allCustomPhotoRelativePaths(tx: DBReadTransaction) -> Set<String> {
        Set(allUniqueThreadIdsWithCustomPhotos(tx: tx).compactMap { try? customPhotoFilename(for: $0) })
    }

    private static func allUniqueThreadIdsWithCustomPhotos(tx: DBReadTransaction) -> [String?] {
        let wallpaperStore = DependenciesBridge.shared.wallpaperStore
        let uniqueThreadIds = wallpaperStore.fetchUniqueThreadIdsWithWallpaper(tx: tx)
        return uniqueThreadIds.filter { wallpaperStore.fetchWallpaper(for: $0, tx: tx) == "photo" }
    }
}
