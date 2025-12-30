//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

public import LibSignalClient

public class ChangePhoneNumberPniManagerMock: ChangePhoneNumberPniManager {

    private let mockKyberStore: KyberPreKeyStoreImpl

    public init(mockKyberStore: KyberPreKeyStoreImpl) {
        self.mockKyberStore = mockKyberStore
    }

    public func generatePniIdentity(
        forNewE164 newE164: E164,
        localAci: Aci,
        localDeviceId: DeviceId,
    ) async -> ChangePhoneNumberPni.GeneratePniIdentityResult {
        let keyPair = ECKeyPair.generateKeyPair()
        let registrationId = UInt32.random(in: 1...0x3fff)

        let localPqKey1 = self.mockKyberStore.generateLastResortKyberPreKeyForChangeNumber(signedBy: keyPair.keyPair.privateKey)
        let localPqKey2 = self.mockKyberStore.generateLastResortKyberPreKeyForChangeNumber(signedBy: keyPair.keyPair.privateKey)

        return .success(
            parameters: PniDistribution.Parameters.mock(
                pniIdentityKeyPair: keyPair,
                localDeviceId: localDeviceId,
                localDevicePniSignedPreKey: SignedPreKeyStoreImpl.generateSignedPreKey(keyId: PreKeyId.random(), signedBy: keyPair.keyPair.privateKey),
                localDevicePniPqLastResortPreKey: localPqKey1,
                localDevicePniRegistrationId: registrationId,
            ),
            pendingState: ChangePhoneNumberPni.PendingState(
                newE164: newE164,
                pniIdentityKeyPair: keyPair,
                localDevicePniSignedPreKeyRecord: SignedPreKeyStoreImpl.generateSignedPreKey(keyId: PreKeyId.random(), signedBy: keyPair.keyPair.privateKey),
                localDevicePniPqLastResortPreKeyRecord: localPqKey2,
                localDevicePniRegistrationId: registrationId,
            ),
        )
    }

    public func finalizePniIdentity(
        identityKey: ECKeyPair,
        signedPreKey: Result<LibSignalClient.SignedPreKeyRecord, DecodingError>,
        lastResortPreKey: Result<LibSignalClient.KyberPreKeyRecord, DecodingError>,
        registrationId: UInt32,
        tx: DBWriteTransaction,
    ) throws {
        // do nothing
    }
}

#endif
