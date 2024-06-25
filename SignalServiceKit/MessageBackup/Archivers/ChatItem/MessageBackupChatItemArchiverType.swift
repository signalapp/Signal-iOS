//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension MessageBackup {

    enum ChatItemArchiverType: Equatable {
        case incomingMessage
        case outgoingMessage
        case chatUpdateMessage

        // TODO: remove once all types are implemented
        case unimplemented
    }
}

extension TSInteraction {

    func archiverType() -> MessageBackup.ChatItemArchiverType {
        if self is TSIncomingMessage {
            return .incomingMessage
        } else if self is TSOutgoingMessage {
            return .outgoingMessage
        } else if
            self is TSInfoMessage
                || self is TSErrorMessage
                || self is TSCall
                || self is OWSGroupCallMessage
        {
            return .chatUpdateMessage
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
        case .updateMessage:
            return .chatUpdateMessage
        default:
            break
        }

        return .unimplemented
    }
}
