//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

enum ChatFolderChatType {
    case individual
    case group

    var name: String {
        switch self {
        case .individual:
            OWSLocalizedString(
                "CHAT_FOLDERS_CHAT_TYPE_INDIVIDUAL",
                comment: "A type of chat a chat folder can include: every 1:1 chat.",
            )
        case .group:
            OWSLocalizedString(
                "CHAT_FOLDERS_CHAT_TYPE_GROUPS",
                comment: "A type of chat a chat folder can include: every group chat.",
            )
        }
    }

    var symbol: SignalSymbol {
        switch self {
        case .individual: .person
        case .group: .group
        }
    }
}
