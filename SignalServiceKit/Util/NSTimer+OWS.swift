//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private class TimerProxy {
    weak var target: AnyObject?
    let selector: Selector

    init(target: AnyObject?, selector: Selector) {
        self.target = target
        self.selector = selector
    }

    @objc
    func timerFired(_ timer: Timer) {
        guard let target else {
            timer.invalidate()
            return
        }
        _ = target.perform(selector, with: timer)
    }
}

extension Timer {
    /// This method avoids the classic NSTimer retain cycle bug by using a weak reference to the target.
    @objc
    @available(swift, obsoleted: 1)
    public static func weakScheduledTimer(withTimeInterval timeInterval: TimeInterval,
                                          target: AnyObject,
                                          selector: Selector,
                                          userInfo: Any?,
                                          repeats: Bool) -> Timer {
        let proxy = TimerProxy(target: target, selector: selector)
        return Timer.scheduledTimer(timeInterval: timeInterval, target: proxy, selector: #selector(TimerProxy.timerFired(_:)), userInfo: userInfo, repeats: repeats)
    }

    /// This method avoids the classic NSTimer retain cycle bug by using a weak reference to the target.
    @objc
    @available(swift, obsoleted: 1)
    public static func weakTimer(withTimeInterval timeInterval: TimeInterval,
                                 target: AnyObject,
                                 selector: Selector,
                                 userInfo: Any?,
                                 repeats: Bool) -> Timer {
        let proxy = TimerProxy(target: target, selector: selector)
        return Timer(timeInterval: timeInterval, target: proxy, selector: #selector(TimerProxy.timerFired(_:)), userInfo: userInfo, repeats: repeats)
    }
}
