//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

protocol CameraFirstCaptureDelegate: AnyObject {
    func cameraFirstCaptureSendFlowDidComplete(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow)
    func cameraFirstCaptureSendFlowDidCancel(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow)
}

class CameraFirstCaptureSendFlow {

    private weak var delegate: CameraFirstCaptureDelegate?

    private var approvedAttachments: ApprovedAttachments?
    private var approvedMessageBody: MessageBody?
    private var textAttachment: UnsentTextAttachment?

    private var mentionCandidates: [Aci] = []

    private let selection = ConversationPickerSelection()
    private var selectedConversations: [ConversationItem] { selection.conversations }

    private let storiesOnly: Bool
    private var showsStoriesInPicker = true

    init(storiesOnly: Bool, delegate: CameraFirstCaptureDelegate) {
        self.storiesOnly = storiesOnly
        self.delegate = delegate
    }

    private func updateMentionCandidates() {
        AssertIsOnMainThread()

        guard
            selectedConversations.count == 1,
            case .group(let groupThreadId) = selectedConversations.first?.messageRecipient
        else {
            mentionCandidates = []
            return
        }

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        self.mentionCandidates = databaseStorage.read { tx in
            let groupThread = TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId, transaction: tx)
            owsAssertDebug(groupThread != nil)
            if let groupThread, groupThread.allowsMentionSend {
                return groupThread.recipientAddresses(with: tx).compactMap(\.aci)
            } else {
                return []
            }
        }
    }
}

extension CameraFirstCaptureSendFlow: SendMediaNavDelegate {
    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController) {
        delegate?.cameraFirstCaptureSendFlowDidCancel(self)
    }

    func sendMediaNav(
        _ sendMediaNavigationController: SendMediaNavigationController,
        didApproveAttachments approvedAttachments: ApprovedAttachments,
        messageBody: MessageBody?,
    ) {
        self.approvedAttachments = approvedAttachments
        self.approvedMessageBody = messageBody

        let pickerVC = ConversationPickerViewController(
            selection: selection,
            attachments: approvedAttachments.attachments,
        )
        pickerVC.pickerDelegate = self
        pickerVC.shouldBatchUpdateIdentityKeys = true
        if storiesOnly {
            pickerVC.isStorySectionExpanded = true
            pickerVC.sectionOptions = .storiesOnly
        } else if showsStoriesInPicker {
            pickerVC.sectionOptions.insert(.stories)
        }
        sendMediaNavigationController.pushViewController(pickerVC, animated: true)
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didFinishWithTextAttachment textAttachment: UnsentTextAttachment) {
        self.textAttachment = textAttachment

        let pickerVC = ConversationPickerViewController(selection: selection, textAttachment: textAttachment)
        pickerVC.pickerDelegate = self
        pickerVC.shouldBatchUpdateIdentityKeys = true
        if showsStoriesInPicker || storiesOnly {
            pickerVC.isStorySectionExpanded = true
            pickerVC.sectionOptions = .storiesOnly
        } else {
            owsFailDebug("Shouldn't ever have stories disabled with text attachments!")
        }
        sendMediaNavigationController.pushViewController(pickerVC, animated: true)
    }

    func sendMediaNav(
        _ sendMediaNavigationController: SendMediaNavigationController,
        didChangeMessageBody newMessageBody: MessageBody?,
    ) {
        // Nothing to do -- this is a conversation view feature.
    }

    func sendMediaNav(
        _ sendMediaNavigationController: SendMediaNavigationController,
        didChangeViewOnceState isViewOnce: Bool,
    ) {
        guard !self.storiesOnly else { return }
        // Don't enable view once media to send to stories.
        self.showsStoriesInPicker = !isViewOnce
    }
}

extension CameraFirstCaptureSendFlow: SendMediaNavDataSource {

    func sendMediaNavInitialMessageBody(_ sendMediaNavigationController: SendMediaNavigationController) -> MessageBody? {
        return nil
    }

    var sendMediaNavTextInputContextIdentifier: String? {
        return nil
    }

    var sendMediaNavRecipientNames: [String] {
        selectedConversations.map { $0.titleWithSneakyTransaction }
    }

    func sendMediaNavMentionableAcis(tx: DBReadTransaction) -> [Aci] {
        return mentionCandidates
    }

    func sendMediaNavMentionCacheInvalidationKey() -> String {
        return "\(mentionCandidates.hashValue)"
    }
}

extension CameraFirstCaptureSendFlow: ConversationPickerDelegate {

    public func conversationPickerSelectionDidChange(_ conversationPickerViewController: ConversationPickerViewController) {
        updateMentionCandidates()
    }

    public func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController) {
        if let textAttachment {
            let selectedStoryItems = selectedConversations.filter { $0 is StoryConversationItem }
            guard !selectedStoryItems.isEmpty else {
                owsFailDebug("Selection was unexpectedly empty.")
                delegate?.cameraFirstCaptureSendFlowDidCancel(self)
                return
            }
            Task { @MainActor in
                do {
                    _ = try await AttachmentMultisend.enqueueTextAttachment(textAttachment, to: selectedStoryItems)
                    self.delegate?.cameraFirstCaptureSendFlowDidComplete(self)
                } catch {
                    owsFailDebug("\(error)")
                }
            }
            return
        }
        if let approvedAttachments {
            let approvedMessageBody = self.approvedMessageBody
            let selectedConversations = self.selectedConversations
            Task { @MainActor in
                do {
                    _ = try await AttachmentMultisend.enqueueApprovedMedia(
                        conversations: selectedConversations,
                        approvedMessageBody: approvedMessageBody,
                        approvedAttachments: approvedAttachments
                    )
                    self.delegate?.cameraFirstCaptureSendFlowDidComplete(self)
                } catch {
                    owsFailDebug("\(error)")
                }
            }
            return
        }
        owsFailDebug("completed without anything to send")
        delegate?.cameraFirstCaptureSendFlowDidCancel(self)
    }

    public func conversationPickerCanCancel(_ conversationPickerViewController: ConversationPickerViewController) -> Bool {
        return false
    }

    public func conversationPickerDidCancel(_ conversationPickerViewController: ConversationPickerViewController) {
        owsFailDebug("Camera-first capture flow should never cancel conversation picker.")
    }

    public func approvalMode(_ conversationPickerViewController: ConversationPickerViewController) -> ApprovalMode {
        return .send
    }

    public func conversationPickerDidBeginEditingText() {}

    public func conversationPickerSearchBarActiveDidChange(_ conversationPickerViewController: ConversationPickerViewController) {}
}
