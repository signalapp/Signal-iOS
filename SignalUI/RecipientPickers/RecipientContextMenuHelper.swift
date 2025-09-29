//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
public import SignalServiceKit

public protocol RecipientContextMenuHelperDelegate: AnyObject {
    func additionalActions(for address: SignalServiceAddress) -> [UIAction]
    func additionalActions(for groupThread: TSGroupThread) -> [UIAction]
}
public extension RecipientContextMenuHelperDelegate {
    func additionalActions(for address: SignalServiceAddress) -> [UIAction] {
        []
    }
    func additionalActions(for groupThread: TSGroupThread) -> [UIAction] { [] }
}

final class RecipientContextMenuHelper {

    private let databaseStorage: SDSDatabaseStorage
    private let recipientHidingManager: RecipientHidingManager
    // TODO: When BlockingManager is protocolized, this should be the protocol type.
    private let blockingManager: BlockingManager
    private let accountManager: TSAccountManager
    private let contactsManager: any ContactManager

    /// The view controller from which to present action
    /// sheets and toasts.
    private weak var fromViewController: UIViewController?

    weak var delegate: (any RecipientContextMenuHelperDelegate)?

    /// Initializer. This helper must be retained for as
    /// long as context menu display should be possible.
    init(
        databaseStorage: SDSDatabaseStorage,
        blockingManager: BlockingManager,
        recipientHidingManager: RecipientHidingManager,
        accountManager: TSAccountManager,
        contactsManager: any ContactManager,
        fromViewController: UIViewController,
        delegate: (any RecipientContextMenuHelperDelegate)? = nil
    ) {
        self.databaseStorage = databaseStorage
        self.blockingManager = blockingManager
        self.recipientHidingManager = recipientHidingManager
        self.accountManager = accountManager
        self.contactsManager = contactsManager
        self.fromViewController = fromViewController
        self.delegate = delegate
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
                return self.accountManager.localIdentifiers(tx: tx)?.aciAddress
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
            let additionalActions = self.delegate?.additionalActions(for: address) ?? []
            return UIMenu(children: additionalActions + [
                self.removeAction(address: address, fromViewController: fromViewController),
                self.blockAction(address: address, fromViewController: fromViewController)
            ])
        }
    }

    func actionProvider(groupThread: TSGroupThread) -> UIContextMenuActionProvider {
        { [weak self] _ in
            guard
                let self,
                let fromViewController = self.fromViewController
            else {
                return nil
            }
            let additionalActions = self.delegate?.additionalActions(for: groupThread) ?? []
            return UIMenu(children: additionalActions + [
                self.blockAction(thread: groupThread, fromViewController: fromViewController),
            ])
        }
    }

    // MARK: Block

    private var blockActionTitle: String {
        OWSLocalizedString(
            "RECIPIENT_CONTEXT_MENU_BLOCK_TITLE",
            comment: "The title for a context menu item that blocks a recipient from your recipient picker list."
        )
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
        UIAction(
            title: blockActionTitle,
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

    private func blockAction(
        thread: TSThread,
        fromViewController: UIViewController
    ) -> UIAction {
        UIAction(
            title: blockActionTitle,
            image: UIImage(named: "block"),
            attributes: .destructive
        ) { _ in
            BlockListUIUtils.showBlockThreadActionSheet(
                thread,
                from: fromViewController,
                completion: nil
            )
        }
    }

    // MARK: Remove contact

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
            if let e164 = address.e164, self.isSystemContact(e164: e164) {
                self.displayViewContactActionSheet(
                    address: address,
                    e164: e164,
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

    /// Whether the given `e164` corresponds with a system contact.
    private func isSystemContact(e164: E164) -> Bool {
        return databaseStorage.read { tx in
            return contactsManager.fetchSignalAccount(forPhoneNumber: e164.stringValue, transaction: tx) != nil
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
            let localAddress = accountManager.localIdentifiers(tx: tx)?.aciAddress
            let recipientDisplayName = contactsManager.displayName(for: address, tx: tx)
                .resolvedValue().formattedForActionSheetTitle()
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
                            inKnownMessageRequestState: false,
                            wasLocallyInitiated: true,
                            tx: tx
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
    /// - Parameter e164: Phone number of the recipient to hide.
    /// - Parameter fromViewController: The view controller from which to present the action sheet.
    private func displayViewContactActionSheet(
        address: SignalServiceAddress,
        e164: E164,
        fromViewController: UIViewController
    ) {
        let (
            isPrimaryDevice,
            localAddress,
            recipientDisplayName
        ) = databaseStorage.read { tx in
            let localAddress = accountManager.localIdentifiers(tx: tx)?.aciAddress
            let recipientDisplayName = contactsManager.displayName(for: address, tx: tx)
                .resolvedValue().formattedForActionSheetTitle()
            return (
                accountManager.registrationState(tx: tx).isPrimaryDevice ?? true,
                localAddress,
                recipientDisplayName
            )
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

        let actionSheetMessage: String
        let removeAction: ActionSheetAction?
        if isPrimaryDevice {
            actionSheetMessage = OWSLocalizedString(
                "HIDE_RECIPIENT_IMPASS_BECAUSE_SYSTEM_CONTACT_ACTION_SHEET_EXPLANATION",
                comment: "An explanation of why the user cannot be removed."
            )
            removeAction = ActionSheetAction(
                title: OWSLocalizedString("VIEW_CONTACT_BUTTON", comment: "Button label for the 'View Contact' button"),
                handler: { [weak self] _ in
                    guard let self else { return }
                    self.displayDeleteContactViewController(
                        e164: e164,
                        serviceId: address.serviceId,
                        fromViewController: fromViewController
                    )
                }
            )
        } else {
            actionSheetMessage = OWSLocalizedString(
                "HIDE_RECIPIENT_IMPOSSIBLE_BECAUSE_SYSTEM_CONTACT_ACTION_SHEET_EXPLANATION",
                comment: "An explanation of why the user cannot be removed on a linked device."
            )
            removeAction = nil
        }

        let actionSheet = ActionSheetController(
            title: actionSheetTitle,
            message: actionSheetMessage
        )

        if let removeAction {
            actionSheet.addAction(removeAction)
        }
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.okayButton,
            style: .cancel
        ))
        fromViewController.presentActionSheet(actionSheet)
    }

    /// Displays a view controller with a simplified contact
    /// view and the option to delete this contact.
    ///
    /// - Parameter e164: The phone number of the contact to
    ///   potentially be deleted.
    /// - Parameter fromViewController: The view controller
    ///   from which to present this contact deletion view
    ///   controller.
    private func displayDeleteContactViewController(
        e164: E164,
        serviceId: ServiceId?,
        fromViewController: UIViewController
    ) {
        let deleteContactViewController = DeleteSystemContactViewController(
            e164: e164,
            serviceId: serviceId,
            viewControllerPresentingToast: fromViewController,
            contactsManager: contactsManager,
            databaseStorage: databaseStorage,
            recipientHidingManager: recipientHidingManager,
            tsAccountManager: accountManager
        )
        let navigationController = OWSNavigationController()
        navigationController.setViewControllers([deleteContactViewController], animated: false)
        fromViewController.presentFormSheet(navigationController, animated: true)
    }

    /// Displays a toast confirming the successful hide of a recipient.
    ///
    /// - Parameter fromViewController: The view controller from which to
    ///   present the toast.
    /// - Parameter displayName: The the display name of the user who has
    ///   been hidden.
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
