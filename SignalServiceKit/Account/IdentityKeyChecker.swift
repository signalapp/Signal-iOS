//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

protocol IdentityKeyChecker {
    func serverHasSameKeyAsLocal(for identity: OWSIdentity, localIdentifier: ServiceId) async throws -> Bool
}

class IdentityKeyCheckerImpl: IdentityKeyChecker {
    private let db: any DB
    private let identityManager: OWSIdentityManager
    private let profileFetcher: Shims.ProfileFetcher

    init(
        db: any DB,
        identityManager: OWSIdentityManager,
        profileFetcher: Shims.ProfileFetcher,
    ) {
        self.db = db
        self.identityManager = identityManager
        self.profileFetcher = profileFetcher
    }

    func serverHasSameKeyAsLocal(for identity: OWSIdentity, localIdentifier: ServiceId) async throws -> Bool {
        owsPrecondition((identity == .aci && localIdentifier is Aci) || (identity == .pni && localIdentifier is Pni))

        let remoteIdentityKey = try await self.profileFetcher.fetchIdentityPublicKey(serviceId: localIdentifier)
        let localIdentityKey = self.db.read(block: { tx -> IdentityKey? in
            return self.identityManager.identityKeyPair(for: identity, tx: tx)?.keyPair.identityKey
        })
        return remoteIdentityKey == localIdentityKey
    }
}

// MARK: - Dependencies

extension IdentityKeyCheckerImpl {
    enum Shims {
        typealias ProfileFetcher = _IdentityKeyCheckerImpl_ProfileFetcher_Shim
    }

    enum Wrappers {
        typealias ProfileFetcher = _IdentityKeyCheckerImpl_ProfileFetcher_Wrapper
    }
}

// MARK: ProfileFetcher

protocol _IdentityKeyCheckerImpl_ProfileFetcher_Shim {
    func fetchIdentityPublicKey(serviceId: ServiceId) async throws -> IdentityKey
}

class _IdentityKeyCheckerImpl_ProfileFetcher_Wrapper: _IdentityKeyCheckerImpl_ProfileFetcher_Shim {
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    func fetchIdentityPublicKey(serviceId: ServiceId) async throws -> IdentityKey {
        let request = OWSRequestFactory.getUnversionedProfileRequest(
            serviceId: serviceId,
            auth: .identified(.implicit()),
        )
        let response = try await networkManager.asyncRequest(request)

        struct Response: Decodable {
            var identityKey: Data
        }

        let decodedResponse = try JSONDecoder().decode(Response.self, from: response.responseBodyData ?? Data())
        return try IdentityKey(bytes: decodedResponse.identityKey)
    }
}
