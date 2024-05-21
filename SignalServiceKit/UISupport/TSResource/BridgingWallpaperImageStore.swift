//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class BridgingWallpaperImageStore: WallpaperImageStore {

    private let wallpaperStore: WallpaperImageStoreImpl

    public init(wallpaperStore: WallpaperImageStoreImpl) {
        self.wallpaperStore = wallpaperStore
    }

    public func setWallpaperImage(_ photo: UIImage?, for thread: TSThread, tx: DBWriteTransaction) throws {
        if FeatureFlags.v2ThreadAttachments {
            try wallpaperStore.setWallpaperImage(photo, for: thread, tx: tx)
        } else {
            try LegacyWallpaperImageStore.setPhoto(photo, for: thread)
        }
    }

    public func setGlobalThreadWallpaperImage(_ photo: UIImage?, tx: DBWriteTransaction) throws {
        if FeatureFlags.v2ThreadAttachments {
            try wallpaperStore.setGlobalThreadWallpaperImage(photo, tx: tx)
        } else {
            try LegacyWallpaperImageStore.setPhoto(photo, for: nil)
        }
    }

    public func loadWallpaperImage(for thread: TSThread, tx: DBReadTransaction) -> UIImage? {
        if FeatureFlags.v2ThreadAttachments {
            return wallpaperStore.loadWallpaperImage(for: thread, tx: tx)
        } else {
            return LegacyWallpaperImageStore.loadPhoto(for: thread)
        }
    }

    public func loadGlobalThreadWallpaper(tx: DBReadTransaction) -> UIImage? {
        if FeatureFlags.v2ThreadAttachments {
            return wallpaperStore.loadGlobalThreadWallpaper(tx: tx)
        } else {
            return LegacyWallpaperImageStore.loadPhoto(for: nil)
        }
    }

    public func copyWallpaperImage(from fromThread: TSThread, to toThread: TSThread, tx: DBWriteTransaction) throws {
        if FeatureFlags.v2ThreadAttachments {
            try wallpaperStore.copyWallpaperImage(from: fromThread, to: toThread, tx: tx)
        } else {
            try LegacyWallpaperImageStore.copyPhoto(from: fromThread, to: toThread)
        }
    }

    public func resetAllWallpaperImages(tx: DBWriteTransaction) throws {
        if FeatureFlags.v2ThreadAttachments {
            try wallpaperStore.resetAllWallpaperImages(tx: tx)
        } else {
            try LegacyWallpaperImageStore.resetAll()
        }
    }
}
