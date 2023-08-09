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

            // Update the target prekeys if necessary.
            // Never creates an identity key; fails if none present.
            case refresh(identity: OWSIdentity, targets: Operation.Target)

            // Update the target prekeys, regardless of their current state.
            // Never creates an identity key; fails if none present.
            case rotate(identity: OWSIdentity, targets: Operation.Target)

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
    private let context: PreKeyTasks.Context
    private let preKeyTask: PreKeyTasks.PreKeyTask
    private let _didSucceed: () -> Void

    public init(
        action: PreKey.Operation.Action,
        auth: ChatServiceAuth = .implicit(),
        context: PreKeyTasks.Context,
        didSucceed: @escaping () -> Void
    ) {
        self.context = context
        self._didSucceed = didSucceed
        self.preKeyTask = PreKeyTasks.PreKeyTask(
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
        _didSucceed()
    }
}
