// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension Timer {
    
    @discardableResult
    public static func scheduledTimerOnMainThread(withTimeInterval timeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: timeInterval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
