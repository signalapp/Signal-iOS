//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

/**
 * As of iOS10, the timer API's take a block, which makes it easy to reference weak self in Swift. This class offers a 
 * similar API that works pre iOS10.
 *
 * Solution modified from
 * http://stackoverflow.com/questions/16821736/weak-reference-to-nstimer-target-to-prevent-retain-cycle/41003985#41003985
 */
public final class WeakTimer {

    fileprivate weak var timer: Timer?
    fileprivate weak var target: AnyObject?
    fileprivate let action: (Timer) -> Void

    fileprivate init(timeInterval: TimeInterval, target: AnyObject, userInfo: Any?, repeats: Bool, action: @escaping (Timer) -> Void) {
        self.target = target
        self.action = action
        self.timer = Timer.scheduledTimer(timeInterval: timeInterval,
                                          target: self,
                                          selector: #selector(fire),
                                          userInfo: userInfo,
                                          repeats: repeats)
    }

    deinit {
        timer?.invalidate()
    }

    @objc
    public class func scheduledTimer(timeInterval: TimeInterval, target: AnyObject, userInfo: Any?, repeats: Bool, action: @escaping (Timer) -> Void) -> Timer {
        return WeakTimer(timeInterval: timeInterval,
                         target: target,
                         userInfo: userInfo,
                         repeats: repeats,
                         action: action).timer!
    }

    @objc public func fire(timer: Timer) {
        if target != nil {
            action(timer)
        } else {
            timer.invalidate()
        }
    }
}
