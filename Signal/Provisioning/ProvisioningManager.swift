//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit
public import LibSignalClient

public class ProvisioningManager {

    private let accountKeyStore: AccountKeyStore
    private let db: any DB
    private let deviceManager: OWSDeviceManager
    private let deviceProvisioningService: DeviceProvisioningService
    private let identityManager: OWSIdentityManager
    private let linkAndSyncManager: LinkAndSyncManager
    private let profileManager: Shims.ProfileManager
    private let receiptManager: Shims.ReceiptManager
    private let tsAccountManager: TSAccountManager

    init(
        accountKeyStore: AccountKeyStore,
        db: any DB,
        deviceManager: OWSDeviceManager,
        deviceProvisioningService: DeviceProvisioningService,
        identityManager: OWSIdentityManager,
        linkAndSyncManager: LinkAndSyncManager,
        profileManager: Shims.ProfileManager,
        receiptManager: Shims.ReceiptManager,
        tsAccountManager: TSAccountManager
    ) {
        self.accountKeyStore = accountKeyStore
        self.db = db
        self.deviceManager = deviceManager
        self.deviceProvisioningService = deviceProvisioningService
        self.identityManager = identityManager
        self.linkAndSyncManager = linkAndSyncManager
        self.profileManager = profileManager
        self.receiptManager = receiptManager
        self.tsAccountManager = tsAccountManager
    }

    public func provision(
        with deviceProvisioningUrl: DeviceProvisioningURL,
        shouldLinkNSync: Bool
    ) async throws -> (BackupKey?, DeviceProvisioningTokenId) {
        // Optimistically set this flag.
        await db.awaitableWrite { deviceManager.setMightHaveUnknownLinkedDevice(true, transaction: $0) }

        struct ProvisioningState {
            var localIdentifiers: LocalIdentifiers
            var aciIdentityKeyPair: ECKeyPair
            var pniIdentityKeyPair: ECKeyPair
            var areReadReceiptsEnabled: Bool
            var rootKey: ProvisioningMessage.RootKey
            var mediaRootBackupKey: BackupKey
            var profileKey: Aes256Key
        }

        let ephemeralBackupKey: BackupKey?
        if
            FeatureFlags.linkAndSyncPrimaryExport,
            shouldLinkNSync,
            deviceProvisioningUrl.capabilities.contains(where: { $0 == .linknsync })
        {
            ephemeralBackupKey = linkAndSyncManager.generateEphemeralBackupKey()
        } else {
            ephemeralBackupKey = nil
        }

        let provisioningState = await db.awaitableWrite { tx in
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else { owsFail("Can't provision without an aci & phone number.")
            }
            guard let aciIdentityKeyPair = identityManager.identityKeyPair(for: .aci, tx: tx) else {
                owsFail("Can't provision without an aci identity.")
            }
            guard let pniIdentityKeyPair = identityManager.identityKeyPair(for: .pni, tx: tx) else {
                owsFail("Can't provision without a pni identity.")
            }
            let areReadReceiptsEnabled = receiptManager.areReadReceiptsEnabled(tx: tx)
            let rootKey: ProvisioningMessage.RootKey
            if FeatureFlags.enableAccountEntropyPool {
                guard let accountEntropyPool = accountKeyStore.getAccountEntropyPool(tx: tx) else {
                    // This should be impossible; the only times you don't have
                    // an AEP are during registration.
                    owsFail("Can't provision without account entropy pool.")
                }
                rootKey = .accountEntropyPool(accountEntropyPool)
            } else {
                guard let masterKey = accountKeyStore.getMasterKey(tx: tx) else {
                    // This should be impossible; the only times you don't have
                    // a master key are during registration.
                    owsFail("Can't provision without master key.")
                }
                rootKey = .masterKey(masterKey)
            }
            let mrbk = accountKeyStore.getOrGenerateMediaRootBackupKey(tx: tx)
            guard let profileKey = profileManager.localUserProfile(tx: tx)?.profileKey else {
                owsFail("Can't provision without a profile key.")
            }
            return ProvisioningState(
                localIdentifiers: localIdentifiers,
                aciIdentityKeyPair: aciIdentityKeyPair,
                pniIdentityKeyPair: pniIdentityKeyPair,
                areReadReceiptsEnabled: areReadReceiptsEnabled,
                rootKey: rootKey,
                mediaRootBackupKey: mrbk,
                profileKey: profileKey
            )
        }

        let myAci = provisioningState.localIdentifiers.aci
        let myPhoneNumber = provisioningState.localIdentifiers.phoneNumber
        guard let myPni = provisioningState.localIdentifiers.pni else {
            owsFail("Can't provision without a pni.")
        }

        let provisioningCode = try await deviceProvisioningService.requestDeviceProvisioningCode()

        let provisioningMessage = ProvisioningMessage(
            rootKey: provisioningState.rootKey,
            aci: myAci,
            phoneNumber: myPhoneNumber,
            pni: myPni,
            aciIdentityKeyPair: provisioningState.aciIdentityKeyPair.identityKeyPair,
            pniIdentityKeyPair: provisioningState.pniIdentityKeyPair.identityKeyPair,
            profileKey: provisioningState.profileKey,
            mrbk: provisioningState.mediaRootBackupKey,
            ephemeralBackupKey: ephemeralBackupKey,
            areReadReceiptsEnabled: provisioningState.areReadReceiptsEnabled,
            provisioningCode: provisioningCode.verificationCode
        )

        let theirPublicKey = deviceProvisioningUrl.publicKey
        let messageBody = try provisioningMessage.buildEncryptedMessageBody(theirPublicKey: theirPublicKey)
        try await deviceProvisioningService.provisionDevice(
            messageBody: messageBody,
            ephemeralDeviceId: deviceProvisioningUrl.ephemeralDeviceId
        )
        return (ephemeralBackupKey, provisioningCode.tokenId)
    }
}
