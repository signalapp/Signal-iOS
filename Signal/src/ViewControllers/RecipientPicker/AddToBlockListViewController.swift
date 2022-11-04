//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

@objc
protocol AddToBlockListDelegate: AnyObject {
    func addToBlockListComplete()
}

@objc
class AddToBlockListViewController: RecipientPickerContainerViewController {
    @objc
    weak var delegate: AddToBlockListDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_ADD_TO_BLOCK_LIST_TITLE",
                                  comment: "Title for the 'add to block list' view.")

        recipientPicker.preferredNavigationBarStyle = OWSNavigationBarStyle.clear.rawValue
        recipientPicker.selectionMode = .blocklist
        recipientPicker.groupsToShow = .showAllGroupsWhenSearching
        recipientPicker.findByPhoneNumberButtonTitle = NSLocalizedString(
            "BLOCK_LIST_VIEW_BLOCK_BUTTON",
            comment: "A label for the block button in the block list view"
        )
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)
        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .trailing)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)
    }

    func block(address: SignalServiceAddress) {
        BlockListUIUtils.showBlockAddressActionSheet(
            address,
            from: self,
            completionBlock: { [weak self] isBlocked in
                guard isBlocked else { return }
                self?.delegate?.addToBlockListComplete()
            }
        )
    }

    func block(thread: TSThread) {
        BlockListUIUtils.showBlockThreadActionSheet(
            thread,
            from: self,
            completionBlock: { [weak self] isBlocked in
                guard isBlocked else { return }
                self?.delegate?.addToBlockListComplete()
            }
        )
    }
}

extension AddToBlockListViewController: RecipientPickerDelegate {

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        getRecipientState recipient: PickedRecipient
    ) -> RecipientPickerRecipientState {
        switch recipient.identifier {
        case .address(let address):
            let isAddressBlocked = databaseStorage.read { blockingManager.isAddressBlocked(address, transaction: $0) }
            guard !isAddressBlocked else {
                return .userAlreadyInBlocklist
            }
            return .canBeSelected
        case .group(let thread):
            let isThreadBlocked = databaseStorage.read { blockingManager.isThreadBlocked(thread, transaction: $0) }
            guard !isThreadBlocked else {
                return .conversationAlreadyInBlocklist
            }
            return .canBeSelected
        }
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        didSelectRecipient recipient: PickedRecipient
    ) {
        switch recipient.identifier {
        case .address(let address):
            block(address: address)
        case .group(let groupThread):
            block(thread: groupThread)
        }
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         prepareToSelectRecipient recipient: PickedRecipient) -> AnyPromise {
        owsFailDebug("This method should not called.")
        return AnyPromise(Promise.value(()))
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryMessageForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> String? {
        switch recipient.identifier {
        case .address(let address):
            #if DEBUG
            let isBlocked = blockingManager.isAddressBlocked(address, transaction: transaction)
            owsAssert(!isBlocked, "It should be impossible to see a blocked connection in this view")
            #endif
            return nil
        case .group(let thread):
            guard blockingManager.isThreadBlocked(thread, transaction: transaction) else { return nil }
            return MessageStrings.conversationIsBlocked
        }
    }

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}

    func recipientPickerNewGroupButtonWasPressed() {}

    func recipientPickerCustomHeaderViews() -> [UIView] { return [] }
}
