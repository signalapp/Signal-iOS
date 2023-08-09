//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension PreKeyTasks {

    internal enum Generate {
        internal struct Context {
            let db: DB
            let identityManager: PreKey.Operation.Shims.IdentityManager
            let scheduler: Scheduler

            let preKeyStore: SignalPreKeyStore
            let signedPreKeyStore: SignalSignedPreKeyStore
            let kyberPreKeyStore: SignalKyberPreKeyStore
        }
    }

    public class GenerateBase {
        fileprivate let context: Generate.Context

        fileprivate init(context: Generate.Context) {
            self.context = context
        }

        fileprivate func getOrCreateIdentityKeyPair(identity: OWSIdentity) -> ECKeyPair {
            let existingKeyPair = context.db.read { tx in
                return context.identityManager.identityKeyPair(for: identity, tx: tx)
            }
            if let identityKeyPair = existingKeyPair {
                return identityKeyPair
            }
            let identityKeyPair = context.identityManager.generateNewIdentityKeyPair()
            context.db.write { tx in
                context.identityManager.store(
                    keyPair: identityKeyPair,
                    for: identity,
                    tx: tx
                )
            }
            return identityKeyPair
        }

        fileprivate func createPartialBundle(
            identity: OWSIdentity,
            identityKeyPair: ECKeyPair,
            targets: PreKey.Operation.Target
        ) throws -> PartialPreKeyUploadBundle {
            // Map the keys to the requested operation.  Create the necessary keys and
            // pass them along to be uploaded to the service/stored/accepted
            var signedPreKey: SignedPreKeyRecord?
            var preKeyRecords: [PreKeyRecord]?
            var lastResortPreKey: KyberPreKeyRecord?
            var pqPreKeyRecords: [KyberPreKeyRecord]?
            try context.db.write { tx in
                try targets.targets.forEach { target in
                    switch target {
                    case .oneTimePreKey:
                        preKeyRecords = context.preKeyStore.generatePreKeyRecords(tx: tx)
                    case .signedPreKey:
                        signedPreKey = context.signedPreKeyStore.generateRandomSignedRecord()
                    case .oneTimePqPreKey:
                        pqPreKeyRecords = try context.kyberPreKeyStore.generateKyberPreKeyRecords(
                            count: 100,
                            signedBy: identityKeyPair,
                            tx: tx
                        )
                    case .lastResortPqPreKey:
                        lastResortPreKey = try context.kyberPreKeyStore.generateLastResortKyberPreKey(
                            signedBy: identityKeyPair,
                            tx: tx
                        )
                    }
                }
            }
            return PartialPreKeyUploadBundle(
                identity: identity,
                identityKeyPair: identityKeyPair,
                signedPreKey: signedPreKey,
                preKeyRecords: preKeyRecords,
                lastResortPreKey: lastResortPreKey,
                pqPreKeyRecords: pqPreKeyRecords
            )
        }
    }

    /// When we register, we create a new identity key and other keys. So this variant:
    /// CAN create a new identity key (or uses any existing one)
    /// ALWAYS changes the targeted keys (regardless of current key state)
    internal class GenerateForRegistration: GenerateBase {

        internal override init(context: Generate.Context) {
            super.init(context: context)
        }

        func runTask(identity: OWSIdentity) throws -> RegistrationPreKeyUploadBundle {
            let identityKeyPair = getOrCreateIdentityKeyPair(identity: identity)
            return try context.db.write { tx in
                return RegistrationPreKeyUploadBundle(
                    identity: identity,
                    identityKeyPair: identityKeyPair,
                    signedPreKey: context.signedPreKeyStore.generateRandomSignedRecord(),
                    lastResortPreKey: try context.kyberPreKeyStore.generateLastResortKyberPreKey(
                        signedBy: identityKeyPair,
                        tx: tx
                    )
                )
            }
        }
    }

    internal class CreateOneTimePreKeys: GenerateBase {
        internal override init(context: Generate.Context) {
            super.init(context: context)
        }

        func runTask(identity: OWSIdentity) -> Promise<PartialPreKeyUploadBundle> {
            // Get the identity key
            guard let identityKeyPair: ECKeyPair = context.db.read(block: { tx in
                context.identityManager.identityKeyPair(for: identity, tx: tx)
            }) else {
                Logger.warn("cannot refresh \(identity) pre-keys; missing identity key")
                return .init(error: Error.noIdentityKey)
            }
            do {
                return .value(try self.createPartialBundle(
                    identity: identity,
                    identityKeyPair: identityKeyPair,
                    targets: [.oneTimePreKey, .oneTimePqPreKey]
                ))
            } catch let error {
                return .init(error: error)
            }
        }
    }

    // TODO: remove this once legacy registration usage is cleaned up.
    /// When we register, we create a new identity key and other keys. So this variant:
    /// CAN create a new identity key (or uses any existing one)
    /// ALWAYS changes the targeted keys (regardless of current key state)
    internal class Legacy_Generate: GenerateBase {

        private let accountManager: PreKey.Operation.Shims.AccountManager
        private let messageProcessor: PreKey.Operation.Shims.MessageProcessor

        internal init(
            accountManager: PreKey.Operation.Shims.AccountManager,
            context: Generate.Context,
            messageProcessor: PreKey.Operation.Shims.MessageProcessor
        ) {
            self.accountManager = accountManager
            self.messageProcessor = messageProcessor
            super.init(context: context)
        }

        func runTask(
            identity: OWSIdentity,
            targets: PreKey.Operation.Target
        ) -> Promise<PartialPreKeyUploadBundle> {
            let messageProcessingPromise: Promise<Void>

            // Legacy code was reliant on this check. To be removed soon.
            if context.db.read(block: accountManager.isRegisteredAndReady(tx:)) {
                messageProcessingPromise = messageProcessor.fetchingAndProcessingCompletePromise()
            } else {
                messageProcessingPromise = .value(())
            }
            let identityKeyPair = getOrCreateIdentityKeyPair(identity: identity)
            return messageProcessingPromise
                .map(on: context.scheduler) {
                    try self.createPartialBundle(
                        identity: identity,
                        identityKeyPair: identityKeyPair,
                        targets: targets
                    )
                }
        }
    }

    /// When we create our PNI (as part of hello world) we are allowed to
    /// create a new identity key. So this variant:
    /// CAN create a new identity key (or uses any existing one)
    /// ALWAYS changes the targeted keys (regardless of current key state)
    internal class GenerateForPNIRotation: GenerateBase {

        private let messageProcessor: PreKey.Operation.Shims.MessageProcessor

        internal init(
            context: Generate.Context,
            messageProcessor: PreKey.Operation.Shims.MessageProcessor
        ) {
            self.messageProcessor = messageProcessor
            super.init(context: context)
        }

        func runTask(targets: PreKey.Operation.Target) -> Promise<PartialPreKeyUploadBundle> {
            let identityKeyPair = getOrCreateIdentityKeyPair(identity: .pni)
            return messageProcessor.fetchingAndProcessingCompletePromise()
                .map(on: context.scheduler) {
                    try self.createPartialBundle(
                        identity: .pni,
                        identityKeyPair: identityKeyPair,
                        targets: targets
                    )
                }
        }
    }

    /// When we rotate keys (e.g. due to prior prekey failure) we should never change
    /// our identity key. So this variant:
    /// CANNOT create a new identity key
    /// ALWAYS changes the targeted keys (regardless of current key state)
    internal class GenerateForRotation: GenerateBase {

        private let messageProcessor: PreKey.Operation.Shims.MessageProcessor

        internal init(
            context: Generate.Context,
            messageProcessor: PreKey.Operation.Shims.MessageProcessor
        ) {
            self.messageProcessor = messageProcessor
            super.init(context: context)
        }

        func runTask(
            identity: OWSIdentity,
            targets: PreKey.Operation.Target
        ) -> Promise<PartialPreKeyUploadBundle> {
            // Get the identity key
            guard let identityKeyPair: ECKeyPair = context.db.read(block: { tx in
                context.identityManager.identityKeyPair(for: identity, tx: tx)
            }) else {
                Logger.warn("cannot refresh \(identity) pre-keys; missing identity key")
                return .init(error: Error.noIdentityKey)
            }
            return messageProcessor.fetchingAndProcessingCompletePromise()
                .map(on: context.scheduler) {
                    try self.createPartialBundle(
                        identity: identity,
                        identityKeyPair: identityKeyPair,
                        targets: targets
                    )
                }
        }
    }

    /// When we create refresh keys (happens periodically) we should never change
    /// our identity key, but may rotate other keys depending on expiration. So this variant:
    /// CANNOT create a new identity key
    /// SOMETIMES changes the targeted keys (dependent on current key state)
    /// In other words, this variant can potential no-op.
    internal class GenerateForRefresh: GenerateBase {

        private let dateProvider: DateProvider
        private let messageProcessor: PreKey.Operation.Shims.MessageProcessor
        private let serviceClient: AccountServiceClient

        internal init(
            dateProvider: @escaping DateProvider,
            context: Generate.Context,
            messageProcessor: PreKey.Operation.Shims.MessageProcessor,
            serviceClient: AccountServiceClient
        ) {
            self.dateProvider = dateProvider
            self.messageProcessor = messageProcessor
            self.serviceClient = serviceClient
            super.init(context: context)
        }

        func runTask(
            identity: OWSIdentity,
            targets unfilteredTargets: PreKey.Operation.Target
        ) -> Promise<PartialPreKeyUploadBundle> {
            // Get the identity key
            guard let identityKeyPair: ECKeyPair = context.db.read(block: { tx in
                context.identityManager.identityKeyPair(for: identity, tx: tx)
            }) else {
                Logger.warn("cannot refresh \(identity) pre-keys; missing identity key")
                return .init(error: Error.noIdentityKey)
            }

            return messageProcessor.fetchingAndProcessingCompletePromise()
                .then(on: context.scheduler) { () -> Promise<PreKey.Operation.Target> in
                    return self.serviceClient.getPreKeysCount(for: identity)
                        .map(on: self.context.scheduler) { (ecCount: Int, pqCount: Int) -> PreKey.Operation.Target in
                            return self.filterToNecessaryTargets(
                                identity: identity,
                                unfilteredTargets: unfilteredTargets,
                                ecPreKeyRecordCount: ecCount,
                                pqPreKeyRecordCount: pqCount
                            )
                        }
                }.map(on: context.scheduler) { targets in
                    return try self.createPartialBundle(
                        identity: identity,
                        identityKeyPair: identityKeyPair,
                        targets: targets
                    )
                }
        }

        private func filterToNecessaryTargets(
            identity: OWSIdentity,
            unfilteredTargets: PreKey.Operation.Target,
            ecPreKeyRecordCount: Int,
            pqPreKeyRecordCount: Int
        ) -> PreKey.Operation.Target {
            let (currentSignedPreKey, currentLastResortPqPreKey) = context.db.read { tx in
                let signedPreKey = context.signedPreKeyStore.currentSignedPreKey(tx: tx)
                let lastResortKey = context.kyberPreKeyStore.getLastResortKyberPreKey(tx: tx)
                return (signedPreKey, lastResortKey)
            }

            // Take the gathered PreKeyState information and run it through
            // logic to determine what really needs to be updated.
            return unfilteredTargets.targets.reduce(into: []) { value, target in
                switch target {
                case .oneTimePreKey:
                    if ecPreKeyRecordCount < Constants.EphemeralPreKeysMinimumCount {
                        value.insert(target: target)
                    } else {
                        Logger.info("Available \(identity) keys sufficient: \(ecPreKeyRecordCount)")
                    }
                case .oneTimePqPreKey:
                    if pqPreKeyRecordCount < Constants.PqPreKeysMinimumCount {
                        value.insert(target: target)
                    } else {
                        Logger.info("Available \(identity) PQ keys sufficient: \(pqPreKeyRecordCount)")
                    }
                case .signedPreKey:
                    if
                        let signedPreKey = currentSignedPreKey,
                        case let currentDate = self.dateProvider(),
                        case let generatedDate = signedPreKey.generatedAt,
                        currentDate.timeIntervalSince(generatedDate) < Constants.SignedPreKeyRotationTime
                    {
                        Logger.info("Available \(identity) signed PreKey sufficient: \(signedPreKey.generatedAt)")
                    } else {
                        value.insert(target: target)
                    }
                case .lastResortPqPreKey:
                    if
                        let lastResortPreKey = currentLastResortPqPreKey,
                        case let currentDate = self.dateProvider(),
                        case let generatedDate = lastResortPreKey.generatedAt,
                        currentDate.timeIntervalSince(generatedDate) < Constants.LastResortPqPreKeyRotationTime
                    {
                        Logger.info("Available \(identity) last resort PreKey sufficient: \(lastResortPreKey.generatedAt)")
                    } else {
                        value.insert(target: target)
                    }
                }
            }
        }
    }
}
