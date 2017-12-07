//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
// All Observer methods will be invoked from the main thread.
@objc
public protocol ShareViewDelegate: class {
    func shareViewWasCompleted()
    func shareViewWasCancelled()
    func shareViewFailed(error: Error)
}
