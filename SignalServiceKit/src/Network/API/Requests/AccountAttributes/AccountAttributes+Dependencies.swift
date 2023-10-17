//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

extension AccountAttributes {

    public static func generateForPrimaryDevice(
        fromDependencies dependencies: Dependencies,
        svr: SecureValueRecovery,
        transaction: SDSAnyWriteTransaction
    ) -> AccountAttributes {
        owsAssertDebug(DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction.asV2Read).isPrimaryDevice == true)
        return generate(
            fromDependencies: dependencies,
            svr: svr,
            encryptedDeviceName: nil,
            isSecondaryDeviceRegistration: false,
            transaction: transaction
        )
    }

    public static func generateForSecondaryDevice(
        fromDependencies dependencies: Dependencies,
        svr: SecureValueRecovery,
        encryptedDeviceName: Data,
        transaction: SDSAnyWriteTransaction
    ) -> AccountAttributes {
        return generate(
            fromDependencies: dependencies,
            svr: svr,
            encryptedDeviceName: encryptedDeviceName,
            isSecondaryDeviceRegistration: true,
            transaction: transaction
        )
    }

    private static func generate(
        fromDependencies dependencies: Dependencies,
        svr: SecureValueRecovery,
        encryptedDeviceName encryptedDeviceNameRaw: Data?,
        isSecondaryDeviceRegistration: Bool,
        transaction: SDSAnyWriteTransaction
    ) -> AccountAttributes {
        let isManualMessageFetchEnabled: Bool
        if isSecondaryDeviceRegistration {
            // Secondary devices only use account attributes during registration;
            // at this time they have historically set this to true.
            // Some forensic investigation is required as to why, but the best bet
            // is that some form of message delivery needs to succeed _before_ it
            // sets its APNS token, and thus it needs manual message fetch enabled.

            // This field is scoped to the device that sets it and does not overwrite
            // the attribute from the primary device.

            // TODO: can we change this with atomic device linking?
            isManualMessageFetchEnabled = true
        } else {
            isManualMessageFetchEnabled = DependenciesBridge.shared.tsAccountManager.isManualMessageFetchEnabled(tx: transaction.asV2Read)
        }

        let registrationId = DependenciesBridge.shared.tsAccountManager.getOrGenerateAciRegistrationId(tx: transaction.asV2Write)
        let pniRegistrationId = DependenciesBridge.shared.tsAccountManager.getOrGeneratePniRegistrationId(tx: transaction.asV2Write)

        let profileKey = dependencies.profileManager.localProfileKey()
        let udAccessKey: String
        do {
            udAccessKey = try SMKUDAccessKey(profileKey: profileKey.keyData).keyData.base64EncodedString()
        } catch {
            // Crash app if UD cannot be enabled.
            owsFail("Could not determine UD access key: \(error).")
        }
        let allowUnrestrictedUD = dependencies.udManager.shouldAllowUnrestrictedAccessLocal(transaction: transaction)

        let twoFaMode: TwoFactorAuthMode
        if isSecondaryDeviceRegistration {
            // Historical note: secondary device registration uses the same AccountAttributes object,
            // but some fields, like reglock and pin, are ignored by the server.
            // Don't bother looking for KBS data the secondary couldn't possibly have at this point,
            // just explicitly set to nil.
            twoFaMode = .none
        } else {
            if
                let reglockToken = svr.data(for: .registrationLock, transaction: transaction.asV2Read),
                dependencies.ows2FAManager.isRegistrationLockV2Enabled(transaction: transaction)
            {
                twoFaMode = .v2(reglockToken: reglockToken.canonicalStringRepresentation)
            } else if
                let pinCode = dependencies.ows2FAManager.pinCode(with: transaction),
                pinCode.isEmpty.negated,
                svr.hasBackedUpMasterKey(transaction: transaction.asV2Read).negated
            {
                twoFaMode = .v1(pinCode: pinCode)
            } else {
                twoFaMode = .none
            }
        }

        let registrationRecoveryPassword = svr.data(
            for: .registrationRecoveryPassword,
            transaction: transaction.asV2Read
        )?.canonicalStringRepresentation

        let encryptedDeviceName = (encryptedDeviceNameRaw?.isEmpty ?? true) ? nil : encryptedDeviceNameRaw?.base64EncodedString()

        let phoneNumberDiscoverabilityManager = DependenciesBridge.shared.phoneNumberDiscoverabilityManager
        let phoneNumberDiscoverability = phoneNumberDiscoverabilityManager.phoneNumberDiscoverability(tx: transaction.asV2Read)

        let hasSVRBackups = svr.hasBackedUpMasterKey(transaction: transaction.asV2Read)

        return AccountAttributes(
            isManualMessageFetchEnabled: isManualMessageFetchEnabled,
            registrationId: registrationId,
            pniRegistrationId: pniRegistrationId,
            unidentifiedAccessKey: udAccessKey,
            unrestrictedUnidentifiedAccess: allowUnrestrictedUD,
            twofaMode: twoFaMode,
            registrationRecoveryPassword: registrationRecoveryPassword,
            encryptedDeviceName: encryptedDeviceName,
            discoverableByPhoneNumber: phoneNumberDiscoverability,
            hasSVRBackups: hasSVRBackups)
    }
}
