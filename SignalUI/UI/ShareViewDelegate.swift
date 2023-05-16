//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// All Observer methods will be invoked from the main thread.
public protocol ShareViewDelegate: AnyObject {
    func shareViewWasUnlocked()
    func shareViewWasCompleted()
    func shareViewWasCancelled()
    func shareViewFailed(error: Error)
    var shareViewNavigationController: OWSNavigationController? { get }
}
