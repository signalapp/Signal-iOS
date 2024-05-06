//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension MessageBackup {

    enum ChatItemArchiverType: Equatable {
        case incomingMessage
        case outgoingMessage
        case groupUpdateInfoMessage
        case individualCall
        case groupCall
        // TODO: remove once all types are implemented
        case unimplemented
    }
}

extension TSInteraction {

    func archiverType(
        localIdentifiers: LocalIdentifiers
    ) -> MessageBackup.ChatItemArchiverType {
        if self is TSIncomingMessage {
            return .incomingMessage
        } else if self is TSOutgoingMessage {
            return .outgoingMessage
        } else if self is TSCall {
            return .individualCall
        } else if self is OWSGroupCallMessage {
            return .groupCall
        } else if let infoMessage = self as? TSInfoMessage {
            switch infoMessage.groupUpdateMetadata(localIdentifiers: localIdentifiers) {
            case .nonGroupUpdate:
                // TODO: other info message types
                break
            case .legacyRawString:
                // Declare that we can archive this, so that its not unhandled.
                // We won't actually archive it though; we just drop these.
                return .groupUpdateInfoMessage
            case .precomputed, .modelDiff, .newGroup:
                return .groupUpdateInfoMessage
            }
        }
        return .unimplemented
    }
}

extension BackupProto.ChatItem {

    internal var archiverType: MessageBackup.ChatItemArchiverType {
        switch directionalDetails {
        case .incoming:
            return .incomingMessage
        case .outgoing:
            return .outgoingMessage
        case nil, .directionless:
            break
        }

        switch item {
        case .updateMessage(let chatUpdateMessage):
            switch chatUpdateMessage.update {
            case .groupChange:
                return .groupUpdateInfoMessage
            default:
                break
            }
        default:
            break
        }

        return .unimplemented
    }
}
