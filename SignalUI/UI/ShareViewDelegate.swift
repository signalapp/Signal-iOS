//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging

// All Observer methods will be invoked from the main thread.
@objc
public protocol ShareViewDelegate: AnyObject {
    func shareViewWasUnlocked()
    func shareViewWasCompleted()
    func shareViewWasCancelled()
    func shareViewFailed(error: Error)
    var shareViewNavigationController: OWSNavigationController? { get }
}
