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
    func sayHelloWorldIfNecessary(tx: DBWriteTransaction)
}

class PniHelloWorldManagerImpl: PniHelloWorldManager {
    private enum StoreConstants {
        static let collectionName = "PniHelloWorldManagerImpl"
        static let hasSaidHelloWorldKey = "hasSaidHelloWorld"
    }

    private let logger = PrefixedLogger(prefix: "PHWM")

    private let database: any DB
    private let identityManager: any OWSIdentityManager
    private let keyValueStore: KeyValueStore
    private let networkManager: Shims.NetworkManager
    private let pniDistributionParameterBuilder: PniDistributionParamaterBuilder
    private let pniSignedPreKeyStore: SignalSignedPreKeyStore
    private let pniKyberPreKeyStore: SignalKyberPreKeyStore
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let schedulers: Schedulers
    private let tsAccountManager: TSAccountManager

    init(
        database: any DB,
        identityManager: any OWSIdentityManager,
        networkManager: Shims.NetworkManager,
        pniDistributionParameterBuilder: PniDistributionParamaterBuilder,
        pniSignedPreKeyStore: SignalSignedPreKeyStore,
        pniKyberPreKeyStore: SignalKyberPreKeyStore,
        recipientDatabaseTable: any RecipientDatabaseTable,
        schedulers: Schedulers,
        tsAccountManager: TSAccountManager
    ) {
        self.database = database
        self.identityManager = identityManager
        self.keyValueStore = KeyValueStore(collection: StoreConstants.collectionName)
        self.networkManager = networkManager
        self.pniDistributionParameterBuilder = pniDistributionParameterBuilder
        self.pniSignedPreKeyStore = pniSignedPreKeyStore
        self.pniKyberPreKeyStore = pniKyberPreKeyStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.schedulers = schedulers
        self.tsAccountManager = tsAccountManager
    }

    func markHelloWorldAsUnnecessary(tx: any DBWriteTransaction) {
        keyValueStore.setBool(true, key: StoreConstants.hasSaidHelloWorldKey, transaction: tx)
    }

    func sayHelloWorldIfNecessary(tx syncTx: DBWriteTransaction) {
        let logger = logger

        guard tsAccountManager.registrationState(tx: syncTx).isRegisteredPrimaryDevice else {
            return
        }

        guard !keyValueStore.getBool(
            StoreConstants.hasSaidHelloWorldKey,
            defaultValue: false,
            transaction: syncTx
        ) else {
            return
        }

        guard
            let localIdentifiers = tsAccountManager.localIdentifiers(tx: syncTx),
            localIdentifiers.pni != nil,
            let localE164 = E164(localIdentifiers.phoneNumber),
            let localRecipient = recipientDatabaseTable.fetchRecipient(serviceId: localIdentifiers.aci, transaction: syncTx)
        else {
            logger.warn("Skipping PNI Hello World, missing local account parameters!")
            return
        }
        let localRecipientUniqueId = localRecipient.uniqueId
        let localDeviceIds = localRecipient.deviceIds

        let localPniIdentityKeyPair: ECKeyPair
        if let existingKeyPair = identityManager.identityKeyPair(for: .pni, tx: syncTx) {
            localPniIdentityKeyPair = existingKeyPair
        } else {
            localPniIdentityKeyPair = identityManager.generateNewIdentityKeyPair()
            identityManager.setIdentityKeyPair(localPniIdentityKeyPair, for: .pni, tx: syncTx)
        }

        let localDeviceId = tsAccountManager.storedDeviceId(tx: syncTx)
        let localDevicePniRegistrationId = tsAccountManager.getOrGeneratePniRegistrationId(tx: syncTx)

        let localDevicePniSignedPreKey = pniSignedPreKeyStore.generateSignedPreKey(signedBy: localPniIdentityKeyPair)
        pniSignedPreKeyStore.storeSignedPreKey(localDevicePniSignedPreKey.id, signedPreKeyRecord: localDevicePniSignedPreKey, tx: syncTx)

        let localDevicePniPqLastResortPreKey: KyberPreKeyRecord
        do {
            localDevicePniPqLastResortPreKey = try pniKyberPreKeyStore.generateLastResortKyberPreKey(signedBy: localPniIdentityKeyPair, tx: syncTx)
            try pniKyberPreKeyStore.storeLastResortPreKey(record: localDevicePniPqLastResortPreKey, tx: syncTx)
        } catch {
            logger.warn("Skipping PNI Hello World; couldn't generate last resort key")
            return
        }

        firstly(on: schedulers.sync) { () -> Guarantee<PniDistribution.ParameterGenerationResult> in
            logger.info("Building PNI distribution parameters.")

            return self.pniDistributionParameterBuilder.buildPniDistributionParameters(
                localAci: localIdentifiers.aci,
                localRecipientUniqueId: localRecipientUniqueId,
                localDeviceId: localDeviceId,
                localUserAllDeviceIds: localDeviceIds,
                localPniIdentityKeyPair: localPniIdentityKeyPair,
                localE164: localE164,
                localDevicePniSignedPreKey: localDevicePniSignedPreKey,
                localDevicePniPqLastResortPreKey: localDevicePniPqLastResortPreKey,
                localDevicePniRegistrationId: localDevicePniRegistrationId
            )
        }.map(on: schedulers.sync) { parameterGenerationResult throws -> PniDistribution.Parameters in
            switch parameterGenerationResult {
            case .success(let parameters):
                return parameters
            case .failure:
                throw OWSGenericError("Failed to generate PNI distribution parameters!")
            }
        }.then(on: schedulers.sync) { pniDistributionParameters -> Promise<Void> in
            logger.info("Making hello world request.")

            return self.networkManager.makeHelloWorldRequest(
                pniDistributionParameters: pniDistributionParameters
            )
        }.done(on: schedulers.global()) {
            self.database.write { tx in
                self.keyValueStore.setBool(
                    true,
                    key: StoreConstants.hasSaidHelloWorldKey,
                    transaction: tx
                )
            }

            logger.info("Hello world succeeded!")
        }.catch(on: schedulers.sync) { error in
            logger.error("Failed to say Hello World! \(error)")
        }
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
    func makeHelloWorldRequest(pniDistributionParameters: PniDistribution.Parameters) -> Promise<Void>
}

class _PniHelloWorldManagerImpl_NetworkManager_Wrapper: _PniHelloWorldManagerImpl_NetworkManager_Shim {
    private let networkManager: NetworkManager

    init(_ networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    func makeHelloWorldRequest(pniDistributionParameters: PniDistribution.Parameters) -> Promise<Void> {
        let helloWorldRequest = OWSRequestFactory.pniHelloWorldRequest(
            pniDistributionParameters: pniDistributionParameters
        )

        return networkManager.makePromise(request: helloWorldRequest).asVoid()
    }
}

// MARK: -

#if TESTABLE_BUILD

struct PniHelloWorldManagerMock: PniHelloWorldManager {
    func markHelloWorldAsUnnecessary(tx: any DBWriteTransaction) {}

    func sayHelloWorldIfNecessary(tx: any DBWriteTransaction) {}
}

#endif
