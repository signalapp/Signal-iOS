//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

#if DEBUG

@objc
public class OWSMockSyncManager: NSObject, OWSSyncManagerProtocol {

    @objc public func sendConfigurationSyncMessage() {
        Logger.info("")
    }

    @objc public func syncLocalContact() -> AnyPromise {
        Logger.info("")

        return AnyPromise()
    }

    @objc public func syncAllContacts() -> AnyPromise {
        Logger.info("")

        return AnyPromise()
    }

    @objc public func syncContacts(for signalAccounts: [SignalAccount]) -> AnyPromise {
        Logger.info("")

        return AnyPromise()
    }
}

#endif
