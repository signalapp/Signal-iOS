//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

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
    var selectedConversations: [ConversationItem] = [] {
        didSet {
            updateMentionCandidates()
        }
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
            mentionCandidates = groupThread.recipientAddresses
        } else {
            mentionCandidates = []
        }
    }
}

extension CameraFirstCaptureSendFlow: SendMediaNavDelegate {
    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController) {
        delegate?.cameraFirstCaptureSendFlowDidCancel(self)
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didApproveAttachments attachments: [SignalAttachment], messageBody: MessageBody?) {
        self.approvedAttachments = attachments
        self.approvalMessageBody = messageBody

        let pickerVC = ConversationPickerViewController()
        pickerVC.delegate = self
        sendMediaNavigationController.pushViewController(pickerVC, animated: true)
    }

    func sendMediaNavInitialMessageBody(_ sendMediaNavigationController: SendMediaNavigationController) -> MessageBody? {
        return approvalMessageBody
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeMessageBody newMessageBody: MessageBody?) {
        self.approvalMessageBody = newMessageBody
    }

    var sendMediaNavApprovalButtonImageName: String {
        return "arrow-right-24"
    }

    var sendMediaNavCanSaveAttachments: Bool {
        return true
    }

    var sendMediaNavTextInputContextIdentifier: String? {
        return nil
    }

    var sendMediaNavRecipientNames: [String] {
        return selectedConversations.map { $0.title }
    }

    var sendMediaNavMentionableAddresses: [SignalServiceAddress] {
        mentionCandidates
    }
}

extension CameraFirstCaptureSendFlow: ConversationPickerDelegate {
    public var selectedConversationsForConversationPicker: [ConversationItem] {
        return selectedConversations
    }

    public func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didSelectConversation conversation: ConversationItem) {
        self.selectedConversations.append(conversation)
    }

    public func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didDeselectConversation conversation: ConversationItem) {
        self.selectedConversations = self.selectedConversations.filter {
            $0.messageRecipient != conversation.messageRecipient
        }
    }

    public func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController) {
        guard let approvedAttachments = self.approvedAttachments else {
            owsFailDebug("approvedAttachments was unexpectedly nil")
            delegate?.cameraFirstCaptureSendFlowDidCancel(self)
            return
        }

        let conversations = selectedConversationsForConversationPicker
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

    public var conversationPickerHasTextInput: Bool { false }

    public var conversationPickerTextInputDefaultText: String? { nil }

    public func conversationPickerSearchBarActiveDidChange(_ conversationPickerViewController: ConversationPickerViewController) {}
}
