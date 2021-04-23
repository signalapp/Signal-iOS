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

    func wallpaperDidChange(_ notification: Notification) {
        guard notification.object == nil || (notification.object as? String) == thread.uniqueId else { return }
        updateWallpaperView()

        let hasWallpaper = databaseStorage.read { transaction in
            Wallpaper.exists(for: self.thread, transaction: transaction)
        }

        updateConversationStyle(hasWallpaper: hasWallpaper)
    }

    func updateWallpaperView() {
        AssertIsOnMainThread()

        viewState.wallpaperContainer.removeAllSubviews()
        viewState.wallpaperView = nil

        guard let wallpaperView = databaseStorage.read(block: { transaction in
            Wallpaper.view(for: self.thread,
                           maskDataSource: self,
                           transaction: transaction)
        }) else {
            viewState.wallpaperContainer.backgroundColor = Theme.backgroundColor
            return
        }

        viewState.wallpaperContainer.backgroundColor = .clear
        viewState.wallpaperContainer.addSubview(wallpaperView)
        wallpaperView.autoPinEdgesToSuperviewEdges()
        viewState.wallpaperView = wallpaperView
    }

    public func updateWallpaperMask() {
        AssertIsOnMainThread()

        viewState.wallpaperView?.updateMask()
    }
}

// MARK: -

extension ConversationViewController: WallpaperMaskDataSource {
    public func buildWallpaperMask(_ wallpaperMaskBuilder: WallpaperMaskBuilder) {
        for cell in collectionView.visibleCells {
            guard let cell = cell as? CVCell else {
                owsFailDebug("Invalid cell.")
                continue
            }
            cell.buildWallpaperMask(wallpaperMaskBuilder)
        }
    }
}
