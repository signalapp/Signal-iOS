//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

protocol PniIdentityKeyChecker {
    func serverHasSameKeyAsLocal(
        localPni: Pni,
        tx: DBReadTransaction
    ) -> Promise<Bool>
}

class PniIdentityKeyCheckerImpl: PniIdentityKeyChecker {
    fileprivate static let logger = PrefixedLogger(prefix: "PIKC")

    private let db: any DB
    private let identityManager: Shims.IdentityManager
    private let profileFetcher: Shims.ProfileFetcher
    private let schedulers: Schedulers

    init(
        db: any DB,
        identityManager: Shims.IdentityManager,
        profileFetcher: Shims.ProfileFetcher,
        schedulers: Schedulers
    ) {
        self.db = db
        self.identityManager = identityManager
        self.profileFetcher = profileFetcher
        self.schedulers = schedulers
    }

    func serverHasSameKeyAsLocal(
        localPni: Pni,
        tx syncTx: DBReadTransaction
    ) -> Promise<Bool> {
        let logger = Self.logger

        if identityManager.pniIdentityKey(tx: syncTx) == nil {
            // If we have no PNI identity key, we can say it doesn't match.
            return .value(false)
        }

        return Promise.wrapAsync {
            return try await self.profileFetcher.fetchPniIdentityPublicKey(localPni: localPni)
        }.map(on: self.schedulers.global()) { remotePniIdentityKey -> Bool in
            guard let localPniIdentityKey = self.db.read(block: { tx -> IdentityKey? in
                return self.identityManager.pniIdentityKey(tx: tx)
            }) else {
                logger.warn("Missing local PNI identity key!")
                return false
            }

            if let remotePniIdentityKey, remotePniIdentityKey == localPniIdentityKey {
                logger.info("Local PNI identity key matches server.")
                return true
            }

            logger.warn("Local PNI identity key does not match server!")
            return false
        }.recover(on: self.schedulers.sync) { error throws -> Promise<Bool> in
            logger.error("Error checking remote identity key: \(error)!")
            throw error
        }
    }
}

// MARK: - Dependencies

extension PniIdentityKeyCheckerImpl {
    enum Shims {
        typealias IdentityManager = _PniIdentityKeyCheckerImpl_IdentityManager_Shim
        typealias ProfileFetcher = _PniIdentityKeyCheckerImpl_ProfileFetcher_Shim
    }

    enum Wrappers {
        typealias IdentityManager = _PniIdentityKeyCheckerImpl_IdentityManager_Wrapper
        typealias ProfileFetcher = _PniIdentityKeyCheckerImpl_ProfileFetcher_Wrapper
    }
}

// MARK: IdentityManager

protocol _PniIdentityKeyCheckerImpl_IdentityManager_Shim {
    func pniIdentityKey(tx: DBReadTransaction) -> IdentityKey?
}

class _PniIdentityKeyCheckerImpl_IdentityManager_Wrapper: _PniIdentityKeyCheckerImpl_IdentityManager_Shim {
    private let identityManager: OWSIdentityManager

    init(_ identityManager: OWSIdentityManager) {
        self.identityManager = identityManager
    }

    func pniIdentityKey(tx: DBReadTransaction) -> IdentityKey? {
        return identityManager.identityKeyPair(for: .pni, tx: tx)?.keyPair.identityKey
    }
}

// MARK: ProfileFetcher

protocol _PniIdentityKeyCheckerImpl_ProfileFetcher_Shim {
    func fetchPniIdentityPublicKey(localPni: Pni) async throws -> IdentityKey?
}

class _PniIdentityKeyCheckerImpl_ProfileFetcher_Wrapper: _PniIdentityKeyCheckerImpl_ProfileFetcher_Shim {
    private let schedulers: Schedulers

    init(schedulers: Schedulers) {
        self.schedulers = schedulers
    }

    func fetchPniIdentityPublicKey(localPni: Pni) async throws -> IdentityKey? {
        let logger = PniIdentityKeyCheckerImpl.logger

        do {
            let request = OWSRequestFactory.getUnversionedProfileRequest(
                serviceId: localPni,
                sealedSenderAuth: nil,
                auth: .implicit()
            )
            let response = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request, canUseWebSocket: true)
            guard let bodyData = response.responseBodyData else {
                throw OWSGenericError("Couldn't handle success response without data.")
            }

            struct Response: Decodable {
                var identityKey: Data?
            }

            let decodedResponse = try JSONDecoder().decode(Response.self, from: bodyData)
            return try decodedResponse.identityKey.map { try IdentityKey(bytes: $0) }
        } catch where error.httpStatusCode == 404 {
            logger.warn("Server does not have a profile for the given PNI.")
            return nil
        }
    }
}
