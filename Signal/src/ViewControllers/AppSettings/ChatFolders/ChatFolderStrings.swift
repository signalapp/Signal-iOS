//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

enum ChatFolderStrings {
    static var settingsTitle: String {
        OWSLocalizedString(
            "CHAT_FOLDERS_SETTINGS_TITLE",
            comment: "Title for the chat folders settings screen.",
        )
    }

    static var createFolder: String {
        OWSLocalizedString(
            "CHAT_FOLDERS_SETTINGS_CREATE_FOLDER",
            comment: "Action in chat folder settings and the chat context menu to create a new chat folder.",
        )
    }

    static var editFolder: String {
        OWSLocalizedString(
            "CHAT_FOLDERS_EDIT_FOLDER",
            comment: "Action that edits a chat folder.",
        )
    }

    static var deleteFolder: String {
        OWSLocalizedString(
            "CHAT_FOLDERS_DELETE_FOLDER",
            comment: "Action that deletes a chat folder.",
        )
    }

    static var includedChats: String {
        OWSLocalizedString(
            "CHAT_FOLDERS_INCLUDED_CHATS_HEADER",
            comment: "Header for the list of chats included in a chat folder, and the title of the screen that chooses them.",
        )
    }

    static var excludedChats: String {
        OWSLocalizedString(
            "CHAT_FOLDERS_EXCLUDED_CHATS_HEADER",
            comment: "Header for the list of chats excluded from a chat folder, and the title of the screen that chooses them.",
        )
    }
}
