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
        firstly { () -> Promise<UInt> in
            if CurrentAppContext().isMainApp {
                return .value(unreadMessagesCount())
            } else {
                return unreadMessageCountPromise()
            }
        }.done {
            CurrentAppContext().setMainAppBadgeNumber(Int($0))
        }.catch { error in
            owsFailDebug("Failed to update badge number: \(error)")
        }
    }
}
