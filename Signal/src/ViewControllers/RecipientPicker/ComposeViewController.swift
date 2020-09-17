//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
class ComposeViewController: OWSViewController {
    let recipientPicker = RecipientPickerViewController()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("MESSAGE_COMPOSEVIEW_TITLE", comment: "Title for the compose view.")

        view.backgroundColor = Theme.backgroundColor

        recipientPicker.allowsSelectingUnregisteredPhoneNumbers = false
        recipientPicker.shouldShowInvites = true
        recipientPicker.shouldShowNewGroup = true
        recipientPicker.shouldHideLocalRecipient = false
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)
        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .trailing)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(dismissPressed))
    }

    @objc func dismissPressed() {
        dismiss(animated: true)
    }

    @objc func newGroupPressed() {
        showNewGroupUI()
    }

    func newConversation(address: SignalServiceAddress) {
        assert(address.isValid)
        let thread = TSContactThread.getOrCreateThread(contactAddress: address)
        newConversation(thread: thread)
    }

    func newConversation(thread: TSThread) {
        SignalApp.shared().presentConversation(for: thread, action: .compose, animated: false)
        presentingViewController?.dismiss(animated: true)
    }

    func showNewGroupUI() {
        navigationController?.pushViewController(NewGroupMembersViewController(), animated: true)
    }
}

extension ComposeViewController: RecipientPickerDelegate {

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        canSelectRecipient recipient: PickedRecipient
    ) -> RecipientPickerRecipientState {
        return .canBeSelected
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        didSelectRecipient recipient: PickedRecipient
    ) {
        switch recipient.identifier {
        case .address(let address):
            newConversation(address: address)
        case .group(let groupThread):
            newConversation(thread: groupThread)
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
        didDeselectRecipient recipient: PickedRecipient
    ) {}

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

    func recipientPickerNewGroupButtonWasPressed() {
        showNewGroupUI()
    }

    func recipientPickerCustomHeaderViews() -> [UIView] { return [] }
}
