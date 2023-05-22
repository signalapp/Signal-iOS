//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Curve25519Kit

extension ChangePhoneNumberPniManagerImpl {
    enum Shims {
        typealias IdentityManager = _ChangePhoneNumberPniManager_IdentityManagerShim
        typealias PreKeyManager = _ChangePhoneNumberPniManager_PreKeyManagerShim
        typealias SignedPreKeyStore = _ChangePhoneNumberPniManager_SignedPreKeyStoreShim
        typealias TSAccountManager = _ChangePhoneNumberPniManager_TSAccountManagerShim
    }

    enum Wrappers {
        typealias IdentityManager = _ChangePhoneNumberPniManager_IdentityManagerWrapper
        typealias PreKeyManager = _ChangePhoneNumberPniManager_PreKeyManagerWrapper
        typealias SignedPreKeyStore = _ChangePhoneNumberPniManager_SignedPreKeyStoreWrapper
        typealias TSAccountManager = _ChangePhoneNumberPniManager_TSAccountManagerWrapper
    }
}

// MARK: - Shims

protocol _ChangePhoneNumberPniManager_IdentityManagerShim {
    func generateNewIdentityKeyPair() -> ECKeyPair

    func storeIdentityKeyPair(
        _ keyPair: ECKeyPair?,
        for identity: OWSIdentity,
        transaction: DBWriteTransaction
    )
}

protocol _ChangePhoneNumberPniManager_PreKeyManagerShim {
    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    )
}

protocol _ChangePhoneNumberPniManager_SignedPreKeyStoreShim {
    func generateSignedPreKey(signedBy: ECKeyPair) -> SignedPreKeyRecord

    func storeSignedPreKeyAsAcceptedAndCurrent(
        signedPreKeyId: Int32,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        transaction: DBWriteTransaction
    )
}

protocol _ChangePhoneNumberPniManager_TSAccountManagerShim {
    func generateRegistrationId() -> UInt32

    func setPniRegistrationId(
        newRegistrationId: UInt32,
        transaction: DBWriteTransaction
    )
}

// MARK: - Wrappers

class _ChangePhoneNumberPniManager_IdentityManagerWrapper: _ChangePhoneNumberPniManager_IdentityManagerShim {
    private let identityManager: OWSIdentityManager

    init(_ identityManager: OWSIdentityManager) {
        self.identityManager = identityManager
    }

    func generateNewIdentityKeyPair() -> ECKeyPair {
        identityManager.generateNewIdentityKeyPair()
    }

    func storeIdentityKeyPair(
        _ keyPair: ECKeyPair?,
        for identity: OWSIdentity,
        transaction: DBWriteTransaction
    ) {
        identityManager.storeIdentityKeyPair(
            keyPair,
            for: identity,
            transaction: SDSDB.shimOnlyBridge(transaction)
        )
    }
}

class _ChangePhoneNumberPniManager_PreKeyManagerWrapper: _ChangePhoneNumberPniManager_PreKeyManagerShim {
    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    ) {
        TSPreKeyManager.refreshOneTimePreKeys(
            forIdentity: identity,
            alsoRefreshSignedPreKey: shouldRefreshSignedPreKey
        )
    }
}

class _ChangePhoneNumberPniManager_SignedPreKeyStoreWrapper: _ChangePhoneNumberPniManager_SignedPreKeyStoreShim {
    private let signedPreKeyStore: SSKSignedPreKeyStore

    init(_ signedPreKeyStore: SSKSignedPreKeyStore) {
        self.signedPreKeyStore = signedPreKeyStore
    }

    func generateSignedPreKey(signedBy: ECKeyPair) -> SignedPreKeyRecord {
        return SSKSignedPreKeyStore.generateSignedPreKey(signedBy: signedBy)
    }

    func storeSignedPreKeyAsAcceptedAndCurrent(
        signedPreKeyId: Int32,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        transaction: DBWriteTransaction
    ) {
        signedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
            signedPreKeyId: signedPreKeyId,
            signedPreKeyRecord: signedPreKeyRecord,
            transaction: SDSDB.shimOnlyBridge(transaction)
        )
    }
}

class _ChangePhoneNumberPniManager_TSAccountManagerWrapper: _ChangePhoneNumberPniManager_TSAccountManagerShim {
    private let tsAccountManager: TSAccountManager

    init(_ tsAccountManager: TSAccountManager) {
        self.tsAccountManager = tsAccountManager
    }

    func generateRegistrationId() -> UInt32 {
        return TSAccountManager.generateRegistrationId()
    }

    func setPniRegistrationId(
        newRegistrationId: UInt32,
        transaction: DBWriteTransaction
    ) {
        tsAccountManager.setPniRegistrationId(
            newRegistrationId: newRegistrationId,
            transaction: SDSDB.shimOnlyBridge(transaction)
        )
    }
}
