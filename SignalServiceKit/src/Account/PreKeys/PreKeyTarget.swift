//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum PreKey {
    static let logger = PrefixedLogger(prefix: "[PreKey]")
}

extension PreKey {

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
}
