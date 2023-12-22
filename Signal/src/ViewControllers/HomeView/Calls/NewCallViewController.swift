//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalCoreKit
import SignalServiceKit

class NewCallViewController: RecipientPickerContainerViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "New Call" // [CallsTab] TODO: Localize

        recipientPicker.allowsAddByPhoneNumber = true
        recipientPicker.shouldShowInvites = true
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

    private func startCall(recipient: PickedRecipient, withVideo: Bool) {
        switch recipient.identifier {
        case let .address(address):
            let thread = TSContactThread.getOrCreateThread(contactAddress: address)
            // [CallsTab] TODO: See ConversationViewController.startIndividualCall(withVideo:)
            callService.initiateCall(thread: thread, isVideo: withVideo)
            self.dismiss(animated: false)
        case let .group(groupThread):
            // [CallsTab] TODO: See ConversationViewController.showGroupLobbyOrActiveCall()
            GroupCallViewController.presentLobby(thread: groupThread)
        }
    }
}

extension NewCallViewController: RecipientPickerDelegate {
    func recipientPicker(_ recipientPickerViewController: SignalUI.RecipientPickerViewController, getRecipientState recipient: SignalUI.PickedRecipient) -> SignalUI.RecipientPickerRecipientState {
        .canBeSelected
    }

    func recipientPicker(_ recipientPickerViewController: SignalUI.RecipientPickerViewController, didSelectRecipient recipient: SignalUI.PickedRecipient) {
        startCall(recipient: recipient, withVideo: false)
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController, accessoryViewForRecipient recipient: PickedRecipient, transaction: SDSAnyReadTransaction) -> ContactCellAccessoryView? {
        // [CallsTab] TODO: Add support for group cell accessory views
        // [CallsTab] TODO: Adjust for dark mode
        // These tint colors do already appear properly in light and dark mode
        // initially, but changing theme while displayed does not change these.
        let voiceCallImageView = UIImageView(image: Theme.iconImage(.buttonVoiceCall))
        // [CallsTab] TODO: Enable user interation on ContactCellConfiguration
        // In order for this button to work, ContactCellConfiguration.allowUserInteraction needs to be true.
        // Check before enabling the calls tab feature flag if that hard-coded
        // bool can be flipped or if it needs to be made configurable.
        let videoCallButton = OWSButton(imageName: Theme.iconName(.buttonVideoCall), tintColor: nil) { [weak self] in
            self?.startCall(recipient: recipient, withVideo: true)
        }
        let stackView = UIStackView(arrangedSubviews: [
            voiceCallImageView,
            videoCallButton,
        ])
        stackView.axis = .horizontal
        stackView.spacing = 20
        return .init(accessoryView: stackView, size: .init(width: 24 * 2 + 20, height: 24))
    }
}
