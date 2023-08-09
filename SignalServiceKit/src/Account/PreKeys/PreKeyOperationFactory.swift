//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PreKeyOperationFactory {

    func createForRegistration(
        future: Future<RegistrationPreKeyUploadBundles>
    ) -> OWSOperation

    func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool,
        future: Future<Void>
    ) -> OWSOperation

    func rotateOneTimePreKeysForRegistration(
        identity: OWSIdentity,
        auth: ChatServiceAuth,
        future: Future<Void>,
        didSucceed: @escaping () -> Void
    ) -> OWSOperation

    func legacy_createPreKeysOperation(
        for identity: OWSIdentity,
        auth: ChatServiceAuth,
        didSucceed: @escaping () -> Void
    ) -> OWSOperation

    func refreshPreKeysOperation(
        for identity: OWSIdentity,
        shouldRefreshOneTimePreKeys: Bool,
        shouldRefreshSignedPreKeys: Bool,
        didSucceed: @escaping () -> Void
    ) -> OWSOperation

    func rotateSignedPreKeyOperation(
        for identity: OWSIdentity,
        didSucceed: @escaping () -> Void
    ) -> OWSOperation

    func createOrRotatePNIPreKeysOperation(
        didSucceed: @escaping () -> Void
    ) -> OWSOperation
}

public struct PreKeyOperationFactoryImpl: PreKeyOperationFactory {

    private let context: PreKeyTasks.Context
    init(context: PreKeyTasks.Context) {
        self.context = context
    }

    public func createForRegistration(
        future: Future<RegistrationPreKeyUploadBundles>
    ) -> OWSOperation {
        return PreKeyCreateForRegistrationOperation(
            dateProvider: context.dateProvider,
            db: context.db,
            identityManager: context.identityManager,
            protocolStoreManager: context.protocolStoreManager,
            schedulers: context.schedulers,
            future: future
        )
    }

    public func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool,
        future: Future<Void>
    ) -> OWSOperation {
        return PreKeyPersistAfterRegistrationOperation(
            bundles: bundles,
            uploadDidSucceed: uploadDidSucceed,
            dateProvider: context.dateProvider,
            db: context.db,
            protocolStoreManager: context.protocolStoreManager,
            schedulers: context.schedulers,
            future: future
        )
    }

    public func rotateOneTimePreKeysForRegistration(
        identity: OWSIdentity,
        auth: ChatServiceAuth,
        future: Future<Void>,
        didSucceed: @escaping () -> Void
    ) -> OWSOperation {
        return PreKeyOperation(
            action: .createOneTimePreKeys(identity: identity),
            auth: auth,
            context: context,
            future: future,
            didSucceed: didSucceed
        )
    }

    public func legacy_createPreKeysOperation(
        for identity: OWSIdentity,
        auth: ChatServiceAuth,
        didSucceed: @escaping () -> Void
    ) -> OWSOperation {
        let targets: PreKey.Operation.Target = [
            .oneTimePreKey,
            .signedPreKey,
            .oneTimePqPreKey,
            .lastResortPqPreKey
        ]

        return PreKeyOperation(
            action: .legacy_create(identity: identity, targets: targets),
            auth: auth,
            context: context,
            didSucceed: didSucceed
        )
    }

    public func refreshPreKeysOperation(
        for identity: OWSIdentity,
        shouldRefreshOneTimePreKeys: Bool,
        shouldRefreshSignedPreKeys: Bool,
        didSucceed: @escaping () -> Void
    ) -> OWSOperation {
        var targets: PreKey.Operation.Target = []
        if shouldRefreshSignedPreKeys {
            targets.insert(.signedPreKey)
            targets.insert(target: .lastResortPqPreKey)
        }
        if shouldRefreshOneTimePreKeys {
            targets.insert(target: .oneTimePreKey)
            targets.insert(target: .oneTimePqPreKey)
        }

        return PreKeyOperation(
            action: .refresh(identity: identity, targets: targets),
            context: context,
            didSucceed: didSucceed
        )
    }

    public func rotateSignedPreKeyOperation(
        for identity: OWSIdentity,
        didSucceed: @escaping () -> Void
    ) -> OWSOperation {
        let targets: PreKey.Operation.Target = [.signedPreKey, .lastResortPqPreKey]

        return PreKeyOperation(
            action: .rotate(identity: identity, targets: targets),
            context: context,
            didSucceed: didSucceed
        )
    }

    public func createOrRotatePNIPreKeysOperation(
        didSucceed: @escaping () -> Void
    ) -> OWSOperation {
        let targets: PreKey.Operation.Target = [
            .oneTimePreKey,
            .signedPreKey,
            .oneTimePqPreKey,
            .lastResortPqPreKey
        ]

        return PreKeyOperation(
            action: .createOrRotatePniKeys(targets: targets),
            context: context,
            didSucceed: didSucceed
        )
    }
}
