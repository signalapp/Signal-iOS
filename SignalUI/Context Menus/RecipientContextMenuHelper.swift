//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit

class RecipientContextMenuHelper {

    private let databaseStorage: SDSDatabaseStorage
    private let recipientHidingManager: RecipientHidingManager
    // TODO: When BlockingManager is protocolized, this should be the protocol type.
    private let blockingManager: BlockingManager
    private let accountManager: TSAccountManager
    private let contactsManager: ContactsManagerProtocol

    /// The view controller from which to present action
    /// sheets and toasts.
    private weak var fromViewController: UIViewController?

    /// Initializer. This helper must be retained for as
    /// long as context menu display should be possible.
    init(
        databaseStorage: SDSDatabaseStorage,
        blockingManager: BlockingManager,
        recipientHidingManager: RecipientHidingManager,
        accountManager: TSAccountManager,
        contactsManager: ContactsManagerProtocol,
        fromViewController: UIViewController
    ) {
        self.databaseStorage = databaseStorage
        self.blockingManager = blockingManager
        self.recipientHidingManager = recipientHidingManager
        self.accountManager = accountManager
        self.contactsManager = contactsManager
        self.fromViewController = fromViewController
    }

    /// Returns the `UIContextMenuActionProvider` used to configure
    /// a system context menu for a recipient with the given `address`.
    func actionProvider(address: SignalServiceAddress) -> UIContextMenuActionProvider {
        return { [weak self] _ in
            guard
                let self,
                let fromViewController = self.fromViewController
            else {
                return nil
            }
            let localAddress: SignalServiceAddress? = self.databaseStorage.read { [weak self] tx in
                guard let self else { return nil }
                return self.accountManager.localAddress(with: tx)
            }
            guard
                let localAddress,
                !localAddress.isEqualToAddress(address) else
            {
                /// There may come a day when the recipient context menu has
                /// menu items that should be available for Note to Self, at
                /// which point this should no longer return nil.
                return nil
            }
            return UIMenu(children: [
                self.removeAction(address: address, fromViewController: fromViewController),
                self.blockAction(address: address, fromViewController: fromViewController)
            ])
        }
    }

    /// Returns context menu action for hiding a recipient.
    ///
    /// - Parameter address: Address of the recipient.
    /// - Parameter fromViewController: The view controller from which to present the action sheet.
    ///
    /// - Returns: A Remove UIAction.
    private func removeAction(
        address: SignalServiceAddress,
        fromViewController: UIViewController
    ) -> UIAction {
        let title = OWSLocalizedString(
            "RECIPIENT_CONTEXT_MENU_REMOVE_TITLE",
            comment: "The title for a context menu item that removes a recipient from your recipient picker list."
        )
        return UIAction(
            title: title,
            image: UIImage(named: "minus-circle")
        ) { [weak self] _ in
            guard let self else { return }
            if self.isSystemContact(address: address) {
                self.displayViewContactActionSheet(
                    address: address,
                    fromViewController: fromViewController
                )
            } else {
                self.displayHideRecipientActionSheet(
                    address: address,
                    fromViewController: fromViewController
                )
            }
        }
    }

    /// Whether the given `address` corresponds with a system contact.
    private func isSystemContact(address: SignalServiceAddress) -> Bool {
        return databaseStorage.read { tx in
            contactsManager.isSystemContact(address: address, transaction: tx)
        }
    }

    /// Returns context menu action for blocking a recipient.
    ///
    /// - Parameter address: Address of the recipient.
    /// - Parameter fromViewController: The view controller from which to present the action sheet.
    ///
    /// - Returns: A Block UIAction.
    private func blockAction(
        address: SignalServiceAddress,
        fromViewController: UIViewController
    ) -> UIAction {
        let title = OWSLocalizedString(
            "RECIPIENT_CONTEXT_MENU_BLOCK_TITLE",
            comment: "The title for a context menu item that blocks a recipient from your recipient picker list."
        )
        return UIAction(
            title: title,
            image: UIImage(named: "block"),
            attributes: .destructive
        ) { _ in
            BlockListUIUtils.showBlockAddressActionSheet(
                address,
                from: fromViewController,
                completion: nil
            )
        }
    }

    private enum Constants {
        static let toastInset = 8.0
    }

    /// Displays an action sheet confirming that the user wants to hide
    /// the indicated recipient.
    ///
    /// - Parameter address: Address of the recipient to hide.
    /// - Parameter fromViewController: The view controller from which to present the action sheet.
    private func displayHideRecipientActionSheet(
        address: SignalServiceAddress,
        fromViewController: UIViewController
    ) {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address).")
            return
        }
        let (localAddress, recipientDisplayName) = databaseStorage.read { tx in
            let localAddress = accountManager.localAddress(with: tx)
            let recipientDisplayName = contactsManager.displayName(
                for: address,
                transaction: tx
            ).formattedForActionSheetTitle()
            return (localAddress, recipientDisplayName)
        }
        guard
            let localAddress,
            !localAddress.isEqualToAddress(address) else
        {
            owsFailDebug("Remove recipient option should not have been shown in context menu for Note to Self, so we shouldn't be able to get here.")
            return
        }
        let actionSheetTitle = String(
            format: OWSLocalizedString(
                "HIDE_RECIPIENT_ACTION_SHEET_TITLE_FORMAT",
                comment: "A format for the 'remove user' action sheet title. Embeds {{the removed user's name or phone number}}."
            ),
            recipientDisplayName
        )

        let actionSheet = ActionSheetController(
            title: actionSheetTitle,
            message: OWSLocalizedString(
                "HIDE_RECIPIENT_BEHAVIOR_EXPLANATION",
                comment: "An explanation of the consequences of removing a user."
            )
        )

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("HIDE_RECIPIENT_BUTTON", comment: "Button label for the 'remove' button"),
            style: .destructive,
            handler: { [weak self] _ in
                guard let self else { return }
                let result: Result<Void, Error> = self.databaseStorage.write { tx in
                    do {
                        try self.recipientHidingManager.addHiddenRecipient(
                            address,
                            wasLocallyInitiated: true,
                            tx: tx.asV2Write
                        )
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }

                switch result {
                case .success(()):
                    self.displaySuccessToast(
                        fromViewController: fromViewController,
                        displayName: recipientDisplayName
                    )
                case .failure(let error):
                    /// This `error` is of the custom type ``RecipientHidingError``.
                    /// We do not currently handle the various errors differently
                    /// in the UI (Design wants to use the generic error message),
                    /// but we do have the capability if we wanted to add per-error
                    /// localized Strings in the future.
                    Logger.warn("[Recipient Hiding] Error: \(error)")
                    self.displayErrorActionSheet(
                        fromViewController: fromViewController,
                        displayName: recipientDisplayName
                    )
                }
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel
        ))
        fromViewController.presentActionSheet(actionSheet)
    }

    /// Displays an action sheet letting the user know that
    /// they cannot remove the indicated recipient without
    /// first removing them from their system contacts.
    ///
    /// - Parameter address: Address of the recipient to hide.
    /// - Parameter fromViewController: The view controller from which to present the action sheet.
    private func displayViewContactActionSheet(
        address: SignalServiceAddress,
        fromViewController: UIViewController
    ) {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address).")
            return
        }
        let (localAddress, recipientDisplayName) = databaseStorage.read { tx in
            let localAddress = accountManager.localAddress(with: tx)
            let recipientDisplayName = contactsManager.displayName(
                for: address,
                transaction: tx
            ).formattedForActionSheetTitle()
            return (localAddress, recipientDisplayName)
        }
        guard
            let localAddress,
            !localAddress.isEqualToAddress(address) else
        {
            owsFailDebug("Remove recipient option should not have been shown in context menu for Note to Self, so we shouldn't be able to get here.")
            return
        }
        let actionSheetTitle = String(
            format: OWSLocalizedString(
                "HIDE_RECIPIENT_IMPASS_BECAUSE_SYSTEM_CONTACT_ACTION_SHEET_TITLE",
                comment: "A format for the 'unable to remove user' action sheet title. Embeds {{the removed user's name or phone number}}."
            ),
            recipientDisplayName
        )

        let actionSheet = ActionSheetController(
            title: actionSheetTitle,
            message: OWSLocalizedString(
                "HIDE_RECIPIENT_IMPASS_BECAUSE_SYSTEM_CONTACT_ACTION_SHEET_EXPLANATION",
                comment: "An explanation of why the user cannot be removed."
            )
        )

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("VIEW_CONTACT_BUTTON", comment: "Button label for the 'View Contact' button"),
            handler: { _ in
                // TODO: present contact sheet
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.okayButton,
            style: .cancel
        ))
        fromViewController.presentActionSheet(actionSheet)
    }

    /// Displays a toast confirming the successful hide of a recipient.
    ///
    /// - Parameter fromViewController: The view controller from which to
    ///   present the toast.
    private func displaySuccessToast(
        fromViewController: UIViewController,
        displayName: String
    ) {
        let toastMessage = String(
            format: OWSLocalizedString(
                "HIDE_RECIPIENT_CONFIRMATION_TOAST",
                comment: "Toast message confirming the recipient was removed. Embeds {{The name of the user who was removed.}}.."
            ),
            displayName
        )
        ToastController(text: toastMessage).presentToastView(
            from: .bottom,
            of: fromViewController.view,
            inset: fromViewController.view.safeAreaInsets.bottom + Constants.toastInset
        )
    }

    /// Displays an action sheet notifying the user that their attempt to
    /// hide a recipient failed.
    ///
    /// - Parameter fromViewController: The view controller from which to
    ///   present the action sheet.
    /// - Parameter displayName: The display name of the recipient the user
    ///   attempted to hide.
    private func displayErrorActionSheet(
        fromViewController: UIViewController,
        displayName: String
    ) {
        let errorActionSheetTitle = String(
            format: OWSLocalizedString(
                "HIDE_RECIPIENT_ERROR_ACTION_SHEET_TITLE_FORMAT",
                comment: "Title for an action sheet indicating that the user was not successfully removed. Embeds {{name of user we attempted to hide}}."
            ),
            displayName
        )
        let errorActionSheet = ActionSheetController(
            title: errorActionSheetTitle,
            message: OWSLocalizedString(
                "HIDE_RECIPIENT_ERROR_ACTION_SHEET_EXPLANATION",
                comment: "An explanation of why a user was not successfully removed and what to do."
            )
        )
        errorActionSheet.addAction(ActionSheetAction(
            title: CommonStrings.okayButton
        ))
        fromViewController.presentActionSheet(errorActionSheet)
    }
}
