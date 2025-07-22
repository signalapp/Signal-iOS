//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalUI

// All Observer methods will be invoked from the main thread.
public protocol ShareViewDelegate: AnyObject {
    func shareViewWillSend()
    func shareViewWasCompleted()
    func shareViewWasCancelled()
    func shareViewFailed(error: Error)
    var shareViewNavigationController: OWSNavigationController? { get }
}
