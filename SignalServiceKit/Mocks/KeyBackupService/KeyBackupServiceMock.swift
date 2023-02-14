//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class KeyBackupServiceMock: KeyBackupServiceProtocol {

    public init() {}

    public var hasMasterKey = false

    public var currentEnclave: KeyBackupEnclave = .init(
        name: "",
        mrenclave: .init("8888888888888888888888888888888888888888888888888888888888888888"),
        serviceId: ""
    )

    public var hasBackedUpMasterKey: Bool = false

    public func hasMasterKey(transaction: DBReadTransaction) -> Bool {
        return hasMasterKey
    }

    public var currentPinType: KBS.PinType?

    public var verifyPinHandler: (String) -> Bool = { _ in return true }

    public func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        resultHandler(verifyPinHandler(pin))
    }

    public var reglockToken: String?

    public func acquireRegistrationLockForNewNumber(with pin: String, and auth: KBSAuthCredential) -> Promise<String> {
        return .value(reglockToken!)
    }

    public func generateAndBackupKeys(with pin: String, rotateMasterKey: Bool) -> AnyPromise {
        return AnyPromise(Promise<Void>.value(()))
    }

    public func generateAndBackupKeys(with pin: String, rotateMasterKey: Bool) -> Promise<Void> {
        return .value(())
    }

    public var restoreKeysAndBackupPromise: Promise<Void>?

    public func restoreKeysAndBackup(with pin: String, and auth: KBSAuthCredential?) -> Promise<Void> {
        return restoreKeysAndBackupPromise!
    }

    public func deleteKeys() -> Promise<Void> {
        return .value(())
    }

    public func encrypt(keyType: KBS.DerivedKey, data: Data) throws -> Data {
        return data
    }

    public func decrypt(keyType: KBS.DerivedKey, encryptedData: Data) throws -> Data {
        return encryptedData
    }

    public func deriveRegistrationLockToken() -> String? {
        return reglockToken
    }

    public static func normalizePin(_ pin: String) -> String {
        return pin
    }

    public func warmCaches() {
        // Do nothing
    }

    public func clearKeys(transaction: DBWriteTransaction) {
        hasMasterKey = false
    }

    public func storeSyncedKey(type: KBS.DerivedKey, data: Data?, transaction: DBWriteTransaction) {
        // Do nothing
    }

    public var hasHadBackupKeyRequestFail = false

    public func hasBackupKeyRequestFailed(transaction: DBReadTransaction) -> Bool {
        return hasHadBackupKeyRequestFail
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

    public func setMasterKeyBackedUp(_ value: Bool, transaction: DBWriteTransaction) {
        hasBackedUpMasterKey = true
    }

    public func useDeviceLocalMasterKey(transaction: DBWriteTransaction) {
        // Do nothing
    }

    public var dataGenerator: (KBS.DerivedKey) -> Data? = { _ in return nil }

    public func data(for key: KBS.DerivedKey) -> Data? {
        return dataGenerator(key)
    }

    public func data(for key: KBS.DerivedKey, transaction: DBReadTransaction) -> Data? {
        return dataGenerator(key)
    }

    public func isKeyAvailable(_ key: KBS.DerivedKey) -> Bool {
        return true
    }
}

#endif
