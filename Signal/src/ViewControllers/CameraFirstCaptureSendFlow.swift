//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

protocol CameraFirstCaptureDelegate: AnyObject {
    func cameraFirstCaptureSendFlowDidComplete(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow)
    func cameraFirstCaptureSendFlowDidCancel(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow)
}

class CameraFirstCaptureSendFlow: Dependencies {

    private weak var delegate: CameraFirstCaptureDelegate?

    private var approvedAttachments: [SignalAttachment]?
    private var approvalMessageBody: MessageBody?
    private var textAttachment: UnsentTextAttachment?

    private var mentionCandidates: [SignalServiceAddress] = []

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

        guard selectedConversations.count == 1,
              case .group(let groupThreadId) = selectedConversations.first?.messageRecipient else {
            mentionCandidates = []
            return
        }

        let groupThread = databaseStorage.read { readTx in
            TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId, transaction: readTx)
        }

        owsAssertDebug(groupThread != nil)
        if let groupThread = groupThread, groupThread.allowsMentionSend {
            mentionCandidates = groupThread.recipientAddressesWithSneakyTransaction
        } else {
            mentionCandidates = []
        }
    }
}

extension CameraFirstCaptureSendFlow: SendMediaNavDelegate {

    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController) {
        // Restore status bar visibility (if current VC hides it) so that
        // there's no visible UI updates in the presenter.
        if sendMediaNavigationController.topViewController?.prefersStatusBarHidden ?? false {
            sendMediaNavigationController.modalPresentationCapturesStatusBarAppearance = false
            sendMediaNavigationController.setNeedsStatusBarAppearanceUpdate()
        }
        delegate?.cameraFirstCaptureSendFlowDidCancel(self)
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didApproveAttachments attachments: [SignalAttachment], messageBody: MessageBody?) {
        self.approvedAttachments = attachments
        self.approvalMessageBody = messageBody

        let pickerVC = ConversationPickerViewController(
            selection: selection,
            attachments: attachments
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

        let pickerVC = ConversationPickerViewController(selection: selection, textAttacment: textAttachment)
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

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeMessageBody newMessageBody: MessageBody?) {
        self.approvalMessageBody = newMessageBody
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeViewOnceState isViewOnce: Bool) {
        guard !self.storiesOnly else { return }
        // Don't enable view once media to send to stories.
        self.showsStoriesInPicker = !isViewOnce
    }
}

extension CameraFirstCaptureSendFlow: SendMediaNavDataSource {

    func sendMediaNavInitialMessageBody(_ sendMediaNavigationController: SendMediaNavigationController) -> MessageBody? {
        return approvalMessageBody
    }

    var sendMediaNavTextInputContextIdentifier: String? {
        nil
    }

    var sendMediaNavRecipientNames: [String] {
        selectedConversations.map { $0.titleWithSneakyTransaction }
    }

    func sendMediaNavMentionableAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] {
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
        if let textAttachment = textAttachment {
            let selectedStoryItems = selectedConversations.filter { $0 is StoryConversationItem }
            guard !selectedStoryItems.isEmpty else {
                owsFailDebug("Selection was unexpectedly empty.")
                delegate?.cameraFirstCaptureSendFlowDidCancel(self)
                return
            }

            firstly {
                AttachmentMultisend.sendTextAttachment(textAttachment, to: selectedStoryItems)
            }.done { _ in
                self.delegate?.cameraFirstCaptureSendFlowDidComplete(self)
            }.catch { error in
                owsFailDebug("Error: \(error)")
            }

            return
        }

        guard let approvedAttachments = self.approvedAttachments else {
            owsFailDebug("approvedAttachments was unexpectedly nil")
            delegate?.cameraFirstCaptureSendFlowDidCancel(self)
            return
        }

        let conversations = selectedConversations
        firstly {
            AttachmentMultisend.sendApprovedMedia(conversations: conversations,
                                                  approvalMessageBody: self.approvalMessageBody,
                                                  approvedAttachments: approvedAttachments)
        }.done { _ in
            self.delegate?.cameraFirstCaptureSendFlowDidComplete(self)
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
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
