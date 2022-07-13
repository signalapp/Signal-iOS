//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol CameraFirstCaptureDelegate: AnyObject {
    func cameraFirstCaptureSendFlowDidComplete(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow)
    func cameraFirstCaptureSendFlowDidCancel(_ cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow)
}

@objc
public class CameraFirstCaptureSendFlow: NSObject {
    @objc
    public weak var delegate: CameraFirstCaptureDelegate?

    var approvedAttachments: [SignalAttachment]?
    var approvalMessageBody: MessageBody?

    var mentionCandidates: [SignalServiceAddress] = []

    private let selection = ConversationPickerSelection()
    var selectedConversations: [ConversationItem] { selection.conversations }

    private let storiesOnly: Bool
    public init(storiesOnly: Bool) {
        self.storiesOnly = storiesOnly
        super.init()
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
        if let groupThread = groupThread, Mention.threadAllowsMentionSend(groupThread) {
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

        let pickerVC = ConversationPickerViewController(selection: selection)
        pickerVC.pickerDelegate = self
        if storiesOnly {
            pickerVC.isStorySectionExpanded = true
            pickerVC.sectionOptions = .stories
        } else {
            pickerVC.sectionOptions.insert(.stories)
        }
        sendMediaNavigationController.pushViewController(pickerVC, animated: true)
    }

    func sendMediaNavInitialMessageBody(_ sendMediaNavigationController: SendMediaNavigationController) -> MessageBody? {
        return approvalMessageBody
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeMessageBody newMessageBody: MessageBody?) {
        self.approvalMessageBody = newMessageBody
    }

    var sendMediaNavTextInputContextIdentifier: String? {
        return nil
    }

    var sendMediaNavRecipientNames: [String] {
        selectedConversations.map { $0.titleWithSneakyTransaction }
    }

    var sendMediaNavMentionableAddresses: [SignalServiceAddress] {
        mentionCandidates
    }
}

// MARK: -

extension CameraFirstCaptureSendFlow: ConversationPickerDelegate {
    public func conversationPickerSelectionDidChange(_ conversationPickerViewController: ConversationPickerViewController) {
        updateMentionCandidates()
    }

    public func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController) {
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
