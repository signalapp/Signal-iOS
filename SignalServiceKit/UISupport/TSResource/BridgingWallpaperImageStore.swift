//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class BridgingWallpaperImageStore: WallpaperImageStore {

    private let db: DB
    private let wallpaperStore: WallpaperImageStoreImpl

    public init(
        db: DB,
        wallpaperStore: WallpaperImageStoreImpl
    ) {
        self.db = db
        self.wallpaperStore = wallpaperStore
    }

    public func setWallpaperImage(
        _ photo: UIImage?,
        for thread: TSThread,
        onInsert: @escaping (DBWriteTransaction) throws -> Void
    ) throws {
        if FeatureFlags.writeThreadWallpaperV2Attachments {
            try wallpaperStore.setWallpaperImage(photo, for: thread, onInsert: onInsert)
        } else {
            try LegacyWallpaperImageStore.setPhoto(photo, for: thread)
            try db.write { tx in
                try onInsert(tx)
            }
        }
    }

    public func setGlobalThreadWallpaperImage(
        _ photo: UIImage?,
        onInsert: @escaping (DBWriteTransaction) throws -> Void
    ) throws {
        if FeatureFlags.writeThreadWallpaperV2Attachments {
            try wallpaperStore.setGlobalThreadWallpaperImage(photo, onInsert: onInsert)
        } else {
            try LegacyWallpaperImageStore.setPhoto(photo, for: nil)
            try db.write { tx in
                try onInsert(tx)
            }
        }
    }

    public func loadWallpaperImage(for thread: TSThread, tx: DBReadTransaction) -> UIImage? {
        if FeatureFlags.readThreadWallpaperV2Attachments {
            return wallpaperStore.loadWallpaperImage(for: thread, tx: tx)
        } else {
            return LegacyWallpaperImageStore.loadPhoto(for: thread)
        }
    }

    public func loadGlobalThreadWallpaper(tx: DBReadTransaction) -> UIImage? {
        if FeatureFlags.readThreadWallpaperV2Attachments {
            return wallpaperStore.loadGlobalThreadWallpaper(tx: tx)
        } else {
            return LegacyWallpaperImageStore.loadPhoto(for: nil)
        }
    }

    public func copyWallpaperImage(from fromThread: TSThread, to toThread: TSThread, tx: DBWriteTransaction) throws {
        if FeatureFlags.writeThreadWallpaperV2Attachments {
            try wallpaperStore.copyWallpaperImage(from: fromThread, to: toThread, tx: tx)
        } else {
            try LegacyWallpaperImageStore.copyPhoto(from: fromThread, to: toThread)
        }
    }

    public func resetAllWallpaperImages(tx: DBWriteTransaction) throws {
        if FeatureFlags.writeThreadWallpaperV2Attachments {
            try wallpaperStore.resetAllWallpaperImages(tx: tx)
        } else {
            try LegacyWallpaperImageStore.resetAll()
        }
    }
}
