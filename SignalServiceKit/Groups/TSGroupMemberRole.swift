//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public enum TSGroupMemberRole: UInt, Codable {
    case normal = 0
    case administrator = 1

    public static func role(for value: GroupsProtoMemberRole) -> TSGroupMemberRole? {
        switch value {
        case .`default`:
            return .normal
        case .administrator:
            return .administrator
        default:
            owsFailDebug("Invalid value: \(value.rawValue)")
            return nil
        }
    }

    public var asProtoRole: GroupsProtoMemberRole {
        switch self {
        case .normal:
            return .`default`
        case .administrator:
            return .administrator
        }
    }
}
