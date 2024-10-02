//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

/// Encodes CallEvent.type & CallEvent.conversationId fields.
///
/// This is used by SyncMessage.CallEvent to identify where a call happened.
/// These two fields must be interpreted in tandem because conversationId is
/// ambiguous unless the type is known.
public enum CallEventConversation {
    case individualThread(serviceId: ServiceId, isVideo: Bool)
    case groupThread(groupId: Data)
    case adHoc(roomId: Data)

    init(type: CallRecord.CallType, conversationId: Data) throws {
        switch type {
        case .audioCall:
            let serviceId = try ServiceId.parseFrom(serviceIdBinary: conversationId)
            self = .individualThread(serviceId: serviceId, isVideo: false)
        case .videoCall:
            let serviceId = try ServiceId.parseFrom(serviceIdBinary: conversationId)
            self = .individualThread(serviceId: serviceId, isVideo: true)
        case .groupCall:
            let groupIdentifier = try GroupIdentifier(contents: [UInt8](conversationId))
            self = .groupThread(groupId: groupIdentifier.serialize().asData)
        case .adHocCall:
            self = .adHoc(roomId: conversationId)
        }
    }

    var type: CallRecord.CallType {
        switch self {
        case .individualThread(_, let isVideo):
            return isVideo ? .videoCall : .audioCall
        case .groupThread:
            return .groupCall
        case .adHoc:
            return .adHocCall
        }
    }

    var id: Data {
        switch self {
        case .individualThread(let serviceId, _):
            return Data(serviceId.serviceIdBinary)
        case .groupThread(let groupId):
            return groupId
        case .adHoc(let roomId):
            return roomId
        }
    }
}
