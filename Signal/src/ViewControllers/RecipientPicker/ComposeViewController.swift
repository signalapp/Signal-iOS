//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

@objc
class ComposeViewController: RecipientPickerContainerViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("MESSAGE_COMPOSEVIEW_TITLE", comment: "Title for the compose view.")

        view.backgroundColor = Theme.backgroundColor

        recipientPicker.shouldShowInvites = true
        recipientPicker.shouldShowNewGroup = true
        recipientPicker.groupsToShow = .showGroupsThatUserIsMemberOfWhenSearching
        recipientPicker.shouldHideLocalRecipient = false

        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)
        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .trailing)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(dismissPressed))
    }

    @objc
    private func dismissPressed() {
        dismiss(animated: true)
    }

    @objc
    private func newGroupPressed() {
        showNewGroupUI()
    }

    /// Presents the conversation for the given address and dismisses this
    /// controller such that the conversation is visible.
    func newConversation(address: SignalServiceAddress) {
        AssertIsOnMainThread()
        owsAssertDebug(address.isValid)

        let thread = Self.databaseStorage.write { transaction in
            TSContactThread.getOrCreateThread(withContactAddress: address,
                                              transaction: transaction)
        }
        self.newConversation(thread: thread)
    }

    /// Presents the conversation for the given thread and dismisses this
    /// controller such that the conversation is visible.
    ///
    /// - Note
    /// In practice, the view controller dismissing us here is the same one
    /// (a ``ConversationSplitViewController``) that will ultimately present the
    /// conversation. To that end, there be dragons in potential races between
    /// the two actions, which seem to particularly be prominent when this
    /// method is called from a `DispatchQueue.main` block. (This happens, for
    /// example, when doing some asynchronous work, such as a lookup, which
    /// completes in a `DispatchQueue.main` block that calls this method.)
    ///
    /// Some example dragons found at the time of writing include user
    /// interaction being disabled on the nav bar, incorrect nav bar layout,
    /// keyboards refusing to pop, and the conversation input toolbar being
    /// hidden behind the keyboard if it does pop.
    ///
    /// Ensuring that the presentation and dismissal are in separate dispatch
    /// blocks seems to dodge the dragons.
    func newConversation(thread: TSThread) {
        SignalApp.shared.presentConversationForThread(thread, action: .compose, animated: false)

        DispatchQueue.main.async { [weak self] in
            self?.presentingViewController?.dismiss(animated: true)
        }
    }

    func showNewGroupUI() {
        navigationController?.pushViewController(NewGroupMembersViewController(), animated: true)
    }
}

extension ComposeViewController: RecipientPickerDelegate {

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        getRecipientState recipient: PickedRecipient
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
                         prepareToSelectRecipient recipient: PickedRecipient) -> AnyPromise {
        owsFailDebug("This method should not called.")
        return AnyPromise(Promise.value(()))
    }

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        didDeselectRecipient recipient: PickedRecipient
    ) {}

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

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         attributedSubtitleForRecipient recipient: PickedRecipient,
                         transaction: SDSAnyReadTransaction) -> NSAttributedString? {
        switch recipient.identifier {
        case .address(let address):
            guard !address.isLocalAddress else {
                return nil
            }
            if let bioForDisplay = Self.profileManagerImpl.profileBioForDisplay(for: address,
                                                                                transaction: transaction) {
                return NSAttributedString(string: bioForDisplay)
            }
            return nil
        case .group:
            return nil
        }
    }

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}

    func recipientPickerNewGroupButtonWasPressed() {
        showNewGroupUI()
    }

    func recipientPickerCustomHeaderViews() -> [UIView] { return [] }
}
