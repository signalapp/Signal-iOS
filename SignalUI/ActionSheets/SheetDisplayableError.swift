//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Abstract base class for errors that can be presented in a sheet.
open class SheetDisplayableError: Error {

    @MainActor
    open func showSheet(
        from fromViewController: UIViewController?,
        dismissalDelegate: SheetDismissalDelegate? = nil,
    ) {
        owsFail("Must be overridden by subclasses!")
    }

    // MARK: -

    public static let networkError: SheetDisplayableError = ActionSheetDisplayableError(
        localizedMessage: OWSLocalizedString(
            "ACTION_SHEET_DISPLAYABLE_ERROR_NETWORK_ERROR",
            comment: "Message shown in an action sheet when a network error occurs.",
        ),
    )

    public static let genericError: SheetDisplayableError = ActionSheetDisplayableError(
        localizedMessage: OWSLocalizedString(
            "ACTION_SHEET_DISPLAYABLE_ERROR_GENERIC_ERROR",
            comment: "Message shown in an action sheet when a generic error occurs.",
        ),
    )

    /// - Important
    /// Does not show a sheet, under the assumption that the user having
    /// cancelled makes it obvious why a given action was aborted.
    public static let userCancelled: SheetDisplayableError = ActionSheetDisplayableError(
        localizedMessage: nil,
    )
}

// MARK: -

open class ActionSheetDisplayableError: SheetDisplayableError {
    private let localizedTitle: String?
    private let localizedMessage: String?

    public init(
        localizedTitle: String? = nil,
        localizedMessage: String?,
    ) {
        self.localizedTitle = localizedTitle
        self.localizedMessage = localizedMessage
    }

    @MainActor
    override open func showSheet(
        from fromViewController: UIViewController?,
        dismissalDelegate: SheetDismissalDelegate? = nil,
    ) {
        if let localizedMessage {
            OWSActionSheets.showActionSheet(
                title: localizedTitle,
                message: localizedMessage,
                fromViewController: fromViewController,
                dismissalDelegate: dismissalDelegate,
            )
        }
    }
}

// MARK: -

open class HeroSheetDisplayableError: SheetDisplayableError {
    private let heroSheetBuilder: @MainActor () -> HeroSheetViewController

    public init(
        heroSheetBuilder: @escaping @MainActor () -> HeroSheetViewController,
    ) {
        self.heroSheetBuilder = heroSheetBuilder
    }

    @MainActor
    override open func showSheet(
        from fromViewController: UIViewController?,
        dismissalDelegate: SheetDismissalDelegate? = nil,
    ) {
        let fromViewController = fromViewController ?? CurrentAppContext().frontmostViewController()

        guard let fromViewController else {
            owsFailDebug("Missing fromViewController for hero sheet!")
            return
        }

        let heroSheet = heroSheetBuilder()
        fromViewController.present(heroSheet, animated: true)
    }
}
