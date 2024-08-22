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
        try wallpaperStore.setWallpaperImage(photo, for: thread, onInsert: onInsert)
    }

    public func setGlobalThreadWallpaperImage(
        _ photo: UIImage?,
        onInsert: @escaping (DBWriteTransaction) throws -> Void
    ) throws {
        try wallpaperStore.setGlobalThreadWallpaperImage(photo, onInsert: onInsert)
    }

    public func loadWallpaperImage(for thread: TSThread, tx: DBReadTransaction) -> UIImage? {
        return wallpaperStore.loadWallpaperImage(for: thread, tx: tx)
    }

    public func loadGlobalThreadWallpaper(tx: DBReadTransaction) -> UIImage? {
        return wallpaperStore.loadGlobalThreadWallpaper(tx: tx)
    }

    public func copyWallpaperImage(from fromThread: TSThread, to toThread: TSThread, tx: DBWriteTransaction) throws {
        try wallpaperStore.copyWallpaperImage(from: fromThread, to: toThread, tx: tx)
    }

    public func resetAllWallpaperImages(tx: DBWriteTransaction) throws {
        try wallpaperStore.resetAllWallpaperImages(tx: tx)
    }
}
