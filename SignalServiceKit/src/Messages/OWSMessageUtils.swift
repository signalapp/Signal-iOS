//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

extension OWSMessageUtils {
    static public func unreadMessageCountPromise() -> Promise<UInt> {
        databaseStorage.read(.promise) { readTx in
            InteractionFinder.unreadCountInAllThreads(transaction: readTx.unwrapGrdbRead)
        }
    }

    @objc
    static public func updateApplicationBadgeCount() {
        let fetchBadgeCount = { () -> Promise<UInt> in
            // The main app gets to perform this synchronously
            if CurrentAppContext().isMainApp {
                return .value(unreadMessagesCount())
            } else {
                return self.unreadMessageCountPromise()
            }
        }


        fetchBadgeCount().done {
            CurrentAppContext().setMainAppBadgeNumber(Int($0))
        }.catch { error in
            owsFailDebug("Failed to update badge number: \(error)")
        }
    }
}
