//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class RecipientContextMenuHelper {

    private let databaseStorage: SDSDatabaseStorage
    private let recipientHidingManager: RecipientHidingManager
    // TODO: When BlockingManager is protocolized, this should be the protocol type.
    private let blockingManager: BlockingManager

    /// Initializer. This helper must be retained for as
    /// long as context menu display should be possible.
    init(
        databaseStorage: SDSDatabaseStorage,
        blockingManager: BlockingManager,
        recipientHidingManager: RecipientHidingManager
    ) {
        self.databaseStorage = databaseStorage
        self.blockingManager = blockingManager
        self.recipientHidingManager = recipientHidingManager
    }

    /// Returns the `UIContextMenuActionProvider` used to configure
    /// a system context menu for a recipient with the given `address`.
    func actionProvider(address: SignalServiceAddress) -> UIContextMenuActionProvider? {
        return { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(children: [
                self.removeAction(address: address),
                self.blockAction(address: address)
            ])
        }
    }

    /// Returns context menu action for hiding a recipient with the given `address`.
    private func removeAction(address: SignalServiceAddress) -> UIAction {
        let title = OWSLocalizedString(
            "RECIPIENT_CONTEXT_MENU_REMOVE_TITLE",
            comment: "The title for a context menu item that removes a recipient from your recipient picker list."
        )
        return UIAction(
            title: title,
            image: UIImage(named: "minus-circle")
        ) { [weak self] _ in
            guard let self else { return }
            do {
                try self.databaseStorage.write { tx in
                    try self.recipientHidingManager.addHiddenRecipient(
                        address,
                        wasLocallyInitiated: true,
                        tx: tx
                    )
                }
            } catch {
                owsFailDebug("Failed to hide recipient with phone number")
            }
        }
    }

    /// Returns context menu action for blocking a recipient with the given `address`.
    private func blockAction(address: SignalServiceAddress) -> UIAction {
        let title = OWSLocalizedString(
            "RECIPIENT_CONTEXT_MENU_BLOCK_TITLE",
            comment: "The title for a context menu item that blocks a recipient from your recipient picker list."
        )
        return UIAction(
            title: title,
            image: UIImage(named: "block"),
            attributes: .destructive
        ) { [weak self] _ in
            guard let self else { return }
            self.databaseStorage.write { tx in
                self.blockingManager.addBlockedAddress(
                    address,
                    blockMode: .localShouldNotLeaveGroups,
                    transaction: tx
                )
            }
        }
    }
}
