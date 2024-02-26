//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalCoreKit
import SignalServiceKit

protocol NewCallViewControllerDelegate: AnyObject {
    func goToChat(for thread: TSThread)
}

class NewCallViewController: RecipientPickerContainerViewController {
    weak var delegate: (any NewCallViewControllerDelegate)?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "New Call" // [CallsTab] TODO: Localize

        recipientPicker.allowsAddByAddress = true
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

    private func startIndividualCall(thread: TSContactThread, withVideo: Bool) {
        // [CallsTab] TODO: See ConversationViewController.startIndividualCall(withVideo:)
        callService.initiateCall(thread: thread, isVideo: withVideo)
        self.dismiss(animated: false)
    }

    private func startGroupCall(thread: TSGroupThread) {
        // [CallsTab] TODO: See ConversationViewController.showGroupLobbyOrActiveCall()
        GroupCallViewController.presentLobby(thread: thread)
        self.dismiss(animated: false)
    }
}

// MARK: - RecipientContextMenuHelperDelegate

extension NewCallViewController: RecipientContextMenuHelperDelegate {
    private func goToChatAction(thread: TSThread) -> UIAction {
        UIAction(
            title: OWSLocalizedString(
                "NEW_CALL_MESSAGE_ACTION_TITLE",
                comment: "Title for a long-press context menu action to message a given recipient or group, triggered from a recipient in the New Call contact picker"
            ),
            image: Theme.iconImage(.contextMenuMessage)
        ) { [weak self] _ in
            self?.delegate?.goToChat(for: thread)
        }
    }

    private func startVoiceCallAction(thread: TSContactThread) -> UIAction {
        UIAction(
            title: OWSLocalizedString(
                "NEW_CALL_AUDIO_CALL_ACTION_TITLE",
                comment: "Title for a long-press context menu action to start an audio call, triggered from a recipient in the New Call contact picker"
            ),
            image: Theme.iconImage(.contextMenuVoiceCall)
        ) { [weak self] _ in
            self?.startIndividualCall(thread: thread, withVideo: false)
        }
    }

    private func startVideoCallAction(handler: @escaping UIActionHandler) -> UIAction {
        UIAction(
            title: OWSLocalizedString(
                "NEW_CALL_VIDEO_CALL_ACTION_TITLE",
                comment: "Title for a long-press context menu action to start a video call, triggered from a recipient in the New Call contact picker"
            ),
            image: Theme.iconImage(.contextMenuVideoCall),
            handler: handler
        )
    }

    func additionalActions(for address: SignalServiceAddress) -> [UIAction] {
        let thread = TSContactThread.getOrCreateThread(contactAddress: address)
        return [
            goToChatAction(thread: thread),
            startVoiceCallAction(thread: thread),
            startVideoCallAction { [weak self] _ in
                self?.startIndividualCall(thread: thread, withVideo: true)
            },
        ]
    }

    func additionalActions(for groupThread: TSGroupThread) -> [UIAction] {
        [
            goToChatAction(thread: groupThread),
            startVideoCallAction { [weak self] _ in
                self?.startGroupCall(thread: groupThread)
            }
        ]
    }
}

// MARK: - RecipientPickerDelegate

extension NewCallViewController: RecipientPickerDelegate {
    func recipientPicker(_ recipientPickerViewController: SignalUI.RecipientPickerViewController, getRecipientState recipient: SignalUI.PickedRecipient) -> SignalUI.RecipientPickerRecipientState {
        .canBeSelected
    }

    func recipientPicker(_ recipientPickerViewController: SignalUI.RecipientPickerViewController, didSelectRecipient recipient: SignalUI.PickedRecipient) {
        switch recipient.identifier {
        case let .address(address):
            let thread = TSContactThread.getOrCreateThread(contactAddress: address)
            startIndividualCall(thread: thread, withVideo: false)
        case let .group(groupThread):
            startGroupCall(thread: groupThread)
        }
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController, accessoryViewForRecipient recipient: PickedRecipient, transaction: SDSAnyReadTransaction) -> ContactCellAccessoryView? {
        // [CallsTab] TODO: Enable user interaction on ContactCellConfiguration
        // In order for this button to work, ContactCellConfiguration.allowUserInteraction needs to be true.
        // Check before enabling the calls tab feature flag if that hard-coded
        // bool can be flipped or if it needs to be made configurable.
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 20
        stackView.tintColor = Theme.primaryTextColor

        switch recipient.identifier {
        case .address(let address):
            // This doesn't actually need to be hooked up to any action
            // since tapping the row already starts a voice call.
            let voiceCallImageView = UIImageView(image: Theme.iconImage(.buttonVoiceCall))
            let videoCallButton = OWSButton(
                imageName: Theme.iconName(.buttonVideoCall),
                tintColor: nil
            ) { [weak self] in
                let thread = TSContactThread.getOrCreateThread(contactAddress: address)
                self?.startIndividualCall(thread: thread, withVideo: true)
            }
            stackView.addArrangedSubviews([
                voiceCallImageView,
                videoCallButton,
            ])
        case .group(_):
            stackView.addArrangedSubview(UIImageView(image: Theme.iconImage(.buttonVideoCall)))
        }

        return .init(accessoryView: stackView, size: .init(width: 24 * 2 + 20, height: 24))
    }
}
