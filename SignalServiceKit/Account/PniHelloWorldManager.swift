//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public protocol PniHelloWorldManager {
    /// Records that performing a "PNI Hello World" operation is unnecessary,
    /// for example because we know none of our devices could possibly have
    /// incorrect PNI identity key material.
    func markHelloWorldAsUnnecessary(tx: DBWriteTransaction)

    /// Perform a "PNI Hello World" operation, if necessary. PNI Hello World
    /// refers to the distribution of PNI identity key material from a primary
    /// device that generated it to linked devices.
    ///
    /// New linked devices receive identity key material during linking.
    /// However, old linked devices may have in the past received now
    /// out-of-date PNI identity keys, or may never received any identity keys.
    ///
    /// This "hello world" operation runs when all devices on the local account
    /// are confirmed to be "PNP capable", to ensure that they have the correct
    /// PNI identity key.
    func sayHelloWorldIfNecessary() async throws
}

class PniHelloWorldManagerImpl: PniHelloWorldManager {
    private enum StoreConstants {
        static let collectionName = "PniHelloWorldManagerImpl"
        static let hasSaidHelloWorldKey = "hasSaidHelloWorld"
    }

    private let logger = PrefixedLogger(prefix: "PHWM")

    private let db: any DB
    private let identityManager: any OWSIdentityManager
    private let keyValueStore: KeyValueStore
    private let networkManager: Shims.NetworkManager
    private let pniDistributionParameterBuilder: PniDistributionParamaterBuilder
    private let pniSignedPreKeyStore: SignalSignedPreKeyStore
    private let pniKyberPreKeyStore: SignalKyberPreKeyStore
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let tsAccountManager: TSAccountManager

    init(
        db: any DB,
        identityManager: any OWSIdentityManager,
        networkManager: Shims.NetworkManager,
        pniDistributionParameterBuilder: PniDistributionParamaterBuilder,
        pniSignedPreKeyStore: SignalSignedPreKeyStore,
        pniKyberPreKeyStore: SignalKyberPreKeyStore,
        recipientDatabaseTable: any RecipientDatabaseTable,
        tsAccountManager: TSAccountManager
    ) {
        self.db = db
        self.identityManager = identityManager
        self.keyValueStore = KeyValueStore(collection: StoreConstants.collectionName)
        self.networkManager = networkManager
        self.pniDistributionParameterBuilder = pniDistributionParameterBuilder
        self.pniSignedPreKeyStore = pniSignedPreKeyStore
        self.pniKyberPreKeyStore = pniKyberPreKeyStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.tsAccountManager = tsAccountManager
    }

    func markHelloWorldAsUnnecessary(tx: DBWriteTransaction) {
        keyValueStore.setBool(true, key: StoreConstants.hasSaidHelloWorldKey, transaction: tx)
    }

    func sayHelloWorldIfNecessary() async throws {
        let logger = logger

        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice else {
            return
        }

        let hasSaidHelloWorld = db.read { tx in
            return keyValueStore.getBool(
                StoreConstants.hasSaidHelloWorldKey,
                defaultValue: false,
                transaction: tx
            )
        }
        if hasSaidHelloWorld {
            return
        }
        try await _sayHelloWorld()
        await self.db.awaitableWrite { tx in
            self.keyValueStore.setBool(
                true,
                key: StoreConstants.hasSaidHelloWorldKey,
                transaction: tx
            )
        }
        logger.info("Hello world succeeded!")
    }

    private struct PniDistributionAccountState {
        var localIdentifiers: LocalIdentifiers
        var localE164: E164
        var localRecipient: SignalRecipient
        var localPniIdentityKeyPair: ECKeyPair
        var localDeviceId: UInt32
        var localDevicePniRegistrationId: UInt32
        var localDevicePniSignedPreKey: SignalServiceKit.SignedPreKeyRecord
        var localDevicePniPqLastResortPreKey: SignalServiceKit.KyberPreKeyRecord
    }

    private func buildAccountState(tx: DBWriteTransaction) -> PniDistributionAccountState? {
        guard
            let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx),
            let localE164 = E164(localIdentifiers.phoneNumber),
            let localRecipient = recipientDatabaseTable.fetchRecipient(serviceId: localIdentifiers.aci, transaction: tx)
        else {
            return nil
        }

        let localPniIdentityKeyPair: ECKeyPair
        if let existingKeyPair = identityManager.identityKeyPair(for: .pni, tx: tx) {
            localPniIdentityKeyPair = existingKeyPair
        } else {
            localPniIdentityKeyPair = identityManager.generateNewIdentityKeyPair()
            identityManager.setIdentityKeyPair(localPniIdentityKeyPair, for: .pni, tx: tx)
        }

        let localDeviceId = tsAccountManager.storedDeviceId(tx: tx)
        let localDevicePniRegistrationId = tsAccountManager.getOrGeneratePniRegistrationId(tx: tx)

        let localDevicePniSignedPreKey = pniSignedPreKeyStore.generateSignedPreKey(signedBy: localPniIdentityKeyPair)
        pniSignedPreKeyStore.storeSignedPreKey(localDevicePniSignedPreKey.id, signedPreKeyRecord: localDevicePniSignedPreKey, tx: tx)

        let localDevicePniPqLastResortPreKey = pniKyberPreKeyStore.generateLastResortKyberPreKey(signedBy: localPniIdentityKeyPair, tx: tx)
        do {
            try pniKyberPreKeyStore.storeLastResortPreKey(record: localDevicePniPqLastResortPreKey, tx: tx)
        } catch {
            owsFailDebug("Couldn't save last resort pq pre key: \(error)")
            return nil
        }

        return PniDistributionAccountState(
            localIdentifiers: localIdentifiers,
            localE164: localE164,
            localRecipient: localRecipient,
            localPniIdentityKeyPair: localPniIdentityKeyPair,
            localDeviceId: localDeviceId,
            localDevicePniRegistrationId: localDevicePniRegistrationId,
            localDevicePniSignedPreKey: localDevicePniSignedPreKey,
            localDevicePniPqLastResortPreKey: localDevicePniPqLastResortPreKey
        )
    }

    private func _sayHelloWorld() async throws {
        let accountState = await db.awaitableWrite { tx in
            return self.buildAccountState(tx: tx)
        }
        guard let accountState, accountState.localIdentifiers.pni != nil else {
            throw OWSGenericError("Skipping PNI Hello World, missing local account parameters!")
        }

        logger.info("Building PNI distribution parameters.")

        let pniDistributionParameters = try await self.pniDistributionParameterBuilder.buildPniDistributionParameters(
            localAci: accountState.localIdentifiers.aci,
            localRecipientUniqueId: accountState.localRecipient.uniqueId,
            localDeviceId: accountState.localDeviceId,
            localUserAllDeviceIds: accountState.localRecipient.deviceIds,
            localPniIdentityKeyPair: accountState.localPniIdentityKeyPair,
            localE164: accountState.localE164,
            localDevicePniSignedPreKey: accountState.localDevicePniSignedPreKey,
            localDevicePniPqLastResortPreKey: accountState.localDevicePniPqLastResortPreKey,
            localDevicePniRegistrationId: accountState.localDevicePniRegistrationId
        )

        try await self.networkManager.makeHelloWorldRequest(pniDistributionParameters: pniDistributionParameters)
    }
}

private extension OWSRequestFactory {
    static func pniHelloWorldRequest(
        pniDistributionParameters: PniDistribution.Parameters
    ) -> TSRequest {
        return TSRequest(
            url: URL(string: "v2/accounts/phone_number_identity_key_distribution")!,
            method: HTTPMethod.put.methodName,
            parameters: pniDistributionParameters.requestParameters()
        )
    }
}

// MARK: - Dependencies

extension PniHelloWorldManagerImpl {
    enum Shims {
        typealias NetworkManager = _PniHelloWorldManagerImpl_NetworkManager_Shim
    }

    enum Wrappers {
        typealias NetworkManager = _PniHelloWorldManagerImpl_NetworkManager_Wrapper
    }
}

// MARK: NetworkManager

protocol _PniHelloWorldManagerImpl_NetworkManager_Shim {
    func makeHelloWorldRequest(pniDistributionParameters: PniDistribution.Parameters) async throws
}

class _PniHelloWorldManagerImpl_NetworkManager_Wrapper: _PniHelloWorldManagerImpl_NetworkManager_Shim {
    private let networkManager: NetworkManager

    init(_ networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    func makeHelloWorldRequest(pniDistributionParameters: PniDistribution.Parameters) async throws {
        let helloWorldRequest = OWSRequestFactory.pniHelloWorldRequest(
            pniDistributionParameters: pniDistributionParameters
        )

        _ = try await networkManager.asyncRequest(helloWorldRequest)
    }
}

// MARK: -

#if TESTABLE_BUILD

struct PniHelloWorldManagerMock: PniHelloWorldManager {
    func markHelloWorldAsUnnecessary(tx: DBWriteTransaction) {}

    func sayHelloWorldIfNecessary() async throws {}
}

#endif
