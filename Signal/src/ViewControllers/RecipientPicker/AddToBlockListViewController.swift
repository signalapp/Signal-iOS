//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol AddToBlockListDelegate: AnyObject {
    func addToBlockListComplete()
}

class AddToBlockListViewController: RecipientPickerContainerViewController {

    weak var delegate: AddToBlockListDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_ADD_TO_BLOCK_LIST_TITLE",
            comment: "Title for the 'add to block list' view.",
        )

        recipientPicker.selectionMode = .blocklist
        recipientPicker.groupsToShow = .allGroupsWhenSearching
        recipientPicker.findByPhoneNumberButtonTitle = OWSLocalizedString(
            "BLOCK_LIST_VIEW_BLOCK_BUTTON",
            comment: "A label for the block button in the block list view",
        )
        recipientPicker.delegate = self

        addRecipientPicker()
    }

    func block(address: SignalServiceAddress) {
        BlockListUIUtils.showBlockAddressActionSheet(address, from: self) { [weak self] isBlocked in
            guard isBlocked else { return }
            self?.delegate?.addToBlockListComplete()
        }
    }

    func block(thread: TSThread) {
        BlockListUIUtils.showBlockThreadActionSheet(thread, from: self) { [weak self] isBlocked in
            guard isBlocked else { return }
            self?.delegate?.addToBlockListComplete()
        }
    }
}

extension AddToBlockListViewController: RecipientPickerDelegate, UsernameLinkScanDelegate {

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        selectionStyleForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction,
    ) -> UITableViewCell.SelectionStyle {
        let blockingManager = SSKEnvironment.shared.blockingManagerRef

        switch recipient.identifier {
        case .address(let address):
            if blockingManager.isAddressBlocked(address, transaction: transaction) {
                return .none
            }
        case .group(let thread):
            if blockingManager.isThreadBlocked(thread, transaction: transaction) {
                return .none
            }
        }

        return .default
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        didSelectRecipient recipient: PickedRecipient,
    ) {
        let blockingManager = SSKEnvironment.shared.blockingManagerRef
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef

        switch recipient.identifier {
        case .address(let address):
            if databaseStorage.read(block: { blockingManager.isAddressBlocked(address, transaction: $0) }) {
                let errorMessage = OWSLocalizedString(
                    "BLOCK_LIST_ERROR_USER_ALREADY_IN_BLOCKLIST",
                    comment: "Error message indicating that a user can't be blocked because they are already blocked.",
                )
                OWSActionSheets.showErrorAlert(message: errorMessage)
                return
            }
            block(address: address)
        case .group(let thread):
            if databaseStorage.read(block: { blockingManager.isThreadBlocked(thread, transaction: $0) }) {
                let errorMessage = OWSLocalizedString(
                    "BLOCK_LIST_ERROR_CONVERSATION_ALREADY_IN_BLOCKLIST",
                    comment: "Error message indicating that a conversation can't be blocked because they are already blocked.",
                )
                OWSActionSheets.showErrorAlert(message: errorMessage)
                return
            }
            block(thread: thread)
        }
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryMessageForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction,
    ) -> String? {
        switch recipient.identifier {
        case .address(let address):
#if DEBUG
            let isBlocked = SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(address, transaction: transaction)
            owsPrecondition(!isBlocked, "It should be impossible to see a blocked connection in this view")
#endif
            return nil
        case .group(let thread):
            guard SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(thread, transaction: transaction) else { return nil }
            return MessageStrings.conversationIsBlocked
        }
    }
}
