//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

import Curve25519Kit
@testable import SignalServiceKit

extension ChangePhoneNumberPniManagerImpl {
    enum Mocks {
        typealias IdentityManager = _ChangePhoneNumberPniManager_IdentityManagerMock
        typealias MessageSender = _ChangePhoneNumberPniManager_MessageSenderMock
        typealias PreKeyManager = _ChangePhoneNumberPniManager_PreKeyManagerMock
        typealias SignedPreKeyStore = _ChangePhoneNumberPniManager_SignedPreKeyStoreMock
        typealias TSAccountManager = _ChangePhoneNumberPniManager_TSAccountManagerMock
    }
}

// MARK: - IdentityManager

class _ChangePhoneNumberPniManager_IdentityManagerMock: _ChangePhoneNumberPniManager_IdentityManagerShim {
    var storedKeyPairs: [OWSIdentity: ECKeyPair] = [:]

    func generateNewIdentityKeyPair() -> ECKeyPair {
        Curve25519.generateKeyPair()
    }

    func storeIdentityKeyPair(
        _ keyPair: ECKeyPair?,
        for identity: OWSIdentity,
        transaction: DBWriteTransaction
    ) {
        storedKeyPairs[identity] = keyPair
    }
}

// MARK: - MessageSender

class _ChangePhoneNumberPniManager_MessageSenderMock: _ChangePhoneNumberPniManager_MessageSenderShim {
    enum DeviceMessageMock {
        case valid(registrationId: UInt32)
        case invalidDevice
        case error
    }

    private struct BuildDeviceMessageError: Error {}

    /// Populated with device messages to be returned by ``buildDeviceMessage``.
    var deviceMessageMocks: [DeviceMessageMock] = []

    func buildDeviceMessage(
        forMessagePlaintextContent messagePlaintextContent: Data?,
        messageEncryptionStyle: EncryptionStyle,
        recipientId: String,
        serviceId: ServiceId,
        deviceId: NSNumber,
        isOnlineMessage: Bool,
        isTransientSenderKeyDistributionMessage: Bool,
        isStoryMessage: Bool,
        isResendRequestMessage: Bool,
        udSendingParamsProvider: UDSendingParamsProvider?
    ) throws -> DeviceMessage? {
        guard let nextDeviceMessageMock = deviceMessageMocks.first else {
            XCTFail("Missing mock!")
            return nil
        }

        deviceMessageMocks = Array(deviceMessageMocks.dropFirst())

        switch nextDeviceMessageMock {
        case let .valid(registrationId):
            return DeviceMessage(
                type: .ciphertext,
                destinationDeviceId: deviceId.uint32Value,
                destinationRegistrationId: registrationId,
                serializedMessage: Cryptography.generateRandomBytes(32)
            )
        case .invalidDevice:
            return nil
        case .error:
            throw BuildDeviceMessageError()
        }
    }
}

// MARK: - PreKeyManager

class _ChangePhoneNumberPniManager_PreKeyManagerMock: _ChangePhoneNumberPniManager_PreKeyManagerShim {
    var attemptedRefreshes: [(OWSIdentity, Bool)] = []

    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    ) {
        attemptedRefreshes.append((identity, shouldRefreshSignedPreKey))
    }
}

// MARK: - SignedPreKeyStore

class _ChangePhoneNumberPniManager_SignedPreKeyStoreMock: _ChangePhoneNumberPniManager_SignedPreKeyStoreShim {
    var storedSignedPreKeyId: Int32?
    var storedSignedPreKeyRecord: SignedPreKeyRecord?

    func storeSignedPreKeyAsAcceptedAndCurrent(
        signedPreKeyId: Int32,
        signedPreKeyRecord: SignedPreKeyRecord,
        transaction: DBWriteTransaction
    ) {
        storedSignedPreKeyId = signedPreKeyId
        storedSignedPreKeyRecord = signedPreKeyRecord
    }
}

// MARK: - TSAccountManager

class _ChangePhoneNumberPniManager_TSAccountManagerMock: _ChangePhoneNumberPniManager_TSAccountManagerShim {
    var storedPniRegistrationId: UInt32?

    func setPniRegistrationId(
        newRegistrationId: UInt32,
        transaction: DBWriteTransaction
    ) {
        storedPniRegistrationId = newRegistrationId
    }
}
