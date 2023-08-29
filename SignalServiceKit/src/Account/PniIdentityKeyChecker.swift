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

    private let db: DB
    private let identityManager: Shims.IdentityManager
    private let profileFetcher: Shims.ProfileFetcher
    private let schedulers: Schedulers

    init(
        db: DB,
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

        if identityManager.pniIdentityPublicKeyData(tx: syncTx) == nil {
            // If we have no PNI identity key, we can say it doesn't match.
            return .value(false)
        }

        return firstly(on: self.schedulers.sync) { () -> Promise<Data?> in
            return self.profileFetcher.fetchPniIdentityPublicKey(localPni: localPni)
        }.map(on: self.schedulers.global()) { remotePniIdentityPublicKeyData -> Bool in
            guard let localPniIdentityPublicKeyData = self.db.read(block: { tx -> Data? in
                return self.identityManager.pniIdentityPublicKeyData(tx: tx)
            }) else {
                logger.warn("Missing local PNI identity key!")
                return false
            }

            if
                let remotePniIdentityPublicKeyData,
                remotePniIdentityPublicKeyData == localPniIdentityPublicKeyData
            {
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
    func pniIdentityPublicKeyData(tx: DBReadTransaction) -> Data?
}

class _PniIdentityKeyCheckerImpl_IdentityManager_Wrapper: _PniIdentityKeyCheckerImpl_IdentityManager_Shim {
    private let identityManager: OWSIdentityManager

    init(_ identityManager: OWSIdentityManager) {
        self.identityManager = identityManager
    }

    func pniIdentityPublicKeyData(tx: DBReadTransaction) -> Data? {
        return identityManager.identityKeyPair(for: .pni, tx: tx)?.publicKey
    }
}

// MARK: ProfileFetcher

protocol _PniIdentityKeyCheckerImpl_ProfileFetcher_Shim {
    func fetchPniIdentityPublicKey(localPni: Pni) -> Promise<Data?>
}

class _PniIdentityKeyCheckerImpl_ProfileFetcher_Wrapper: _PniIdentityKeyCheckerImpl_ProfileFetcher_Shim {
    private let schedulers: Schedulers

    init(schedulers: Schedulers) {
        self.schedulers = schedulers
    }

    func fetchPniIdentityPublicKey(localPni: Pni) -> Promise<Data?> {
        let logger = PniIdentityKeyCheckerImpl.logger

        return ProfileFetcherJob.fetchProfilePromise(
            serviceId: localPni,
            mainAppOnly: true,
            ignoreThrottling: true,
            shouldUpdateStore: false
        ).map(on: schedulers.sync) { fetchedProfile -> Data in
            return fetchedProfile.profile.identityKey
        }.recover(on: schedulers.sync) { error throws -> Promise<Data?> in
            switch error {
            case ProfileFetchError.missing:
                logger.warn("Server does not have a profile for the given PNI.")
                return .value(nil)
            case ParamParser.ParseError.missingField("identityKey"):
                logger.warn("Server does not have a PNI identity key.")
                return .value(nil)
            case ProfileFetchError.notMainApp:
                throw OWSGenericError("Could not check remote identity key outside main app.")
            default:
                throw error
            }
        }
    }
}
