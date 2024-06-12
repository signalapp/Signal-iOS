//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol WallpaperImageStore {

    /// Pass nil to remove any existing wallpaper.
    /// Opens a sneaky transaction; should not be called from within a transaction. 
    /// - Parameter onInsert: a block to execute when inserting the new image.
    func setWallpaperImage(
        _ photo: UIImage?,
        for thread: TSThread,
        onInsert: @escaping (DBWriteTransaction) throws -> Void
    ) throws

    /// Pass nil to remove any existing wallpaper.
    /// Opens a sneaky transaction; should not be called from within a transaction.
    /// - Parameter onInsert: a block to execute when inserting the new image.
    func setGlobalThreadWallpaperImage(
        _ photo: UIImage?,
        onInsert: @escaping (DBWriteTransaction) throws -> Void
    ) throws

    func loadWallpaperImage(for thread: TSThread, tx: DBReadTransaction) -> UIImage?

    func loadGlobalThreadWallpaper(tx: DBReadTransaction) -> UIImage?

    func copyWallpaperImage(from fromThread: TSThread, to toThread: TSThread, tx: DBWriteTransaction) throws

    func resetAllWallpaperImages(tx: DBWriteTransaction) throws
}
