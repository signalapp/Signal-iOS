//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

extension ConversationViewController {

    func setupWallpaper() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(wallpaperDidChange),
            name: Wallpaper.wallpaperDidChangeNotification,
            object: nil
        )

        updateWallpaperView()
    }

    @objc
    func wallpaperDidChange(_ notification: Notification) {
        guard notification.object == nil || (notification.object as? String) == thread.uniqueId else { return }
        updateWallpaperView()

        updateConversationStyle()
    }

    func updateWallpaperView() {
        AssertIsOnMainThread()

        guard let wallpaperView = databaseStorage.read(block: { transaction in
            Wallpaper.view(for: self.thread, transaction: transaction)
        }) else {
            backgroundContainer.set(wallpaperView: nil)
            return
        }

        backgroundContainer.set(wallpaperView: wallpaperView)
    }
}
