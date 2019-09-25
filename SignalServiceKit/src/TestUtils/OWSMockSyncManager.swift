//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

#if TESTABLE_BUILD

@objc
public class OWSMockSyncManager: NSObject, OWSSyncManagerProtocol {
    public typealias MockBlock = () -> Void

    @objc
    public var syncGroupsHook: MockBlock?

    @objc
    public func sendConfigurationSyncMessage() {
        Logger.info("")
    }

    @objc
    public func syncLocalContact() -> AnyPromise {
        Logger.info("")

        return AnyPromise()
    }

    @objc
    public func syncAllContacts() -> AnyPromise {
        Logger.info("")

        return AnyPromise()
    }

    @objc
    public func syncContacts(for signalAccounts: [SignalAccount]) -> AnyPromise {
        Logger.info("")

        return AnyPromise()
    }

    @objc
    public func syncGroups(with transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        syncGroupsHook?()
    }
}

#endif
