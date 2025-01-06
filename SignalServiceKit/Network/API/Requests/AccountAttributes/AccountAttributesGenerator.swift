//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct AccountAttributesGenerator {
    private let ows2FAManager: OWS2FAManager
    private let profileManager: ProfileManager
    private let svrKeyDeriver: SVRKeyDeriver
    private let svrLocalStorage: SVRLocalStorage
    private let tsAccountManager: TSAccountManager
    private let udManager: OWSUDManager

    init(
        ows2FAManager: OWS2FAManager,
        profileManager: ProfileManager,
        svrKeyDeriver: SVRKeyDeriver,
        svrLocalStorage: SVRLocalStorage,
        tsAccountManager: TSAccountManager,
        udManager: OWSUDManager
    ) {
        self.ows2FAManager = ows2FAManager
        self.profileManager = profileManager
        self.svrKeyDeriver = svrKeyDeriver
        self.svrLocalStorage = svrLocalStorage
        self.tsAccountManager = tsAccountManager
        self.udManager = udManager
    }

    func generateForPrimary(
        tx: DBWriteTransaction
    ) -> AccountAttributes {
        owsAssertDebug(tsAccountManager.registrationState(tx: tx).isPrimaryDevice == true)

        let sdsTx: SDSAnyWriteTransaction = SDSDB.shimOnlyBridge(tx)

        let isManualMessageFetchEnabled = tsAccountManager.isManualMessageFetchEnabled(tx: tx)

        let registrationId = tsAccountManager.getOrGenerateAciRegistrationId(tx: tx)
        let pniRegistrationId = tsAccountManager.getOrGeneratePniRegistrationId(tx: tx)

        let udAccessKey: String
        do {
            let profileKey = profileManager.localProfileKey
            udAccessKey = try SMKUDAccessKey(profileKey: profileKey.keyData).keyData.base64EncodedString()
        } catch {
            // Crash app if UD cannot be enabled.
            owsFail("Could not determine UD access key: \(error).")
        }

        let allowUnrestrictedUD = udManager.shouldAllowUnrestrictedAccessLocal(transaction: sdsTx)
        let hasSVRBackups = svrLocalStorage.getIsMasterKeyBackedUp(tx)

        let twoFaMode: AccountAttributes.TwoFactorAuthMode
        if
            let reglockToken = svrKeyDeriver.data(for: .registrationLock, tx: tx),
            ows2FAManager.isRegistrationLockV2Enabled(transaction: sdsTx)
        {
            twoFaMode = .v2(reglockToken: reglockToken.canonicalStringRepresentation)
        } else if
            let pinCode = ows2FAManager.pinCode(transaction: sdsTx),
            pinCode.isEmpty.negated,
            hasSVRBackups.negated
        {
            twoFaMode = .v1(pinCode: pinCode)
        } else {
            twoFaMode = .none
        }

        let registrationRecoveryPassword = svrKeyDeriver.data(
            for: .registrationRecoveryPassword,
            tx: tx
        )?.canonicalStringRepresentation

        let phoneNumberDiscoverability = tsAccountManager.phoneNumberDiscoverability(tx: tx)

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
