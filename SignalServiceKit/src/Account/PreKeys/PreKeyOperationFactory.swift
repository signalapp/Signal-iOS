//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PreKeyOperationFactory {
    func rotateSignedPreKeyOperation(for identity: OWSIdentity, shouldSkipIfRecent: Bool) -> OWSOperation
    func createPreKeysOperation(for identity: OWSIdentity, auth: ChatServiceAuth) -> OWSOperation
    func refreshPreKeysOperation(for identity: OWSIdentity, shouldRefreshSignedPreKey: Bool) -> OWSOperation
}

public struct PreKeyOperationFactoryImpl: PreKeyOperationFactory {

    private let context: PreKeyTask.Context
    init(context: PreKeyTask.Context) {
        self.context = context
    }

    public func rotateSignedPreKeyOperation(for identity: OWSIdentity, shouldSkipIfRecent: Bool) -> OWSOperation {

        var targets: PreKey.Operation.Target = .signedPreKey
        if FeatureFlags.enablePQXDH {
            targets.insert(target: .lastResortPqPreKey)
        }

        return PreKeyOperation(
            for: identity,
            action: .refresh(targets, forceRefresh: !shouldSkipIfRecent),
            context: context
        )
    }

    public func createPreKeysOperation(for identity: OWSIdentity, auth: ChatServiceAuth) -> OWSOperation {
        var targets: PreKey.Operation.Target = [.oneTimePreKey, .signedPreKey]
        if FeatureFlags.enablePQXDH {
            targets.insert(target: .oneTimePqPreKey)
            targets.insert(target: .lastResortPqPreKey)
        }

        return PreKeyOperation(
            for: identity,
            action: .create(targets),
            auth: auth,
            context: context
        )
    }

    public func refreshPreKeysOperation(for identity: OWSIdentity, shouldRefreshSignedPreKey: Bool) -> OWSOperation {
        var targets: PreKey.Operation.Target = .oneTimePreKey
        if shouldRefreshSignedPreKey {
            targets.insert(.signedPreKey)
        }

        if FeatureFlags.enablePQXDH {
            targets.insert(target: .oneTimePqPreKey)
            if shouldRefreshSignedPreKey {
                targets.insert(target: .lastResortPqPreKey)
            }
        }

        return PreKeyOperation(
            for: identity,
            action: .refresh(targets, forceRefresh: false),
            context: context
        )
    }
}
