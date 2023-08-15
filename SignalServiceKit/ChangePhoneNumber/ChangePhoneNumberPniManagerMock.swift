//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class ChangePhoneNumberPniManagerMock: ChangePhoneNumberPniManager {

    private let mockKyberStore: SignalKyberPreKeyStore

    public init(mockKyberStore: SignalKyberPreKeyStore) {
        self.mockKyberStore = mockKyberStore
    }

    public func generatePniIdentity(
        forNewE164 newE164: E164,
        localAci: UntypedServiceId,
        localAccountId: String,
        localDeviceId: UInt32,
        localUserAllDeviceIds: [UInt32]
    ) -> Guarantee<ChangePhoneNumberPni.GeneratePniIdentityResult> {
        let keyPair = Curve25519.generateKeyPair()
        let registrationId = UInt32.random(in: 1...0x3fff)

        let localPqKey1 = try! self.mockKyberStore.generateEphemeralLastResortKyberPreKey(signedBy: keyPair)
        let localPqKey2 = try! self.mockKyberStore.generateEphemeralLastResortKyberPreKey(signedBy: keyPair)

        return .value(.success(
            parameters: PniDistribution.Parameters.mock(
                pniIdentityKeyPair: keyPair,
                localDeviceId: localDeviceId,
                localDevicePniSignedPreKey: SSKSignedPreKeyStore.generateSignedPreKey(signedBy: keyPair),
                localDevicePniPqLastResortPreKey: localPqKey1,
                localDevicePniRegistrationId: registrationId
            ),
            pendingState: ChangePhoneNumberPni.PendingState(
                newE164: newE164,
                pniIdentityKeyPair: keyPair,
                localDevicePniSignedPreKeyRecord: SSKSignedPreKeyStore.generateSignedPreKey(signedBy: keyPair),
                localDevicePniPqLastResortPreKeyRecord: localPqKey2,
                localDevicePniRegistrationId: registrationId
            )
        ))
    }

    public func finalizePniIdentity(
        withPendingState pendingState: ChangePhoneNumberPni.PendingState,
        transaction: DBWriteTransaction
    ) throws {
        // do nothing
    }
}

#endif
