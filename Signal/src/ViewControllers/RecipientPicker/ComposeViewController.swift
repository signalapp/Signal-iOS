//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ComposeViewController: OWSViewController {
    let recipientPicker = RecipientPickerViewController()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("MESSAGE_COMPOSEVIEW_TITLE", comment: "Title for the compose view.")

        recipientPicker.allowsSelectingUnregisteredPhoneNumbers = false
        recipientPicker.shouldShowInvites = true
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(dismissPressed))

        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "btnGroup--white"), style: .plain, target: self, action: #selector(newGroupPressed))
        navigationItem.rightBarButtonItem?.accessibilityLabel = NSLocalizedString("NEW_GROUP_BUTTON_LABEL",
                                                                                  comment: "Accessibility label for the new group button")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DispatchQueue.main.async {
            self.newGroupPressed()
        }
    }

    @objc func dismissPressed() {
        dismiss(animated: true)
    }

    @objc func newGroupPressed() {
        let newGroupView: UIViewController = (FeatureFlags.groupsV2CreateGroups
            ? NewGroupViewController2()
            : NewGroupViewController())
        navigationController?.pushViewController(newGroupView, animated: true)
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
}

extension ComposeViewController: RecipientPickerDelegate {
    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        canSelectRecipient recipient: PickedRecipient
    ) -> Bool {
        return true
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
            guard recipientPicker.contactsViewHelper.isSignalServiceAddressBlocked(address) else { return nil }
            return MessageStrings.conversationIsBlocked
        case .group(let thread):
            guard recipientPicker.contactsViewHelper.isThreadBlocked(thread) else { return nil }
            return MessageStrings.conversationIsBlocked
        }
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         accessoryViewForRecipient recipient: PickedRecipient) -> UIView? {
        return nil
    }

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}
}
