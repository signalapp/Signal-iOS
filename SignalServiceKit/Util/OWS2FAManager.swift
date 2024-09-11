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

    public func requestEnable2FA(withPin pin: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            requestEnable2FA(withPin: pin, success: {
                continuation.resume()
            }) { error in
                continuation.resume(throwing: error)
            }
        }
    }

    public func enableRegistrationLockV2() async throws {
        let token = self.databaseStorage.read { tx in
            return DependenciesBridge.shared.svr.data(
                for: .registrationLock,
                transaction: tx.asV2Read
            )?.canonicalStringRepresentation
        }
        guard let token else {
            throw OWSAssertionError("Cannot enable registration lock without an existing PIN")
        }

        let request = OWSRequestFactory.enableRegistrationLockV2Request(token: token)
        _ = try await self.networkManager.makePromise(request: request).awaitable()

        await self.databaseStorage.awaitableWrite { transaction in
            OWS2FAManager.keyValueStore().setBool(
                true,
                key: OWS2FAManager.isRegistrationLockV2EnabledKey,
                transaction: transaction
            )
        }

        Task {
            do {
                try await DependenciesBridge.shared.accountAttributesUpdater.updateAccountAttributes(authedAccount: .implicit())
            } catch {
                Logger.warn("\(error)")
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
        return AnyPromise(Promise.wrapAsync { try await self.disableRegistrationLockV2() })
    }

    public func disableRegistrationLockV2() async throws {
        let request = OWSRequestFactory.disableRegistrationLockV2Request()
        _ = try await self.networkManager.makePromise(request: request).awaitable()

        await self.databaseStorage.awaitableWrite { transaction in
            OWS2FAManager.keyValueStore().removeValue(
                forKey: OWS2FAManager.isRegistrationLockV2EnabledKey,
                transaction: transaction
            )
        }

        Task {
            do {
                try await DependenciesBridge.shared.accountAttributesUpdater.updateAccountAttributes(authedAccount: .implicit())
            } catch {
                Logger.warn("\(error)")
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
        return AnyPromise(Promise.wrapAsync { try await self.migrateToRegistrationLockV2() })
    }

    public func migrateToRegistrationLockV2() async throws {
        guard let pinCode = pinCode else {
            throw OWSAssertionError("tried to migrate to registration lock V2 without legacy PIN")
        }

        try await requestEnable2FA(withPin: pinCode)
        try await enableRegistrationLockV2()
    }

    @objc
    public func disable2FAV1(success: OWS2FASuccess?, failure: OWS2FAFailure?) {
        Task {
            do {
                let request = OWSRequestFactory.disable2FARequest()
                _ = try await self.networkManager.makePromise(request: request).awaitable()
                await self.databaseStorage.awaitableWrite { transaction in
                    self.markDisabled(transaction: transaction)
                }
                DispatchQueue.main.async { success?() }
            } catch {
                owsFailDebugUnlessNetworkFailure(error)
                DispatchQueue.main.async { failure?(error) }
            }
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

    @objc(generateAndBackupKeysWithPin:)
    @available(swift, obsoleted: 1.0)
    public func generateAndBackupKeys(with pin: String) -> AnyPromise {
        let promise = DependenciesBridge.shared.svr.generateAndBackupKeys(pin: pin, authMethod: .implicit)
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
