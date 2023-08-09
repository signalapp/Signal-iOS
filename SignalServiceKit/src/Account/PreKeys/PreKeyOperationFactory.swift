//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PreKeyOperationFactory {
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

    public func legacy_createPreKeysOperation(
        for identity: OWSIdentity,
        auth: ChatServiceAuth,
        didSucceed: @escaping () -> Void
    ) -> OWSOperation {
        var targets: PreKey.Operation.Target = [.oneTimePreKey, .signedPreKey]
        if FeatureFlags.enablePQXDH {
            targets.insert(target: .oneTimePqPreKey)
            targets.insert(target: .lastResortPqPreKey)
        }

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
        }
        if shouldRefreshOneTimePreKeys {
            targets.insert(target: .oneTimePreKey)
        }

        if FeatureFlags.enablePQXDH {
            targets.insert(target: .oneTimePqPreKey)
            if shouldRefreshSignedPreKeys {
                targets.insert(target: .lastResortPqPreKey)
            }
            if shouldRefreshOneTimePreKeys {
                targets.insert(target: .oneTimePqPreKey)
            }
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
        var targets: PreKey.Operation.Target = .signedPreKey
        if FeatureFlags.enablePQXDH {
            targets.insert(target: .lastResortPqPreKey)
        }

        return PreKeyOperation(
            action: .rotate(identity: identity, targets: targets),
            context: context,
            didSucceed: didSucceed
        )
    }

    public func createOrRotatePNIPreKeysOperation(
        didSucceed: @escaping () -> Void
    ) -> OWSOperation {
        var targets: PreKey.Operation.Target = [.oneTimePreKey, .signedPreKey]
        if FeatureFlags.enablePQXDH {
            targets.insert(target: .oneTimePqPreKey)
            targets.insert(target: .lastResortPqPreKey)
        }

        return PreKeyOperation(
            action: .createOrRotatePniKeys(targets: targets),
            context: context,
            didSucceed: didSucceed
        )
    }
}
