//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
