//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
protocol AddToBlockListDelegate: class {
    func addToBlockListComplete()
}

@objc
class AddToBlockListViewController: OWSViewController {
    @objc weak var delegate: AddToBlockListDelegate?
    let recipientPicker = RecipientPickerViewController()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_ADD_TO_BLOCK_LIST_TITLE",
                                  comment: "Title for the 'add to block list' view.")

        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)
        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .trailing)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)

        recipientPicker.findByPhoneNumberButtonTitle = NSLocalizedString(
            "BLOCK_LIST_VIEW_BLOCK_BUTTON",
            comment: "A label for the block button in the block list view"
        )
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
        canSelectRecipient recipient: PickedRecipient
    ) -> RecipientPickerRecipientState {
        switch recipient.identifier {
        case .address(let address):
            guard !contactsViewHelper.isSignalServiceAddressBlocked(address) else {
                return .userAlreadyInBlocklist
            }
            return .canBeSelected
        case .group(let thread):
            guard !contactsViewHelper.isThreadBlocked(thread) else {
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
                         willRenderRecipient recipient: PickedRecipient) {
        // Do nothing.
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         prepareToSelectRecipient recipient: PickedRecipient) -> AnyPromise {
        owsFailDebug("This method should not called.")
        return AnyPromise(Promise.value(()))
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         showInvalidRecipientAlert recipient: PickedRecipient) {
        owsFailDebug("Unexpected error.")
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryMessageForRecipient recipient: PickedRecipient
    ) -> String? {
        switch recipient.identifier {
        case .address(let address):
            guard contactsViewHelper.isSignalServiceAddressBlocked(address) else { return nil }
            return MessageStrings.conversationIsBlocked
        case .group(let thread):
            guard contactsViewHelper.isThreadBlocked(thread) else { return nil }
            return MessageStrings.conversationIsBlocked
        }
    }

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}

    func recipientPickerNewGroupButtonWasPressed() {}

    func recipientPickerCustomHeaderViews() -> [UIView] { return [] }
}
