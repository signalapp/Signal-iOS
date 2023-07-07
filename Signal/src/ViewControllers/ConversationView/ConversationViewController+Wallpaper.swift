//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalServiceKit
import SignalUI

extension ConversationViewController {
    func setUpWallpaper() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(wallpaperDidChange),
            name: WallpaperStore.wallpaperDidChangeNotification,
            object: nil
        )
        updateWallpaperViewBuilder()
    }

    @objc
    private func wallpaperDidChange(_ notification: Notification) {
        guard notification.object == nil || (notification.object as? String) == thread.uniqueId else { return }
        updateWallpaperViewBuilder()
        updateConversationStyle()
    }

    func updateWallpaperViewBuilder() {
        viewState.wallpaperViewBuilder = databaseStorage.read { tx in Wallpaper.viewBuilder(for: thread, tx: tx) }
        updateWallpaperView()
    }

    func updateWallpaperView() {
        AssertIsOnMainThread()
        backgroundContainer.set(wallpaperView: viewState.wallpaperViewBuilder?.build())
    }
}
