//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public enum ActionSheetDisplayableError: Error {
    case networkError
    case genericError
    case custom(localizedMessage: String)

    public func showActionSheet(from fromViewController: UIViewController?) {
        OWSActionSheets.showActionSheet(
            message: localizedActionSheetMessage,
            fromViewController: fromViewController,
        )
    }

    private var localizedActionSheetMessage: String {
        switch self {
        case .networkError:
            OWSLocalizedString(
                "ACTION_SHEET_DISPLAYABLE_ERROR_NETWORK_ERROR",
                comment: "Message shown in an action sheet when a network error occurs."
            )
        case .genericError:
            OWSLocalizedString(
                "ACTION_SHEET_DISPLAYABLE_ERROR_GENERIC_ERROR",
                comment: "Message shown in an action sheet when a generic error occurs."
            )
        case .custom(let localizedMessage):
            localizedMessage
        }
    }
}
