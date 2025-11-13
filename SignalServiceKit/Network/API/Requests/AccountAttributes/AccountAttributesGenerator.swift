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
        aciRegistrationId: UInt32,
        pniRegistrationId: UInt32,
        tx: DBReadTransaction
    ) -> AccountAttributes {
        owsAssertDebug(tsAccountManager.registrationState(tx: tx).isPrimaryDevice == true)

        let isManualMessageFetchEnabled = tsAccountManager.isManualMessageFetchEnabled(tx: tx)

        guard let profileKey = profileManager.localUserProfile(tx: tx)?.profileKey else {
            owsFail("Couldn't fetch local profile key.")
        }
        let udAccessKey = SMKUDAccessKey(profileKey: profileKey).keyData.base64EncodedString()

        let allowUnrestrictedUD = udManager.shouldAllowUnrestrictedAccessLocal(transaction: tx)
        let hasSVRBackups = svrLocalStorage.getIsMasterKeyBackedUp(tx)

        let reglockToken: String?
        if
            let _reglockToken = accountKeyStore.getMasterKey(tx: tx)?.data(for: .registrationLock),
            ows2FAManager.isRegistrationLockV2Enabled(transaction: tx)
        {
            reglockToken = _reglockToken.canonicalStringRepresentation
        } else {
            reglockToken = nil
        }

        let registrationRecoveryPassword = accountKeyStore.getMasterKey(tx: tx)?.data(
            for: .registrationRecoveryPassword
        ).canonicalStringRepresentation

        let phoneNumberDiscoverability = tsAccountManager.phoneNumberDiscoverability(tx: tx)

        return AccountAttributes(
            isManualMessageFetchEnabled: isManualMessageFetchEnabled,
            registrationId: aciRegistrationId,
            pniRegistrationId: pniRegistrationId,
            unidentifiedAccessKey: udAccessKey,
            unrestrictedUnidentifiedAccess: allowUnrestrictedUD,
            reglockToken: reglockToken,
            registrationRecoveryPassword: registrationRecoveryPassword,
            encryptedDeviceName: nil,
            discoverableByPhoneNumber: phoneNumberDiscoverability,
            hasSVRBackups: hasSVRBackups
        )
    }
}
