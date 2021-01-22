//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public enum Wallpaper: String, CaseIterable {
    public static let wallpaperDidChangeNotification = NSNotification.Name("wallpaperDidChangeNotification")

    // Solid
    case blush
    case copper
    case zorba
    case envy
    case sky
    case wildBlueYonder
    case lavender
    case shocking
    case gray
    case eden
    case violet
    case eggplant

    // Gradient
    case starshipGradient
    case woodsmokeGradient
    case coralGradient
    case ceruleanGradient
    case roseGradient
    case aquamarineGradient
    case tropicalGradient
    case blueGradient
    case bisqueGradient

    // Custom
    case photo

    public static var defaultWallpapers: [Wallpaper] { allCases.filter { $0 != .photo } }

    public static func warmCaches() {
        owsAssertDebug(!Thread.isMainThread)

        let photoURLs: [URL]
        do {
            photoURLs = try OWSFileSystem.recursiveFilesInDirectory(wallpaperDirectory.path).map { URL(fileURLWithPath: $0) }
        } catch {
            owsFailDebug("Failed to enumerate wallpaper photos \(error)")
            return
        }

        guard !photoURLs.isEmpty else { return }

        var keysToCache = [String]()
        var orphanedKeys = [String]()

        SDSDatabaseStorage.shared.read { transaction in
            for url in photoURLs {
                guard let key = url.lastPathComponent.removingPercentEncoding else {
                    owsFailDebug("Failed to remove percent encoding in key")
                    continue
                }
                guard case .photo = get(for: key, transaction: transaction) else {
                    orphanedKeys.append(key)
                    continue
                }
                keysToCache.append(key)
            }
        }

        if !orphanedKeys.isEmpty {
            Logger.info("Cleaning up \(orphanedKeys.count) orphaned wallpaper photos")
            for key in orphanedKeys {
                do {
                    try cleanupPhotoIfNecessary(for: key)
                } catch {
                    owsFailDebug("Failed to cleanup orphaned wallpaper photo \(key) \(error)")
                }
            }
        }

        for key in keysToCache {
            do {
                try photo(for: key)
            } catch {
                owsFailDebug("Failed to cache wallpaper photo \(key) \(error)")
            }
        }
    }

    public static func clear(for thread: TSThread? = nil, transaction: SDSAnyWriteTransaction) throws {
        owsAssertDebug(!Thread.isMainThread)

        enumStore.removeValue(forKey: key(for: thread), transaction: transaction)
        dimmingStore.removeValue(forKey: key(for: thread), transaction: transaction)
        try OWSFileSystem.deleteFileIfExists(url: photoURL(for: thread))

        transaction.addAsyncCompletion {
            NotificationCenter.default.post(name: wallpaperDidChangeNotification, object: thread?.uniqueId)
        }
    }

    public static func resetAll(transaction: SDSAnyWriteTransaction) throws {
        owsAssertDebug(!Thread.isMainThread)

        enumStore.removeAll(transaction: transaction)
        dimmingStore.removeAll(transaction: transaction)
        try OWSFileSystem.deleteFileIfExists(url: wallpaperDirectory)

        transaction.addAsyncCompletion {
            NotificationCenter.default.post(name: wallpaperDidChangeNotification, object: nil)
        }
    }

    public static func setBuiltIn(_ wallpaper: Wallpaper, for thread: TSThread? = nil, transaction: SDSAnyWriteTransaction) throws {
        owsAssertDebug(!Thread.isMainThread)

        owsAssertDebug(wallpaper != .photo)

        try set(wallpaper, for: thread, transaction: transaction)
    }

    public static func setPhoto(_ photo: UIImage, for thread: TSThread? = nil, transaction: SDSAnyWriteTransaction) throws {
        owsAssertDebug(Thread.current != .main)

        try set(.photo, photo: photo, for: thread, transaction: transaction)
    }

    public static func exists(for thread: TSThread? = nil, transaction: SDSAnyReadTransaction) -> Bool {
        guard get(for: thread, transaction: transaction) != nil else {
            if thread != nil { return exists(transaction: transaction) }
            return false
        }
        return true
    }

    public static func dimInDarkMode(for thread: TSThread? = nil, transaction: SDSAnyReadTransaction) -> Bool {
        guard let dimInDarkMode = getDimInDarkMode(for: thread, transaction: transaction) else {
            if thread != nil { return self.dimInDarkMode(transaction: transaction) }
            return true
        }
        return dimInDarkMode
    }

    public static func view(for thread: TSThread? = nil, transaction: SDSAnyReadTransaction) -> UIView? {
        AssertIsOnMainThread()

        guard let wallpaper: Wallpaper = {
            if let wallpaper = get(for: thread, transaction: transaction) {
                return wallpaper
            } else if thread != nil, let wallpaper = get(for: nil, transaction: transaction) {
                return wallpaper
            } else {
                return nil
            }
        }() else { return nil }

        let photo: UIImage? = {
            guard case .photo = wallpaper else { return nil }
            if let photo = try? self.photo(for: thread) {
                return photo
            } else if thread != nil, let photo = try? self.photo(for: nil) {
                return photo
            } else {
                return nil
            }
        }()

        if case .photo = wallpaper, photo == nil {
            owsFailDebug("Missing photo for wallpaper \(wallpaper)")
            return nil
        }

        guard let view = view(for: wallpaper, photo: photo) else { return nil }

        if Theme.isDarkThemeEnabled && dimInDarkMode(for: thread, transaction: transaction) {
            let dimmingView = UIView()
            dimmingView.backgroundColor = .ows_blackAlpha20
            view.addSubview(dimmingView)
            dimmingView.autoPinEdgesToSuperviewEdges()
        }

        return view
    }

    public static func view(for wallpaper: Wallpaper, photo: UIImage? = nil) -> UIView? {
        AssertIsOnMainThread()

        if let solidColor = wallpaper.solidColor {
            let view = UIView()
            view.backgroundColor = solidColor
            return view
        } else if let gradientView = wallpaper.gradientView {
            return gradientView
        } else if case .photo = wallpaper {
            guard let photo = photo else {
                owsFailDebug("Missing photo for wallpaper \(wallpaper)")
                return nil
            }
            let imageView = UIImageView(image: photo)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            return imageView
        } else {
            owsFailDebug("Unexpected wallpaper type \(wallpaper)")
            return nil
        }
    }
}

// MARK: -

fileprivate extension Wallpaper {
    static func key(for thread: TSThread?) -> String {
        return thread?.uniqueId ?? "global"
    }
}

// MARK: -

fileprivate extension Wallpaper {
    private static let enumStore = SDSKeyValueStore(collection: "Wallpaper+Enum")

    static func set(_ wallpaper: Wallpaper?, photo: UIImage? = nil, for thread: TSThread?, transaction: SDSAnyWriteTransaction) throws {
        owsAssertDebug(photo == nil || wallpaper == .photo)

        try cleanupPhotoIfNecessary(for: thread)

        if let photo = photo { try setPhoto(photo, for: thread) }

        enumStore.setString(wallpaper?.rawValue, key: key(for: thread), transaction: transaction)

        transaction.addAsyncCompletion {
            NotificationCenter.default.post(name: wallpaperDidChangeNotification, object: thread?.uniqueId)
        }
    }

    static func get(for thread: TSThread?, transaction: SDSAnyReadTransaction) -> Wallpaper? {
        return get(for: key(for: thread), transaction: transaction)
    }

    static func get(for key: String, transaction: SDSAnyReadTransaction) -> Wallpaper? {
        guard let rawValue = enumStore.getString(key, transaction: transaction) else {
            return nil
        }
        guard let wallpaper = Wallpaper(rawValue: rawValue) else {
            owsFailDebug("Unexpectedly wallpaper \(rawValue)")
            return nil
        }
        return wallpaper
    }
}

// MARK: -

extension Wallpaper {
    private static let dimmingStore = SDSKeyValueStore(collection: "Wallpaper+Dimming")

    public static func setDimInDarkMode(_ dimInDarkMode: Bool, for thread: TSThread?, transaction: SDSAnyWriteTransaction) throws {
        dimmingStore.setBool(dimInDarkMode, key: key(for: thread), transaction: transaction)

        transaction.addAsyncCompletion {
            NotificationCenter.default.post(name: wallpaperDidChangeNotification, object: thread?.uniqueId)
        }
    }

    fileprivate static func getDimInDarkMode(for thread: TSThread?, transaction: SDSAnyReadTransaction) -> Bool? {
        return dimmingStore.getBool(key(for: thread), transaction: transaction)
    }
}

// MARK: - Photo management

fileprivate extension Wallpaper {
    static let appSharedDataDirectory = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
    static let wallpaperDirectory = URL(fileURLWithPath: "Wallpapers", isDirectory: true, relativeTo: appSharedDataDirectory)
    static let cache = NSCache<NSString, UIImage>()

    static func ensureWallpaperDirectory() throws {
        guard OWSFileSystem.ensureDirectoryExists(wallpaperDirectory.path) else {
            throw OWSAssertionError("Failed to create ensure wallpaper directory")
        }
    }

    static func setPhoto(_ photo: UIImage, for thread: TSThread?) throws {
        owsAssertDebug(!Thread.isMainThread)

        cache.setObject(photo, forKey: key(for: thread) as NSString)

        guard let data = photo.jpegData(compressionQuality: 0.8) else {
            throw OWSAssertionError("Failed to get jpg data for wallpaper photo")
        }
        guard !OWSFileSystem.fileOrFolderExists(url: try photoURL(for: thread)) else { return }
        try ensureWallpaperDirectory()
        try data.write(to: try photoURL(for: thread), options: .atomic)
    }

    static func photo(for thread: TSThread?) throws -> UIImage? {
        return try photo(for: key(for: thread))
    }

    @discardableResult
    static func photo(for key: String) throws -> UIImage? {
        if let photo = cache.object(forKey: key as NSString) { return photo }

        guard OWSFileSystem.fileOrFolderExists(url: try photoURL(for: key)) else { return nil }

        let data = try Data(contentsOf: try photoURL(for: key))

        guard let photo = UIImage(data: data) else {
            owsFailDebug("Failed to initialize wallpaper photo from data")
            try cleanupPhotoIfNecessary(for: key)
            return nil
        }

        cache.setObject(photo, forKey: key as NSString)

        return photo
    }

    static func cleanupPhotoIfNecessary(for thread: TSThread?) throws {
        try cleanupPhotoIfNecessary(for: key(for: thread))
    }

    static func cleanupPhotoIfNecessary(for key: String) throws {
        owsAssertDebug(!Thread.isMainThread)

        cache.removeObject(forKey: key as NSString)
        try OWSFileSystem.deleteFileIfExists(url: try photoURL(for: key))
    }

    static func photoURL(for thread: TSThread?) throws -> URL {
        return try photoURL(for: key(for: thread))
    }

    static func photoURL(for key: String) throws -> URL {
        guard let filename = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            throw OWSAssertionError("Failed to percent encode filename")
        }
        return URL(fileURLWithPath: filename, relativeTo: wallpaperDirectory)
    }
}
