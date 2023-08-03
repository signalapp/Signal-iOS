//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum PreKey {}

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

            // Update the target prekeys if necessary. Passing in
            // `forceRefresh: true` will have the effect of rotating
            // all the target keys with new ones.
            case refresh(Operation.Target, forceRefresh: Bool)

            // Create is essentially the same as a force refresh, but allows the
            // task to create an identity key if missing.
            case create(Operation.Target)
        }
    }
}

public class PreKeyOperation: OWSOperation {
    private let context: PreKeyTask.Context
    private let preKeyTask: PreKeyTask

    public init(
        for identity: OWSIdentity,
        action: PreKey.Operation.Action,
        auth: ChatServiceAuth = .implicit(),
        context: PreKeyTask.Context
    ) {
        self.context = context
        self.preKeyTask = PreKeyTask(
            for: identity,
            action: action,
            auth: auth,
            context: context
        )
    }

    public override func run() {
        firstly(on: context.schedulers.global()) {
            self.preKeyTask.runPreKeyTask()
        } .done(on: self.context.schedulers.global()) {
            self.reportSuccess()
        }.catch(on: self.context.schedulers.global()) { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    public override func didSucceed() {
        super.didSucceed()
        DependenciesBridge.shared.preKeyManager.refreshPreKeysDidSucceed()
    }
}
