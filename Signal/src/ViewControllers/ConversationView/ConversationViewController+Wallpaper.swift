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

        updateWallpaper()
    }

    @objc
    func wallpaperDidChange(_ notification: Notification) {
        guard notification.object == nil || (notification.object as? String) == thread.uniqueId else { return }
        updateWallpaper()
    }

    @objc
    func updateWallpaper() {
        let hadWallpaper = threadViewModel.hasWallpaper

        func applyWallpaperChange(hasWallpaper: Bool) {
            guard hasWallpaper != hadWallpaper else { return }
            viewState.threadViewModel = databaseStorage.read { ThreadViewModel(thread: thread, transaction: $0) }
            updateConversationStyle()
        }

        var wallpaperView: UIView?
        let thread = self.thread
        databaseStorage.asyncRead { transaction in
            wallpaperView = Wallpaper.view(for: thread, transaction: transaction)
        } completion: {
            self.viewState.wallpaperContainer.removeAllSubviews()

            guard let wallpaperView = wallpaperView else {
                self.viewState.wallpaperContainer.backgroundColor = Theme.backgroundColor
                applyWallpaperChange(hasWallpaper: false)
                return
            }

            applyWallpaperChange(hasWallpaper: true)

            self.viewState.wallpaperContainer.backgroundColor = .clear

            self.viewState.wallpaperContainer.addSubview(wallpaperView)
            wallpaperView.autoPinEdgesToSuperviewEdges()
        }
    }
}
