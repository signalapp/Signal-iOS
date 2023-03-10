//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension ChangePhoneNumberPniManagerImpl {
    enum Shims {
        typealias IdentityManager = _ChangePhoneNumberPniManager_IdentityManagerShim
        typealias MessageSender = _ChangePhoneNumberPniManager_MessageSenderShim
        typealias PreKeyManager = _ChangePhoneNumberPniManager_PreKeyManagerShim
        typealias SignedPreKeyStore = _ChangePhoneNumberPniManager_SignedPreKeyStoreShim
        typealias TSAccountManager = _ChangePhoneNumberPniManager_TSAccountManagerShim
    }

    enum Wrappers {
        typealias IdentityManager = _ChangePhoneNumberPniManager_IdentityManagerWrapper
        typealias MessageSender = _ChangePhoneNumberPniManager_MessageSenderWrapper
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

protocol _ChangePhoneNumberPniManager_MessageSenderShim {
    func buildDeviceMessage(
        forMessagePlaintextContent messagePlaintextContent: Data?,
        messageEncryptionStyle: EncryptionStyle,
        recipientServiceId: ServiceId,
        recipientAccountId: String,
        recipientDeviceId: NSNumber,
        isOnlineMessage: Bool,
        isTransientSenderKeyDistributionMessage: Bool,
        isStorySendMessage: Bool,
        isResendRequestMessage: Bool,
        udSendingParamsProvider: UDSendingParamsProvider?
    ) throws -> DeviceMessage?
}

protocol _ChangePhoneNumberPniManager_PreKeyManagerShim {
    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    )
}

protocol _ChangePhoneNumberPniManager_SignedPreKeyStoreShim {
    func storeSignedPreKeyAsAcceptedAndCurrent(
        signedPreKeyId: Int32,
        signedPreKeyRecord: SignalServiceKit.SignedPreKeyRecord,
        transaction: DBWriteTransaction
    )
}

protocol _ChangePhoneNumberPniManager_TSAccountManagerShim {
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

class _ChangePhoneNumberPniManager_MessageSenderWrapper: _ChangePhoneNumberPniManager_MessageSenderShim {
    private let messageSender: MessageSender

    init(_ messageSender: MessageSender) {
        self.messageSender = messageSender
    }

    func buildDeviceMessage(
        forMessagePlaintextContent messagePlaintextContent: Data?,
        messageEncryptionStyle: EncryptionStyle,
        recipientServiceId: ServiceId,
        recipientAccountId: String,
        recipientDeviceId: NSNumber,
        isOnlineMessage: Bool,
        isTransientSenderKeyDistributionMessage: Bool,
        isStorySendMessage: Bool,
        isResendRequestMessage: Bool,
        udSendingParamsProvider: UDSendingParamsProvider?
    ) throws -> DeviceMessage? {
        try messageSender.buildDeviceMessage(
            forMessagePlaintextContent: messagePlaintextContent,
            messageEncryptionStyle: messageEncryptionStyle,
            recipientAddress: SignalServiceAddress(recipientServiceId),
            recipientAccountId: recipientAccountId,
            recipientDeviceId: recipientDeviceId,
            isOnlineMessage: isOnlineMessage,
            isTransientSenderKeyDistributionMessage: isTransientSenderKeyDistributionMessage,
            isStorySendMessage: isStorySendMessage,
            isResendRequestMessage: isResendRequestMessage,
            udSendingParamsProvider: udSendingParamsProvider
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
