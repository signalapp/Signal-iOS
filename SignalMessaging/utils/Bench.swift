//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public func BenchAsync(title: String, block: (() -> Void) -> Void) {
    let startTime = CFAbsoluteTimeGetCurrent()

    block {
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        Logger.debug("[Bench] title: \(title), duration: \(timeElapsed)")
    }
}

public func Bench(title: String, block: () -> Void) {
    BenchAsync(title: title) { finish in
        block()
        finish()
    }
}
