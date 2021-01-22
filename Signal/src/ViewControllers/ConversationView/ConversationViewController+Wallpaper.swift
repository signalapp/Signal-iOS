//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
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

        let hasWallpaper = databaseStorage.read { transaction in
            Wallpaper.exists(for: self.thread, transaction: transaction)
        }

        updateConversationStyle(hasWallpaper: hasWallpaper)
    }

    @objc
    func updateWallpaperView() {
        AssertIsOnMainThread()

        viewState.wallpaperContainer.removeAllSubviews()

        guard let wallpaperView = databaseStorage.read(block: { transaction in
            Wallpaper.view(for: self.thread, transaction: transaction)
        }) else {
            viewState.wallpaperContainer.backgroundColor = Theme.backgroundColor
            return
        }

        viewState.wallpaperContainer.backgroundColor = .clear

        viewState.wallpaperContainer.addSubview(wallpaperView)
        wallpaperView.autoPinEdgesToSuperviewEdges()
    }
}
