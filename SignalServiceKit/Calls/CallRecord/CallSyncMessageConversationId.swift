//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// Represents an identifier for a conversation used in multiple sync messages
/// related to calls.
///
/// Specifically, at the time of writing this conversation ID is reused across
/// `CallEvent` and `CallLogEvent` sync messages.
///
/// - SeeAlso ``OutgoingCallEventSyncMessage``
/// - SeeAlso ``OutgoingCallLogEventSyncMessage``
public enum CallSyncMessageConversationId {
    case individual(contactServiceId: ServiceId)
    case group(groupId: Data)

    // MARK: -

    static func from(data: Data) -> CallSyncMessageConversationId? {
        if let contactServiceId = try? ServiceId.parseFrom(serviceIdBinary: data) {
            return .individual(contactServiceId: contactServiceId)
        } else if GroupManager.isV2GroupId(data) {
            return .group(groupId: data)
        }

        return nil
    }

    var asData: Data {
        switch self {
        case .individual(let contactServiceId):
            return Data(contactServiceId.serviceIdBinary)
        case .group(let groupId):
            return groupId
        }
    }
}
