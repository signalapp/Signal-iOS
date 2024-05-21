//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol WallpaperImageStore {

    /// Pass nil to remove any existing wallpaper.
    func setWallpaperImage(_ photo: UIImage?, for thread: TSThread, tx: DBWriteTransaction) throws

    /// Pass nil to remove any existing wallpaper.
    func setGlobalThreadWallpaperImage(_ photo: UIImage?, tx: DBWriteTransaction) throws

    func loadWallpaperImage(for thread: TSThread, tx: DBReadTransaction) -> UIImage?

    func loadGlobalThreadWallpaper(tx: DBReadTransaction) -> UIImage?

    func copyWallpaperImage(from fromThread: TSThread, to toThread: TSThread, tx: DBWriteTransaction) throws

    func resetAllWallpaperImages(tx: DBWriteTransaction) throws
}
