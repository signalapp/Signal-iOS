//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class MockWallpaperImageStore: WallpaperImageStore {

    public func setWallpaperImage(
        _ photo: UIImage?,
        for thread: TSThread,
        onInsert: @escaping (DBWriteTransaction) throws -> Void
    ) throws {
        // Do nothing
    }

    public func setGlobalThreadWallpaperImage(
        _ photo: UIImage?,
        onInsert: @escaping (DBWriteTransaction) throws -> Void
    ) throws {
        // Do nothing
    }

    public func loadWallpaperImage(for thread: TSThread, tx: DBReadTransaction) -> UIImage? {
        return nil
    }

    public func loadGlobalThreadWallpaper(tx: DBReadTransaction) -> UIImage? {
        return nil
    }

    public func copyWallpaperImage(from fromThread: TSThread, to toThread: TSThread, tx: DBWriteTransaction) throws {
        // Do nothing
    }

    public func resetAllWallpaperImages(tx: DBWriteTransaction) throws {
        // Do nothing
    }
}

#endif
