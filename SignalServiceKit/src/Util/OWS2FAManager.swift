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
            guard let token = DependenciesBridge.shared.keyBackupService.deriveRegistrationLockToken() else {
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
                TSAccountManager.shared.updateAccountAttributes()
            }.catch { error in
                Logger.error("Error: \(error)")
            }
        }
    }

    public func markRegistrationLockV2Enabled(transaction: SDSAnyWriteTransaction) {
        guard !TSAccountManager.shared.isRegistered else {
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
                TSAccountManager.shared.updateAccountAttributes()
            }.catch { error in
                Logger.error("Error: \(error)")
            }
        }
    }

    public func markRegistrationLockV2Disabled(transaction: SDSAnyWriteTransaction) {
        guard !TSAccountManager.shared.isRegistered else {
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
        }.done(on: .main) { _ in
            Self.databaseStorage.write { transaction in
                self.markEnabled(pin: pin, transaction: transaction)
            }
            success?()
        }.catch(on: .main) { error in
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
        }.done(on: .main) { _ in
            Self.databaseStorage.write { transaction in
                self.markDisabled(transaction: transaction)
            }
            success?()
        }.catch(on: .main) { error in
            owsFailDebugUnlessNetworkFailure(error)
            failure?(error)
        }
    }

    // MARK: - KeyBackupService Wrappers/Helpers

    @objc
    public var hasBackedUpMasterKey: Bool {
        DependenciesBridge.shared.keyBackupService.hasBackedUpMasterKey
    }

    @objc(generateAndBackupKeysWithPin:rotateMasterKey:)
    @available(swift, obsoleted: 1.0)
    public func generateAndBackupKeys(with pin: String, rotateMasterKey: Bool) -> AnyPromise {
        return DependenciesBridge.shared.keyBackupService.generateAndBackupKeys(with: pin, rotateMasterKey: rotateMasterKey)
    }

    @objc
    public func verifyKBSPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        DependenciesBridge.shared.keyBackupService.verifyPin(pin, resultHandler: resultHandler)
    }

    @objc(deleteKeys)
    public func deleteKBSKeys() -> AnyPromise {
        return AnyPromise(DependenciesBridge.shared.keyBackupService.deleteKeys())
    }
}
