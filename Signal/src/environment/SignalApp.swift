//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension SignalApp {
    @objc
    func warmAvailableEmojiCacheAsync() {
        DispatchQueue.global(qos: .background).async {
            Emoji.warmAvailableCache()
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
}
