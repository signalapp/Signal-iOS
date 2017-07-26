//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

/**
 * We synchronize access to state in this class using this queue.
 */
func assertOnQueue(_ queue: DispatchQueue) {
    if #available(iOS 10.0, *) {
        dispatchPrecondition(condition: .onQueue(queue))
    } else {
        // Skipping check on <iOS10, since syntax is different and it's just a development convenience.
    }
}

func owsFail(_ message: String) {
    Logger.error(message)
    Logger.flush()
    assertionFailure(message)
}
