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
}
