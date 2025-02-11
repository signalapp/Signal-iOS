//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

protocol PniIdentityKeyChecker {
    func serverHasSameKeyAsLocal(localPni: Pni) async throws -> Bool
}

class PniIdentityKeyCheckerImpl: PniIdentityKeyChecker {
    private let db: any DB
    private let identityManager: Shims.IdentityManager
    private let profileFetcher: Shims.ProfileFetcher

    init(
        db: any DB,
        identityManager: Shims.IdentityManager,
        profileFetcher: Shims.ProfileFetcher
    ) {
        self.db = db
        self.identityManager = identityManager
        self.profileFetcher = profileFetcher
    }

    func serverHasSameKeyAsLocal(localPni: Pni) async throws -> Bool {
        let remotePniIdentityKey = try await self.profileFetcher.fetchPniIdentityPublicKey(localPni: localPni)

        let localPniIdentityKey = self.db.read(block: { tx -> IdentityKey? in
            return self.identityManager.pniIdentityKey(tx: tx)
        })

        return remotePniIdentityKey != nil && remotePniIdentityKey == localPniIdentityKey
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
        do {
            let request = OWSRequestFactory.getUnversionedProfileRequest(
                serviceId: localPni,
                sealedSenderAuth: nil,
                auth: .implicit()
            )
            let response = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)

            struct Response: Decodable {
                var identityKey: Data?
            }

            let decodedResponse = try JSONDecoder().decode(Response.self, from: (response.responseBodyData ?? Data()))
            return try decodedResponse.identityKey.map { try IdentityKey(bytes: $0) }
        } catch where error.httpStatusCode == 404 {
            return nil
        }
    }
}
