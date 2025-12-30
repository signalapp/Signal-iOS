//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class SecureValueRecoveryMock: SecureValueRecovery {

    public init() {}

    public var hasMasterKey = false

    public var hasBackedUpMasterKey: Bool = false

    public func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool {
        return hasBackedUpMasterKey
    }

    public func hasMasterKey(transaction: DBReadTransaction) -> Bool {
        return hasMasterKey
    }

    public var currentPinType: SVR.PinType?

    public func currentPinType(transaction: DBReadTransaction) -> SVR.PinType? {
        return currentPinType
    }

    public var reglockToken: String?

    public var backupMasterKeyMock: ((_ pin: String, _ masterKey: MasterKey, _ authMethod: SVR.AuthMethod) -> Promise<MasterKey>)?

    public func backupMasterKey(pin: String, masterKey: MasterKey, authMethod: SVR.AuthMethod) -> Promise<MasterKey> {
        return backupMasterKeyMock!(pin, masterKey, authMethod)
    }

    public var restoreKeysMock: ((_ pin: String, _ authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult>)?

    public func restoreKeys(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult> {
        return restoreKeysMock!(pin, authMethod)
    }

    public var restoreKeysAndBackupMock: ((_ pin: String, _ authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult>)?

    public func restoreKeysAndBackup(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult> {
        return restoreKeysAndBackupMock!(pin, authMethod)
    }

    public func deleteKeys() -> Promise<Void> {
        return .value(())
    }

    public func warmCaches() {
        // Do nothing
    }

    public func clearKeys(transaction: DBWriteTransaction) {
        hasMasterKey = false
    }

    public var syncedMasterKey: MasterKey?

    public func storeKeys(
        fromKeysSyncMessage syncMessage: SSKProtoSyncMessageKeys,
        authedDevice: AuthedDevice,
        tx: DBWriteTransaction,
    ) throws(SVR.KeysError) {
        syncedMasterKey = syncMessage.master.map { try! MasterKey(data: $0) }
    }

    public func storeKeys(
        fromProvisioningMessage provisioningMessage: LinkingProvisioningMessage,
        authedDevice: AuthedDevice,
        tx: DBWriteTransaction,
    ) throws(SVR.KeysError) {
        let masterKey = switch provisioningMessage.rootKey {
        case .accountEntropyPool(let aep): aep.getMasterKey()
        case .masterKey(let masterKey): masterKey
        }
        syncedMasterKey = masterKey
    }

    public var doesHavePendingRestoration = false

    public func hasPendingRestoration(transaction: DBReadTransaction) -> Bool {
        return doesHavePendingRestoration
    }

    public func recordPendingRestoration(transaction: DBWriteTransaction) {
        doesHavePendingRestoration = true
    }

    public func clearPendingRestoration(transaction: DBWriteTransaction) {
        doesHavePendingRestoration = false
    }

    public func handleMasterKeyUpdated(newMasterKey: MasterKey, disablePIN: Bool, tx: DBWriteTransaction) {
        // Do nothing
    }
}

#endif
