//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum AnyGroupIdentifier {
    public typealias GroupIdentifierV2 = LibSignalClient.GroupIdentifier

    case V1(GroupIdentifierV1)
    case V2(GroupIdentifierV2)

    public static func parseFrom(_ groupIdData: Data) throws -> Self {
        if groupIdData.count == kGroupIdLengthV1 {
            return .V1(try GroupIdentifierV1(rawValue: groupIdData))
        }
        return .V2(try GroupIdentifierV2(contents: groupIdData))
    }

    func serialize() -> Data {
        switch self {
        case .V1(let value): value.rawValue
        case .V2(let value): value.serialize()
        }
    }
}

public struct GroupIdentifierV1 {
    let rawValue: Data
    init(rawValue: Data) throws {
        guard rawValue.count == kGroupIdLengthV1 else {
            throw OWSGenericError("group id must be 16 bytes")
        }
        self.rawValue = rawValue
    }
}
