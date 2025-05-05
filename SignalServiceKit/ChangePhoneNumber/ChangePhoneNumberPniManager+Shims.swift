//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension ChangePhoneNumberPniManagerImpl {
    enum Shims {
        typealias IdentityManager = _ChangePhoneNumberPniManager_IdentityManagerShim
        typealias PreKeyManager = _ChangePhoneNumberPniManager_PreKeyManagerShim
    }

    enum Wrappers {
        typealias IdentityManager = _ChangePhoneNumberPniManager_IdentityManagerWrapper
        typealias PreKeyManager = _ChangePhoneNumberPniManager_PreKeyManagerWrapper
    }
}

// MARK: - Shims

protocol _ChangePhoneNumberPniManager_IdentityManagerShim {
    func generateNewIdentityKeyPair() -> ECKeyPair

    func setIdentityKeyPair(
        _ keyPair: ECKeyPair?,
        for identity: OWSIdentity,
        tx: DBWriteTransaction
    )
}

protocol _ChangePhoneNumberPniManager_PreKeyManagerShim {
    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
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

    func setIdentityKeyPair(
        _ keyPair: ECKeyPair?,
        for identity: OWSIdentity,
        tx: DBWriteTransaction
    ) {
        identityManager.setIdentityKeyPair(keyPair, for: identity, tx: tx)
    }
}

class _ChangePhoneNumberPniManager_PreKeyManagerWrapper: _ChangePhoneNumberPniManager_PreKeyManagerShim {
    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    ) {
        DependenciesBridge.shared.preKeyManager.refreshOneTimePreKeys(
            forIdentity: identity,
            alsoRefreshSignedPreKey: shouldRefreshSignedPreKey
        )
    }
}
