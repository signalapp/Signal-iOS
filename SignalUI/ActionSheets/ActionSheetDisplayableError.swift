//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Represents an error that is potentially displayable in an action sheet.
public enum ActionSheetDisplayableError: Error {
    case networkError
    case genericError
    case custom(localizedTitle: String? = nil, localizedMessage: String)
    /// - Important
    /// Does not show an action sheet, under the assumption that the user having
    /// manually cancelled makes it obvious why a given action was aborted.
    case userCancelled

    public func showActionSheet(
        from fromViewController: UIViewController?,
        dismissalDelegate: SheetDismissalDelegate? = nil,
    ) {
        if let localizedActionSheetMessage {
            OWSActionSheets.showActionSheet(
                title: localizedActionSheetTitle,
                message: localizedActionSheetMessage,
                fromViewController: fromViewController,
                dismissalDelegate: dismissalDelegate,
            )
        }
    }

    private var localizedActionSheetTitle: String? {
        switch self {
        case .networkError, .genericError, .userCancelled:
            return nil
        case .custom(let title, _):
            return title
        }
    }

    private var localizedActionSheetMessage: String? {
        switch self {
        case .networkError:
            return OWSLocalizedString(
                "ACTION_SHEET_DISPLAYABLE_ERROR_NETWORK_ERROR",
                comment: "Message shown in an action sheet when a network error occurs."
            )
        case .genericError:
            return OWSLocalizedString(
                "ACTION_SHEET_DISPLAYABLE_ERROR_GENERIC_ERROR",
                comment: "Message shown in an action sheet when a generic error occurs."
            )
        case .custom(_, let localizedMessage):
            return localizedMessage
        case .userCancelled:
            return nil
        }
    }
}
