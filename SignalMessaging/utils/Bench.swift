//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

/// Benchmark async code by calling the passed in block parameter when the work
/// is done.
///
///     BenchAsync(title: "my benchmark") { completeBenchmark in
///         foo {
///             completeBenchmark()
///             fooCompletion()
///         }
///     }
public func BenchAsync(title: String, block: (@escaping () -> Void) -> Void) {
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
