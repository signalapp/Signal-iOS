//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

enum Wallpaper: String {
    static let wallpaperDidChangeNotification = NSNotification.Name("wallpaperDidChangeNotification")

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

    static func warmCaches() {
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
                let key = url.lastPathComponent
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

    static func setBuiltIn(_ wallpaper: Wallpaper, for thread: TSThread? = nil, transaction: SDSAnyWriteTransaction) throws {
        owsAssertDebug(!Thread.isMainThread)

        owsAssertDebug(wallpaper != .photo)

        try set(wallpaper, for: thread, transaction: transaction)

        transaction.addAsyncCompletion {
            NotificationCenter.default.post(name: wallpaperDidChangeNotification, object: thread?.uniqueId)
        }
    }

    static func setPhoto(_ photo: UIImage, for thread: TSThread? = nil, transaction: SDSAnyWriteTransaction) throws {
        owsAssertDebug(Thread.current != .main)

        try set(.photo, photo: photo, for: thread, transaction: transaction)

        transaction.addAsyncCompletion {
            NotificationCenter.default.post(name: wallpaperDidChangeNotification, object: thread?.uniqueId)
        }
    }

    static func view(for thread: TSThread? = nil, transaction: SDSAnyReadTransaction) -> UIView? {
        guard let wallpaper = get(for: thread, transaction: transaction) else {
            if thread != nil { return view(transaction: transaction)}
            return nil
        }

        func view(color: UIColor) -> UIView {
            let view = UIView()
            view.backgroundColor = color
            return view
        }

        if let solidColor = wallpaper.solidColor {
            let view = UIView()
            view.backgroundColor = solidColor
            return view
        } else if let gradientView = wallpaper.gradientView {
            return gradientView
        } else if case .photo = wallpaper {
            guard let photo = try? photo(for: thread) else {
                owsFailDebug("Missing photo for wallpaper \(wallpaper)")
                return nil
            }
            let imageView = UIImageView(image: photo)
            imageView.contentMode = .scaleAspectFit
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

fileprivate extension Wallpaper {
    private static let dimmingStore = SDSKeyValueStore(collection: "Wallpaper+Dimming")

    static func setDimInDarkMode(_ dimInDarkMode: Bool, for thread: TSThread?, transaction: SDSAnyWriteTransaction) throws {
        dimmingStore.setBool(dimInDarkMode, key: key(for: thread), transaction: transaction)
    }

    static func getDimInDarkMode(for thread: TSThread?, transaction: SDSAnyReadTransaction) -> Bool {
        return dimmingStore.getBool(key(for: thread), defaultValue: false, transaction: transaction)
    }
}

// MARK: - Photo management

fileprivate extension Wallpaper {
    static let appSharedDataDirectory = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
    static let wallpaperDirectory = URL(fileURLWithPath: "wallpapers", isDirectory: true, relativeTo: appSharedDataDirectory)
    static let cache = NSCache<NSString, UIImage>()

    static func ensureWallpaperDirectory() throws {
        guard OWSFileSystem.ensureDirectoryExists(wallpaperDirectory.path) else {
            throw OWSAssertionError("Failed to create ensure wallpaper directory")
        }
    }

    static func setPhoto(_ photo: UIImage, for thread: TSThread?) throws {
        owsAssertDebug(!Thread.isMainThread)

        cache.setObject(photo, forKey: key(for: thread) as NSString)

        guard let data = photo.pngData() else {
            throw OWSAssertionError("Failed to get png data for wallpaper photo")
        }
        guard !OWSFileSystem.fileOrFolderExists(url: photoURL(for: thread)) else { return }
        try ensureWallpaperDirectory()
        try data.write(to: photoURL(for: thread), options: .atomic)
    }

    static func photo(for thread: TSThread?) throws -> UIImage? {
        return try photo(for: key(for: thread))
    }

    @discardableResult
    static func photo(for key: String) throws -> UIImage? {
        if let photo = cache.object(forKey: key as NSString) { return photo }

        guard OWSFileSystem.fileOrFolderExists(url: photoURL(for: key)) else { return nil }

        let data = try Data(contentsOf: photoURL(for: key))

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
        try OWSFileSystem.deleteFileIfExists(url: photoURL(for: key))
    }

    static func photoURL(for thread: TSThread?) -> URL {
        return photoURL(for: key(for: thread))
    }

    static func photoURL(for key: String) -> URL {
        return URL(fileURLWithPath: key, relativeTo: wallpaperDirectory)
    }
}
