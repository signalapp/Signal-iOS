//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension TSAccountManager {

    // MARK: - Dependencies

    class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    var profileManager: ProfileManagerProtocol {
        return SSKEnvironment.shared.profileManager
    }

    // MARK: -

    @objc
    private class func getLocalThread(transaction: SDSAnyReadTransaction) -> TSThread? {
        guard let localAddress = self.localAddress(with: transaction) else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getWithContactAddress(localAddress, transaction: transaction)
    }

    @objc
    private class func getLocalThreadWithSneakyTransaction() -> TSThread? {
        return databaseStorage.read { transaction in
            return getLocalThread(transaction: transaction)
        }
    }

    @objc
    class func getOrCreateLocalThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        guard let localAddress = self.localAddress(with: transaction) else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getOrCreateThread(withContactAddress: localAddress, transaction: transaction)
    }

    @objc
    class func getOrCreateLocalThreadWithSneakyTransaction() -> TSThread? {
        assert(!Thread.isMainThread)

        if let thread = getLocalThreadWithSneakyTransaction() {
            return thread
        }

        return databaseStorage.write { transaction in
            return getOrCreateLocalThread(transaction: transaction)
        }
    }

    @objc
    var isRegisteredPrimaryDevice: Bool {
        return isRegistered && self.storedDeviceId() == OWSDevicePrimaryDeviceId
    }

    @objc
    var isPrimaryDevice: Bool {
        return storedDeviceId() == OWSDevicePrimaryDeviceId
    }

    @objc
    var storedServerUsername: String? {
        guard let serviceIdentifier = self.localAddress?.serviceIdentifier else {
            return nil
        }

        return isRegisteredPrimaryDevice ? serviceIdentifier : "\(serviceIdentifier).\(storedDeviceId())"
    }

    @objc(performUpdateAccountAttributes)
    func objc_performUpdateAccountAttributes() -> AnyPromise {
        return AnyPromise(performUpdateAccountAttributes())
    }

    func performUpdateAccountAttributes() -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            guard isRegisteredPrimaryDevice else {
                throw OWSAssertionError("only update account attributes on primary")
            }

            return SignalServiceRestClient().updatePrimaryDeviceAccountAttributes()
        }.done {
            // Fetch the local profile, as we may have changed its
            // account attributes.  Specifically, we need to determine
            // if all devices for our account now support UD for sync
            // messages.
            self.profileManager.fetchAndUpdateLocalUsersProfile()
        }
    }
}
