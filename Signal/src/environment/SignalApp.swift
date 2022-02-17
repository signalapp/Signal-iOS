//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import SignalUI
import UIKit

extension SignalApp {
    @objc
    func warmCachesAsync() {
        DispatchQueue.global(qos: .background).async {
            InstrumentsMonitor.measure(category: "appstart", parent: "caches", name: "warmEmojiCache") {
                Emoji.warmAvailableCache()
            }
        }

        DispatchQueue.global(qos: .background).async {
            InstrumentsMonitor.measure(category: "appstart", parent: "caches", name: "warmWallpaperCaches") {
                Wallpaper.warmCaches()
            }
        }
    }

    @objc
    func dismissAllModals(animated: Bool, completion: (() -> Void)?) {
        guard let window = CurrentAppContext().mainWindow else {
            owsFailDebug("Missing window.")
            return
        }
        guard let rootViewController = window.rootViewController else {
            owsFailDebug("Missing rootViewController.")
            return
        }
        let hasModal = rootViewController.presentedViewController != nil
        if hasModal {
            rootViewController.dismiss(animated: animated, completion: completion)
        } else {
            completion?()
        }
    }

    func showAppSettings(mode: ShowAppSettingsMode) {
        guard let conversationSplitViewController = self.conversationSplitViewControllerForSwift else {
            owsFailDebug("Missing conversationSplitViewController.")
            return
        }
        conversationSplitViewController.showAppSettingsWithMode(mode)
    }
}
