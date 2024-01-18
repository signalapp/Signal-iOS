//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol IncomingPniChangeNumberProcessor {

    func processIncomingPniChangePhoneNumber(
        proto: SSKProtoSyncMessagePniChangeNumber,
        updatedPni updatedPniString: String?,
        tx: DBWriteTransaction
    )
}

public class IncomingPniChangeNumberProcessorImpl: IncomingPniChangeNumberProcessor {

    private let identityManager: OWSIdentityManager
    private let pniProtocolStore: SignalProtocolStore
    private let preKeyManager: PreKeyManager
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let tsAccountManager: TSAccountManager

    public init(
        identityManager: OWSIdentityManager,
        pniProtocolStore: SignalProtocolStore,
        preKeyManager: PreKeyManager,
        registrationStateChangeManager: RegistrationStateChangeManager,
        tsAccountManager: TSAccountManager
    ) {
        self.identityManager = identityManager
        self.pniProtocolStore = pniProtocolStore
        self.preKeyManager = preKeyManager
        self.registrationStateChangeManager = registrationStateChangeManager
        self.tsAccountManager = tsAccountManager
    }

    private struct PniChangePhoneNumberData {
        let identityKeyPair: ECKeyPair
        let signedPreKey: SignalServiceKit.SignedPreKeyRecord
        // TODO (PQXDH): 8/14/2023 - This should me made non-optional after 90 days
        let lastResortKyberPreKey: SignalServiceKit.KyberPreKeyRecord?
        let registrationId: UInt32
        let e164: E164
    }

    public func processIncomingPniChangePhoneNumber(
        proto: SSKProtoSyncMessagePniChangeNumber,
        updatedPni updatedPniString: String?,
        tx: DBWriteTransaction
    ) {
        guard let updatedPni = Pni.parseFrom(pniString: updatedPniString) else {
            owsFailDebug("Missing or invalid updated PNI string while processing incoming PNI change-number sync message!")
            return
        }

        guard let localAci = tsAccountManager.localIdentifiers(tx: tx)?.aci else {
            owsFailDebug("Missing ACI while processing incoming PNI change-number sync message!")
            return
        }

        guard let pniChangeData = deserializeIncomingPniChangePhoneNumber(proto: proto) else {
            return
        }

        // Store in the right places

        // attempt this first and return before writing any other information
        do {
            if let lastResortKey = pniChangeData.lastResortKyberPreKey {
                try pniProtocolStore.kyberPreKeyStore.storeLastResortPreKeyAndMarkAsCurrent(
                    record: lastResortKey,
                    tx: tx
                )
            }
        } catch {
            owsFailDebug("Failed to store last resort Kyber prekey")
            return
        }

        identityManager.setIdentityKeyPair(
            pniChangeData.identityKeyPair,
            for: .pni,
            tx: tx
        )

        pniChangeData.signedPreKey.markAsAcceptedByService()
        pniProtocolStore.signedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
            signedPreKeyId: pniChangeData.signedPreKey.id,
            signedPreKeyRecord: pniChangeData.signedPreKey,
            tx: tx
        )

        tsAccountManager.setPniRegistrationId(pniChangeData.registrationId, tx: tx)
        registrationStateChangeManager.didUpdateLocalPhoneNumber(
            pniChangeData.e164,
            aci: localAci,
            pni: updatedPni,
            tx: tx
        )

        // Clean up thereafter

        // We need to refresh our one-time pre-keys, and should also refresh
        // our signed pre-key so we use the one generated on the primary for as
        // little time as possible.
        preKeyManager.refreshOneTimePreKeys(forIdentity: .pni, alsoRefreshSignedPreKey: true)
    }

    private func deserializeIncomingPniChangePhoneNumber(
        proto: SSKProtoSyncMessagePniChangeNumber
    ) -> PniChangePhoneNumberData? {
        guard
            let pniIdentityKeyPairData = proto.identityKeyPair,
            let pniSignedPreKeyData = proto.signedPreKey,
            proto.hasRegistrationID, proto.registrationID > 0,
            let newE164 = E164(proto.newE164)
        else {
            owsFailDebug("Invalid PNI change number proto, missing fields!")
            return nil
        }

        do {
            let pniIdentityKeyPair = ECKeyPair(try IdentityKeyPair(bytes: pniIdentityKeyPairData))
            let pniSignedPreKey = try LibSignalClient.SignedPreKeyRecord(bytes: pniSignedPreKeyData).asSSKRecord()

            var pniLastResortKyberPreKey: KyberPreKeyRecord?
            if let pniLastResortKyberKeyData = proto.lastResortKyberPreKey {
                pniLastResortKyberPreKey = try LibSignalClient.KyberPreKeyRecord(
                    bytes: pniLastResortKyberKeyData
                ).asSSKLastResortRecord()
            }

            let pniRegistrationId = proto.registrationID

            return PniChangePhoneNumberData(
                identityKeyPair: pniIdentityKeyPair,
                signedPreKey: pniSignedPreKey,
                lastResortKyberPreKey: pniLastResortKyberPreKey,
                registrationId: pniRegistrationId,
                e164: newE164
            )
        } catch let error {
            owsFailDebug("Error while deserializing PNI change-number proto: \(error)")
            return nil
        }
    }
}
