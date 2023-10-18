//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum PreKey {
    static let logger = PrefixedLogger(prefix: "[PreKey]")
}

extension PreKey {
    public enum Operation {

        // Needs to remain in sync with 'Target' below
        public enum SingleTarget: Int, Equatable, CaseIterable {
            case signedPreKey = 1
            case oneTimePreKey = 2
            case oneTimePqPreKey = 4
            case lastResortPqPreKey = 8
            // next raw value: 16 (1 << 4)

            public var asTarget: Target {
                return Target(rawValue: rawValue)
            }
        }

        public struct Target: OptionSet {
            public let rawValue: Int
            public init(rawValue: Int) {
                self.rawValue = rawValue
            }

            static let signedPreKey  = Target(rawValue: SingleTarget.signedPreKey.rawValue)
            static let oneTimePreKey = Target(rawValue: SingleTarget.oneTimePreKey.rawValue)
            static let oneTimePqPreKey = Target(rawValue: SingleTarget.oneTimePqPreKey.rawValue)
            static let lastResortPqPreKey = Target(rawValue: SingleTarget.lastResortPqPreKey.rawValue)

            public mutating func insert(target: SingleTarget) {
                self.insert(target.asTarget)
            }

            public func contains(target: SingleTarget) -> Bool {
                self.contains(target.asTarget)
            }

            public var targets: [SingleTarget] {
                return SingleTarget.allCases.compactMap {
                    return self.contains(target: $0) ? $0 : nil
                }
            }

            static var all: Target {
                SingleTarget.allCases.reduce(into: []) { $0.insert(target: $1) }
            }
        }

        public enum Action {

            // Update the target prekeys if necessary.
            // Never creates an identity key; fails if none present.
            case refresh(identity: OWSIdentity, targets: Operation.Target)

            // Update the target prekeys, regardless of their current state.
            // Never creates an identity key; fails if none present.
            case rotate(identity: OWSIdentity, targets: Operation.Target)

            // Create all one time prekeys. Used during registration.
            // Does not check for existing prekeys, or wait for message
            // processing, as it is assumed these are the first prekeys.
            case createOneTimePreKeys(identity: OWSIdentity)

            // Create pni keys, rotating if they already exist.
            // May also create the pni identity key if it didn't exist;
            // if it did the existing key will be reused.
            case createOrRotatePniKeys(targets: Operation.Target)

            // Update the targeted prekeys, regardless of their current state.
            // May also create the identity key if it didn't exist;
            // if it did the existing key will be reused.
            // TODO: remove this mode, everything that was create should
            // either use new registration methods or pni methods.
            case legacy_create(identity: OWSIdentity, targets: Operation.Target)
        }
    }
}

public class PreKeyOperation: OWSOperation {

    public enum Error: Swift.Error {
        case cancelled
    }

    private let context: PreKeyTasks.Context
    private let preKeyTask: PreKeyTasks.PreKeyTask
    private let future: Future<Void>?
    private let _didSucceed: () -> Void

    public init(
        action: PreKey.Operation.Action,
        auth: ChatServiceAuth = .implicit(),
        context: PreKeyTasks.Context,
        future: Future<Void>? = nil,
        didSucceed: @escaping () -> Void
    ) {
        self.context = context
        self.future = future
        self._didSucceed = didSucceed
        self.preKeyTask = PreKeyTasks.PreKeyTask(
            action: action,
            auth: auth,
            context: context
        )
    }

    public override func run() {
        PreKey.logger.info("")
        guard !isCancelled else {
            PreKey.logger.info("Operation cancelled")
            self.future?.reject(Error.cancelled)
            return
        }
        firstly(on: context.schedulers.global()) {
            self.preKeyTask.runPreKeyTask()
        } .done(on: self.context.schedulers.global()) {
            self.future?.resolve()
            self.reportSuccess()
        }.catch(on: self.context.schedulers.global()) { error in
            self.future?.reject(error)
            self.reportError(withUndefinedRetry: error)
        }
    }

    public override func didSucceed() {
        super.didSucceed()
        _didSucceed()
    }
}

internal class PreKeyCreateForRegistrationOperation: OWSOperation {
    private let scheduler: Scheduler
    private let aciGenerateTask: PreKeyTasks.GenerateForRegistration
    private let pniGenerateTask: PreKeyTasks.GenerateForRegistration
    private let aciPersistTask: PreKeyTasks.PersistPriorToUpload
    private let pniPersistTask: PreKeyTasks.PersistPriorToUpload
    private let future: Future<RegistrationPreKeyUploadBundles>

    public init(
        dateProvider: @escaping DateProvider,
        db: DB,
        identityManager: PreKey.Operation.Shims.IdentityManager,
        protocolStoreManager: SignalProtocolStoreManager,
        schedulers: Schedulers,
        future: Future<RegistrationPreKeyUploadBundles>
    ) {
        let scheduler = schedulers.global()
        self.scheduler = scheduler
        self.future = future

        func generateContext(for identity: OWSIdentity) -> PreKeyTasks.Generate.Context {
            let protocolStore = protocolStoreManager.signalProtocolStore(for: identity)
            return .init(
                db: db,
                identityManager: identityManager,
                scheduler: scheduler,
                preKeyStore: protocolStore.preKeyStore,
                signedPreKeyStore: protocolStore.signedPreKeyStore,
                kyberPreKeyStore: protocolStore.kyberPreKeyStore
            )
        }

        let aciContext = generateContext(for: .aci)
        self.aciGenerateTask = PreKeyTasks.GenerateForRegistration(context: aciContext)
        let pniContext = generateContext(for: .pni)
        self.pniGenerateTask = PreKeyTasks.GenerateForRegistration(context: pniContext)
        self.aciPersistTask = PreKeyTasks.PersistPriorToUpload(
            dateProvider: dateProvider,
            db: db,
            preKeyStore: aciContext.preKeyStore,
            signedPreKeyStore: aciContext.signedPreKeyStore,
            kyberPreKeyStore: aciContext.kyberPreKeyStore
        )
        self.pniPersistTask = PreKeyTasks.PersistPriorToUpload(
            dateProvider: dateProvider,
            db: db,
            preKeyStore: pniContext.preKeyStore,
            signedPreKeyStore: pniContext.signedPreKeyStore,
            kyberPreKeyStore: pniContext.kyberPreKeyStore
        )
    }

    public override func run() {
        PreKey.logger.info("Create for registration")
        firstly(on: scheduler) { () -> RegistrationPreKeyUploadBundles in
            let aciBundle = try self.aciGenerateTask.runTask(identity: .aci)
            try self.aciPersistTask.runTask(bundle: aciBundle)
            let pniBundle = try self.pniGenerateTask.runTask(identity: .pni)
            try self.pniPersistTask.runTask(bundle: pniBundle)
            return .init(aci: aciBundle, pni: pniBundle)
        }.done(on: scheduler) {
            self.future.resolve($0)
            self.reportSuccess()
        }.catch(on: scheduler) { error in
            self.future.reject(error)
            self.reportError(withUndefinedRetry: error)
        }
    }
}

internal class PreKeyCreateForProvisioningOperation: OWSOperation {
    private let scheduler: Scheduler

    private let aciIdentityKeyPair: ECKeyPair
    private let pniIdentityKeyPair: ECKeyPair
    private let aciGenerateTask: PreKeyTasks.GenerateForProvisioning
    private let pniGenerateTask: PreKeyTasks.GenerateForProvisioning
    private let aciPersistTask: PreKeyTasks.PersistPriorToUpload
    private let pniPersistTask: PreKeyTasks.PersistPriorToUpload
    private let future: Future<RegistrationPreKeyUploadBundles>

    public init(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair,
        dateProvider: @escaping DateProvider,
        db: DB,
        identityManager: PreKey.Operation.Shims.IdentityManager,
        protocolStoreManager: SignalProtocolStoreManager,
        schedulers: Schedulers,
        future: Future<RegistrationPreKeyUploadBundles>
    ) {
        self.aciIdentityKeyPair = aciIdentityKeyPair
        self.pniIdentityKeyPair = pniIdentityKeyPair
        let scheduler = schedulers.global()
        self.scheduler = scheduler
        self.future = future

        func generateContext(for identity: OWSIdentity) -> PreKeyTasks.Generate.Context {
            let protocolStore = protocolStoreManager.signalProtocolStore(for: identity)
            return .init(
                db: db,
                identityManager: identityManager,
                scheduler: scheduler,
                preKeyStore: protocolStore.preKeyStore,
                signedPreKeyStore: protocolStore.signedPreKeyStore,
                kyberPreKeyStore: protocolStore.kyberPreKeyStore
            )
        }

        let aciContext = generateContext(for: .aci)
        self.aciGenerateTask = PreKeyTasks.GenerateForProvisioning(context: aciContext)
        let pniContext = generateContext(for: .pni)
        self.pniGenerateTask = PreKeyTasks.GenerateForProvisioning(context: pniContext)
        self.aciPersistTask = PreKeyTasks.PersistPriorToUpload(
            dateProvider: dateProvider,
            db: db,
            preKeyStore: aciContext.preKeyStore,
            signedPreKeyStore: aciContext.signedPreKeyStore,
            kyberPreKeyStore: aciContext.kyberPreKeyStore
        )
        self.pniPersistTask = PreKeyTasks.PersistPriorToUpload(
            dateProvider: dateProvider,
            db: db,
            preKeyStore: pniContext.preKeyStore,
            signedPreKeyStore: pniContext.signedPreKeyStore,
            kyberPreKeyStore: pniContext.kyberPreKeyStore
        )
    }

    public override func run() {
        PreKey.logger.info("Create for provisioning")
        firstly(on: scheduler) { () -> RegistrationPreKeyUploadBundles in
            let aciBundle = try self.aciGenerateTask.runTask(identity: .aci, identityKeyPair: self.aciIdentityKeyPair)
            try self.aciPersistTask.runTask(bundle: aciBundle)
            let pniBundle = try self.pniGenerateTask.runTask(identity: .pni, identityKeyPair: self.pniIdentityKeyPair)
            try self.pniPersistTask.runTask(bundle: pniBundle)
            return .init(aci: aciBundle, pni: pniBundle)
        }.done(on: scheduler) {
            self.future.resolve($0)
            self.reportSuccess()
        }.catch(on: scheduler) { error in
            self.future.reject(error)
            self.reportError(withUndefinedRetry: error)
        }
    }
}

internal class PreKeyPersistAfterRegistrationOperation: OWSOperation {
    private let bundles: RegistrationPreKeyUploadBundles
    private let uploadDidSucceed: Bool
    private let scheduler: Scheduler
    private let aciPersistTask: PreKeyTasks.PersistAfterRegistration
    private let pniPersistTask: PreKeyTasks.PersistAfterRegistration
    private let future: Future<Void>

    public init(
        bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool,
        dateProvider: @escaping DateProvider,
        db: DB,
        protocolStoreManager: SignalProtocolStoreManager,
        schedulers: Schedulers,
        future: Future<Void>
    ) {
        self.bundles = bundles
        self.uploadDidSucceed = uploadDidSucceed
        let scheduler = schedulers.global()
        self.scheduler = scheduler
        self.future = future

        let aciProtocolStore = protocolStoreManager.signalProtocolStore(for: .aci)
        let pniProtocolStore = protocolStoreManager.signalProtocolStore(for: .pni)
        self.aciPersistTask = PreKeyTasks.PersistAfterRegistration(
            dateProvider: dateProvider,
            db: db,
            preKeyStore: aciProtocolStore.preKeyStore,
            signedPreKeyStore: aciProtocolStore.signedPreKeyStore,
            kyberPreKeyStore: aciProtocolStore.kyberPreKeyStore
        )
        self.pniPersistTask = PreKeyTasks.PersistAfterRegistration(
            dateProvider: dateProvider,
            db: db,
            preKeyStore: pniProtocolStore.preKeyStore,
            signedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            kyberPreKeyStore: pniProtocolStore.kyberPreKeyStore
        )
    }

    public override func run() {
        PreKey.logger.info("Persist after provisioning")
        firstly(on: scheduler) {
            try self.aciPersistTask.runTask(bundle: self.bundles.aci, uploadDidSucceed: self.uploadDidSucceed)
            try self.pniPersistTask.runTask(bundle: self.bundles.pni, uploadDidSucceed: self.uploadDidSucceed)
        }.done(on: scheduler) {
            self.future.resolve(())
            self.reportSuccess()
        }.catch(on: scheduler) { error in
            self.future.reject(error)
            self.reportError(withUndefinedRetry: error)
        }
    }
}
