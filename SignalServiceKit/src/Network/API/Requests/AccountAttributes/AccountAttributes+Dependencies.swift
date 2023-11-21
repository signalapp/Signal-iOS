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

        let isManualMessageFetchEnabled = DependenciesBridge.shared.tsAccountManager.isManualMessageFetchEnabled(tx: transaction.asV2Read)

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

        let registrationRecoveryPassword = svr.data(
            for: .registrationRecoveryPassword,
            transaction: transaction.asV2Read
        )?.canonicalStringRepresentation

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
            encryptedDeviceName: nil,
            discoverableByPhoneNumber: phoneNumberDiscoverability,
            hasSVRBackups: hasSVRBackups
        )
    }
}
