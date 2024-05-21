//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class WallpaperImageStoreImpl: WallpaperImageStore {

    public init() {}

    public func setWallpaperImage(_ photo: UIImage?, for thread: TSThread, tx: DBWriteTransaction) throws {
        fatalError("Unimplemented")
    }

    public func setGlobalThreadWallpaperImage(_ photo: UIImage?, tx: DBWriteTransaction) throws {
        fatalError("Unimplemented")
    }

    public func loadWallpaperImage(for thread: TSThread, tx: DBReadTransaction) -> UIImage? {
        fatalError("Unimplemented")
    }

    public func loadGlobalThreadWallpaper(tx: DBReadTransaction) -> UIImage? {
        fatalError("Unimplemented")
    }

    public func copyWallpaperImage(from fromThread: TSThread, to toThread: TSThread, tx: DBWriteTransaction) throws {
        fatalError("Unimplemented")
    }

    public func resetAllWallpaperImages(tx: DBWriteTransaction) throws {
        fatalError("Unimplemented")
    }
}
