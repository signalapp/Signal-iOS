//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Needs to remain in sync with 'PreKeyTargets' below
public enum PreKeyTarget: Int, Equatable, CaseIterable {
    case signedPreKey = 1
    case oneTimePreKey = 2
    case oneTimePqPreKey = 4
    case lastResortPqPreKey = 8
    // next raw value: 16 (1 << 4)

    fileprivate var asTargets: PreKeyTargets {
        return PreKeyTargets(rawValue: rawValue)
    }
}

public struct PreKeyTargets: OptionSet, CustomDebugStringConvertible {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let signedPreKey = Self(rawValue: PreKeyTarget.signedPreKey.rawValue)
    static let oneTimePreKey = Self(rawValue: PreKeyTarget.oneTimePreKey.rawValue)
    static let oneTimePqPreKey = Self(rawValue: PreKeyTarget.oneTimePqPreKey.rawValue)
    static let lastResortPqPreKey = Self(rawValue: PreKeyTarget.lastResortPqPreKey.rawValue)

    public mutating func insert(target: PreKeyTarget) {
        self.insert(target.asTargets)
    }

    public func contains(target: PreKeyTarget) -> Bool {
        return self.contains(target.asTargets)
    }

    public var targets: [PreKeyTarget] {
        return PreKeyTarget.allCases.compactMap {
            return self.contains(target: $0) ? $0 : nil
        }
    }

    static var all: Self {
        return PreKeyTarget.allCases.reduce(into: []) { $0.insert(target: $1) }
    }

    public var debugDescription: String {
        return "[" + targets.map { "\($0)" }.joined(separator: ", ") + "]"
    }
}
