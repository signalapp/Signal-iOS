//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

@objc
class ComposeViewController: RecipientPickerContainerViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("MESSAGE_COMPOSEVIEW_TITLE", comment: "Title for the compose view.")

        view.backgroundColor = Theme.backgroundColor

        recipientPicker.shouldShowInvites = true
        recipientPicker.shouldShowNewGroup = true
        recipientPicker.groupsToShow = .groupsThatUserIsMemberOfWhenSearching
        recipientPicker.shouldHideLocalRecipient = false

        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)
        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .trailing)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)

        navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
    }

    /// Presents the conversation for the given address and dismisses this
    /// controller such that the conversation is visible.
    func newConversation(address: SignalServiceAddress) {
        AssertIsOnMainThread()
        owsAssertDebug(address.isValid)

        let thread = SSKEnvironment.shared.databaseStorageRef.write { transaction in
            TSContactThread.getOrCreateThread(withContactAddress: address,
                                              transaction: transaction)
        }
        self.newConversation(thread: thread)
    }

    /// Presents the conversation for the given thread and dismisses this
    /// controller such that the conversation is visible.
    func newConversation(thread: TSThread) {
        presentingViewController?.dismiss(animated: true)
        if let transitionCoordinator = presentingViewController?.transitionCoordinator {
            // When transitionCoordinator is present, coordinate the immediate presentation of
            // the conversationVC with the animated dismissal of the compose VC
            transitionCoordinator.animate { _ in
                UIView.performWithoutAnimation {
                    SignalApp.shared.presentConversationForThread(thread, action: .compose, animated: false)
                }
            }
        } else {
            // There isn't a transition coordinator present for some reason, revert to displaying
            // the conversation VC in parallel with the animated dismissal of the compose VC
            SignalApp.shared.presentConversationForThread(thread, action: .compose, animated: false)
        }
    }

    func showNewGroupUI() {
        navigationController?.pushViewController(NewGroupMembersViewController(), animated: true)
    }
}

extension ComposeViewController: RecipientPickerDelegate, UsernameLinkScanDelegate {

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

    func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryMessageForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> String? {
        switch recipient.identifier {
        case .address:
            return nil
        case .group(let thread):
            guard SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(thread, transaction: transaction) else { return nil }
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
            if let bioForDisplay = SSKEnvironment.shared.profileManagerImplRef.profileBioForDisplay(for: address,
                                                                                transaction: transaction) {
                return NSAttributedString(string: bioForDisplay)
            }
            return nil
        case .group:
            return nil
        }
    }

    func recipientPickerNewGroupButtonWasPressed() {
        showNewGroupUI()
    }
}
