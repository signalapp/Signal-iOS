//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - Public Structs

public enum PreKeyTasks {

    public struct Context {
        let accountManager: PreKey.Operation.Shims.AccountManager
        let dateProvider: DateProvider
        let db: DB
        let identityManager: PreKey.Operation.Shims.IdentityManager
        let messageProcessor: PreKey.Operation.Shims.MessageProcessor
        let protocolStoreManager: SignalProtocolStoreManager
        let schedulers: Schedulers
        let serviceClient: AccountServiceClient
    }
}

// MARK: - Internal Structs

extension PreKeyTasks {
    enum Constants {
        // We generate 100 one-time prekeys at a time.
        // Replenish whenever 10 or less remain
        internal static let EphemeralPreKeysMinimumCount: UInt = 10

        internal static let PqPreKeysMinimumCount: UInt = 10

        // Signed prekeys should be rotated every at least every 2 days
        internal static let SignedPreKeyRotationTime: TimeInterval = 2 * kDayInterval

        internal static let LastResortPqPreKeyRotationTime: TimeInterval = 2 * kDayInterval
    }

    public enum Error: Swift.Error {
        case noIdentityKey
        case notRegistered
        case cancelled
    }
}

extension PreKeyTasks {

    public class PreKeyTask {
        private let context: Context
        private let auth: ChatServiceAuth

        private let action: PreKey.Operation.Action

        private let preKeyStore: SignalPreKeyStore
        private let signedPreKeyStore: SignalSignedPreKeyStore
        private let kyberPreKeyStore: SignalKyberPreKeyStore

        public init(
            action: PreKey.Operation.Action,
            auth: ChatServiceAuth,
            context: Context
        ) {
            self.auth = auth
            self.context = context

            let protocolStore = context.protocolStoreManager.signalProtocolStore(for: action.identity)

            self.preKeyStore = protocolStore.preKeyStore
            self.signedPreKeyStore = protocolStore.signedPreKeyStore
            self.kyberPreKeyStore = protocolStore.kyberPreKeyStore

            self.action = action
        }

        /// PreKeyTask is broken down into the following steps
        /// 1. Fetch the identity key.  If this is a create operation, create the key, otherwise error if missing
        /// 2. If registered and not a create operation, check that message processing is idle before continuing
        /// 3. Check the server for the number of remaining PreKeys (skip on create/force refresh)
        /// 4. Run any logic to determine what requested operations are really necessary
        /// 5. Generate the necessary keys for the resulting operations
        /// 6. Upload these new keys to the server
        /// 7. Store the new keys and run any cleanup logic
        public func runPreKeyTask() -> Promise<Void> {

            let globalQueue = { self.context.schedulers.global() }

            let bundlePromise: Promise<PreKeyUploadBundle>

            let generateContext = Generate.Context(
                db: context.db,
                identityManager: context.identityManager,
                scheduler: globalQueue(),
                preKeyStore: self.preKeyStore,
                signedPreKeyStore: self.signedPreKeyStore,
                kyberPreKeyStore: self.kyberPreKeyStore
            )

            switch action {
            case .refresh(_, let targets):
                bundlePromise = GenerateForRefresh
                    .init(
                        dateProvider: context.dateProvider,
                        context: generateContext,
                        messageProcessor: context.messageProcessor,
                        serviceClient: context.serviceClient
                    )
                    .runTask(
                        identity: action.identity,
                        targets: targets
                    )
                    .map(on: SyncScheduler()) { $0 }
            case .rotate(_, let targets):
                bundlePromise = GenerateForRotation
                    .init(
                        context: generateContext,
                        messageProcessor: context.messageProcessor
                    )
                    .runTask(
                        identity: action.identity,
                        targets: targets
                    )
                    .map(on: SyncScheduler()) { $0 }
            case .createOneTimePreKeys:
                bundlePromise = CreateOneTimePreKeys(context: generateContext)
                    .runTask(identity: action.identity)
                    .map(on: SyncScheduler()) { $0 }
            case .createOrRotatePniKeys(let targets):
                bundlePromise = GenerateForPNIRotation
                    .init(
                        context: generateContext,
                        messageProcessor: context.messageProcessor
                    )
                    .runTask(targets: targets)
                    .map(on: SyncScheduler()) { $0 }
            case .legacy_create(_, let targets):
                bundlePromise = Legacy_Generate
                    .init(
                        accountManager: context.accountManager,
                        context: generateContext,
                        messageProcessor: context.messageProcessor
                    )
                    .runTask(
                        identity: action.identity,
                        targets: targets
                    ).map(on: SyncScheduler()) { $0 }
            }

            return bundlePromise.then(on: globalQueue()) { (bundle: PreKeyUploadBundle) -> Promise<Void> in
                return Upload(serviceClient: self.context.serviceClient)
                    .runTask(bundle: bundle, auth: self.auth)
                    .map(on: globalQueue()) {
                        try PersistSuccesfulUpload(
                            dateProvider: self.context.dateProvider,
                            db: self.context.db,
                            preKeyStore: self.preKeyStore,
                            signedPreKeyStore: self.signedPreKeyStore,
                            kyberPreKeyStore: self.kyberPreKeyStore
                        ).runTask(bundle: bundle)
                    }
                    .recover(on: globalQueue()) { error in
                        IncrementFailureCount(
                            db: self.context.db,
                            signedPreKeyStore: self.signedPreKeyStore
                        ).runTask(bundle: bundle, error: error)
                        return Promise<Void>(error: error)
                    }
                }
        }
    }
}

fileprivate extension PreKey.Operation.Action {

    var identity: OWSIdentity {
        switch self {
        case .refresh(let identity, _), .rotate(let identity, _), .legacy_create(let identity, _), .createOneTimePreKeys(let identity):
            return identity
        case .createOrRotatePniKeys:
            return .pni
        }
    }
}
