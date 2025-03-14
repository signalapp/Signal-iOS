//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct AccountAttributesGenerator {
    private let accountKeyStore: AccountKeyStore
    private let ows2FAManager: OWS2FAManager
    private let profileManager: ProfileManager
    private let svrLocalStorage: SVRLocalStorage
    private let tsAccountManager: TSAccountManager
    private let udManager: OWSUDManager

    init(
        accountKeyStore: AccountKeyStore,
        ows2FAManager: OWS2FAManager,
        profileManager: ProfileManager,
        svrLocalStorage: SVRLocalStorage,
        tsAccountManager: TSAccountManager,
        udManager: OWSUDManager
    ) {
        self.accountKeyStore = accountKeyStore
        self.ows2FAManager = ows2FAManager
        self.profileManager = profileManager
        self.svrLocalStorage = svrLocalStorage
        self.tsAccountManager = tsAccountManager
        self.udManager = udManager
    }

    func generateForPrimary(
        tx: DBWriteTransaction
    ) -> AccountAttributes {
        owsAssertDebug(tsAccountManager.registrationState(tx: tx).isPrimaryDevice == true)

        let sdsTx: DBWriteTransaction = SDSDB.shimOnlyBridge(tx)

        let isManualMessageFetchEnabled = tsAccountManager.isManualMessageFetchEnabled(tx: tx)

        let registrationId = tsAccountManager.getOrGenerateAciRegistrationId(tx: tx)
        let pniRegistrationId = tsAccountManager.getOrGeneratePniRegistrationId(tx: tx)

        guard let profileKey = profileManager.localUserProfile(tx: sdsTx)?.profileKey else {
            owsFail("Couldn't fetch local profile key.")
        }
        let udAccessKey = SMKUDAccessKey(profileKey: profileKey).keyData.base64EncodedString()

        let allowUnrestrictedUD = udManager.shouldAllowUnrestrictedAccessLocal(transaction: sdsTx)
        let hasSVRBackups = svrLocalStorage.getIsMasterKeyBackedUp(tx)

        let twoFaMode: AccountAttributes.TwoFactorAuthMode
        if
            let reglockToken = accountKeyStore.getMasterKey(tx: tx)?.data(for: .registrationLock),
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

        let registrationRecoveryPassword = accountKeyStore.getMasterKey(tx: tx)?.data(
            for: .registrationRecoveryPassword
        ).canonicalStringRepresentation

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
