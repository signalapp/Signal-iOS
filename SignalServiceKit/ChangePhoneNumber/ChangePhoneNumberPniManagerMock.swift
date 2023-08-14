//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

#if TESTABLE_BUILD

public class ChangePhoneNumberPniManagerMock: ChangePhoneNumberPniManager {

    public func generatePniIdentity(
        forNewE164 newE164: E164,
        localAci: Aci,
        localAccountId: String,
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32]
    ) -> Guarantee<ChangePhoneNumberPni.GeneratePniIdentityResult> {
        let keyPair = Curve25519.generateKeyPair()
        let registrationId = UInt32.random(in: 1...0x3fff)
        return .value(.success(
            parameters: PniDistribution.Parameters.mock(
                pniIdentityKeyPair: keyPair,
                localDeviceId: localDeviceId,
                localDevicePniSignedPreKey: SSKSignedPreKeyStore.generateSignedPreKey(signedBy: keyPair),
                localDevicePniRegistrationId: registrationId
            ),
            pendingState: ChangePhoneNumberPni.PendingState(
                newE164: newE164,
                pniIdentityKeyPair: keyPair,
                localDevicePniSignedPreKeyRecord: SSKSignedPreKeyStore.generateSignedPreKey(signedBy: keyPair),
                localDevicePniRegistrationId: registrationId
            )
        ))
    }

    public func finalizePniIdentity(
        withPendingState pendingState: ChangePhoneNumberPni.PendingState,
        transaction: DBWriteTransaction
    ) {
        // do nothing
    }
}

#endif
