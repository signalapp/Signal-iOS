//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension OWS2FAManager {

    @objc
    public static var isRegistrationLockV2EnabledKey = "isRegistrationLockV2Enabled"

    @objc
    public var isRegistrationLockEnabled: Bool {
        switch mode {
        case .V2:
            return isRegistrationLockV2Enabled
        case .V1:
            return true // In v1 reg lock and 2fa are the same thing.
        case .disabled:
            return false
        }
    }

    @objc
    public var isRegistrationLockV2Enabled: Bool {
        return databaseStorage.read { transaction in
            OWS2FAManager.keyValueStore().getBool(
                OWS2FAManager.isRegistrationLockV2EnabledKey,
                defaultValue: false,
                transaction: transaction
            )
        }
    }

    public func isRegistrationLockV2Enabled(transaction: SDSAnyReadTransaction) -> Bool {
        return OWS2FAManager.keyValueStore().getBool(
            OWS2FAManager.isRegistrationLockV2EnabledKey,
            defaultValue: false,
            transaction: transaction
        )
    }

    public func requestEnable2FA(withPin pin: String, mode: OWS2FAMode, rotateMasterKey: Bool = false) -> Promise<Void> {
        return Promise { future in
            requestEnable2FA(withPin: pin, mode: mode, rotateMasterKey: rotateMasterKey, success: {
                future.resolve()
            }) { error in
                future.reject(error)
            }
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func enableRegistrationLockV2() -> AnyPromise {
        return AnyPromise(enableRegistrationLockV2())
    }

    public func enableRegistrationLockV2() -> Promise<Void> {
        return DispatchQueue.global().async(.promise) { () -> String in
            let token = Self.databaseStorage.read { tx in
                return DependenciesBridge.shared.svr.data(
                    for: .registrationLock,
                    transaction: tx.asV2Read
                )?.canonicalStringRepresentation
            }
            guard let token else {
                throw OWSAssertionError("Cannot enable registration lock without an existing PIN")
            }
            return token
        }.then { token -> Promise<HTTPResponse> in
            let request = OWSRequestFactory.enableRegistrationLockV2Request(token: token)
            return self.networkManager.makePromise(request: request)
        }.done { _ in
            self.databaseStorage.write { transaction in
                OWS2FAManager.keyValueStore().setBool(
                    true,
                    key: OWS2FAManager.isRegistrationLockV2EnabledKey,
                    transaction: transaction
                )
            }
            firstly {
                return Promise.wrapAsync {
                    try await DependenciesBridge.shared.accountAttributesUpdater.updateAccountAttributes(authedAccount: .implicit())
                }
            }.catch { error in
                Logger.error("Error: \(error)")
            }
        }
    }

    public func markRegistrationLockV2Enabled(transaction: SDSAnyWriteTransaction) {
        guard !DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction.asV2Read).isRegistered else {
            return owsFailDebug("Unexpectedly attempted to mark reglock as enabled after registration")
        }

        OWS2FAManager.keyValueStore().setBool(
            true,
            key: OWS2FAManager.isRegistrationLockV2EnabledKey,
            transaction: transaction
        )
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func disableRegistrationLockV2() -> AnyPromise {
        return AnyPromise(disableRegistrationLockV2())
    }

    public func disableRegistrationLockV2() -> Promise<Void> {
        return firstly { () -> Promise<HTTPResponse> in
            let request = OWSRequestFactory.disableRegistrationLockV2Request()
            return self.networkManager.makePromise(request: request)
        }.done { _ in
            self.databaseStorage.write { transaction in
                OWS2FAManager.keyValueStore().removeValue(
                    forKey: OWS2FAManager.isRegistrationLockV2EnabledKey,
                    transaction: transaction
                )
            }
            firstly {
                return Promise.wrapAsync {
                    try await DependenciesBridge.shared.accountAttributesUpdater.updateAccountAttributes(authedAccount: .implicit())
                }
            }.catch { error in
                Logger.error("Error: \(error)")
            }
        }
    }

    public func markRegistrationLockV2Disabled(transaction: SDSAnyWriteTransaction) {
        guard !DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction.asV2Read).isRegistered else {
            return owsFailDebug("Unexpectedly attempted to mark reglock as disabled after registration")
        }

        OWS2FAManager.keyValueStore().removeValue(
            forKey: OWS2FAManager.isRegistrationLockV2EnabledKey,
            transaction: transaction
        )
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func migrateToRegistrationLockV2() -> AnyPromise {
        return AnyPromise(migrateToRegistrationLockV2())
    }

    public func migrateToRegistrationLockV2() -> Promise<Void> {
        guard let pinCode = pinCode else {
            return Promise(error: OWSAssertionError("tried to migrate to registration lock V2 without legacy PIN"))
        }

        return firstly {
            return requestEnable2FA(withPin: pinCode, mode: .V2)
        }.then {
            return self.enableRegistrationLockV2()
        }
    }

    @objc
    public func enable2FAV1(pin: String,
                            success: (() -> Void)?,
                            failure: ((Error) -> Void)?) {
        // Convert the pin to arabic numerals, we never want to
        // operate with pins in other numbering systems.
        let request = OWSRequestFactory.enable2FARequest(withPin: pin.ensureArabicNumerals)
        firstly {
            Self.networkManager.makePromise(request: request)
        }.done(on: DispatchQueue.main) { _ in
            Self.databaseStorage.write { transaction in
                self.markEnabled(pin: pin, transaction: transaction)
            }
            success?()
        }.catch(on: DispatchQueue.main) { error in
            owsFailDebugUnlessNetworkFailure(error)
            failure?(error)
        }
    }

    @objc
    public func disable2FAV1(success: OWS2FASuccess?,
                             failure: OWS2FAFailure?) {
        let request = OWSRequestFactory.disable2FARequest()
        firstly {
            Self.networkManager.makePromise(request: request)
        }.done(on: DispatchQueue.main) { _ in
            Self.databaseStorage.write { transaction in
                self.markDisabled(transaction: transaction)
            }
            success?()
        }.catch(on: DispatchQueue.main) { error in
            owsFailDebugUnlessNetworkFailure(error)
            failure?(error)
        }
    }

    public static func isWeakPin(_ pin: String) -> Bool {
        let normalizedPin = SVRUtil.normalizePin(pin)

        guard pin.count >= kMin2FAv2PinLength else { return true }

        // We only check numeric pins for weakness
        guard normalizedPin.digitsOnly() == normalizedPin else { return false }

        var allTheSame = true
        var forwardSequential = true
        var reverseSequential = true

        var previousWholeNumberValue: Int?
        for character in normalizedPin {
            guard let current = character.wholeNumberValue else {
                owsFailDebug("numeric pin unexpectedly contatined non-numeric characters")
                break
            }

            defer { previousWholeNumberValue = current }
            guard let previous = previousWholeNumberValue else { continue }

            if previous != current { allTheSame = false }
            if previous + 1 != current { forwardSequential = false }
            if previous - 1 != current { reverseSequential = false }

            if !allTheSame && !forwardSequential && !reverseSequential { break }
        }

        return allTheSame || forwardSequential || reverseSequential
    }

    @objc
    public func clearLocalPinCode(transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore().removeValue(forKey: kOWS2FAManager_PinCode, transaction: transaction)
    }

    // MARK: - KeyBackupService Wrappers/Helpers

    @objc
    public func hasBackedUpMasterKey(transaction: SDSAnyReadTransaction) -> Bool {
        return DependenciesBridge.shared.svr.hasBackedUpMasterKey(transaction: transaction.asV2Read)
    }

    @objc(generateAndBackupKeysWithPin:rotateMasterKey:)
    @available(swift, obsoleted: 1.0)
    public func generateAndBackupKeys(with pin: String, rotateMasterKey: Bool) -> AnyPromise {
        let promise = DependenciesBridge.shared.svr.generateAndBackupKeys(pin: pin, authMethod: .implicit, rotateMasterKey: rotateMasterKey)
        return AnyPromise(promise)
    }

    @objc
    public func verifyKBSPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        DependenciesBridge.shared.svr.verifyPin(pin, resultHandler: resultHandler)
    }

    @objc(deleteKeys)
    public func deleteKBSKeys() -> AnyPromise {
        return AnyPromise(DependenciesBridge.shared.svr.deleteKeys())
    }
}
