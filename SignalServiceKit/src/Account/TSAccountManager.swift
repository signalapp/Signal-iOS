//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension TSAccountManager {

    // MARK: - Dependencies

    class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    private class func getLocalThread(transaction: SDSAnyReadTransaction) -> TSThread? {
        guard let localAddress = self.localAddress(with: transaction) else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getWithContactAddress(localAddress, transaction: transaction)
    }

    private class func getLocalThreadWithSneakyTransaction() -> TSThread? {
        return databaseStorage.read { transaction in
            return getLocalThread(transaction: transaction)
        }
    }

    class func getOrCreateLocalThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        guard let localAddress = self.localAddress(with: transaction) else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getOrCreateThread(withContactAddress: localAddress, transaction: transaction)
    }

    class func getOrCreateLocalThreadWithSneakyTransaction() -> TSThread? {
        assert(!Thread.isMainThread)

        if let thread = getLocalThreadWithSneakyTransaction() {
            return thread
        }

        return databaseStorage.write { transaction in
            return getOrCreateLocalThread(transaction: transaction)
        }
    }

    var isRegisteredPrimaryDevice: Bool {
        return isRegistered && self.storedDeviceId() == OWSDevicePrimaryDeviceId
    }

    var isPrimaryDevice: Bool {
        return storedDeviceId() == OWSDevicePrimaryDeviceId
    }

    var storedServerUsername: String? {
        guard let serviceIdentifier = self.localAddress?.serviceIdentifier else {
            return nil
        }

        return isRegisteredPrimaryDevice ? serviceIdentifier : "\(serviceIdentifier).\(storedDeviceId())"
    }
}
