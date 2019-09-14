//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
    var approvalMessageText: String?

    var selectedConversations: [ConversationItem] = []

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }
}

extension CameraFirstCaptureSendFlow: SendMediaNavDelegate {
    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController) {
        delegate?.cameraFirstCaptureSendFlowDidCancel(self)
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didApproveAttachments attachments: [SignalAttachment], messageText: String?) {
        self.approvedAttachments = attachments
        self.approvalMessageText = messageText

        let pickerVC = ConversationPickerViewController()
        pickerVC.delegate = self
        sendMediaNavigationController.pushViewController(pickerVC, animated: true)
    }

    func sendMediaNavInitialMessageText(_ sendMediaNavigationController: SendMediaNavigationController) -> String? {
        return approvalMessageText
    }

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeMessageText newMessageText: String?) {
        self.approvalMessageText = newMessageText
    }

    var sendMediaNavApprovalButtonImageName: String {
        return "arrow-right-24"
    }
}

extension CameraFirstCaptureSendFlow: ConversationPickerDelegate {
    var selectedConversationsForConversationPicker: [ConversationItem] {
        return selectedConversations
    }

    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didSelectConversation conversation: ConversationItem) {
        self.selectedConversations.append(conversation)
    }

    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didDeselectConversation conversation: ConversationItem) {
        self.selectedConversations = self.selectedConversations.filter {
            $0.messageRecipient != conversation.messageRecipient
        }
    }

    func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController) {
        guard let approvedAttachments = self.approvedAttachments else {
            owsFailDebug("approvedAttachments was unexpectedly nil")
            delegate?.cameraFirstCaptureSendFlowDidCancel(self)
            return
        }

        // CAMERAFIRST TODO batch sends with a single attachment upload.
        databaseStorage.write { transaction in
            for conversation in self.selectedConversationsForConversationPicker {
                let thread: TSThread
                switch conversation.messageRecipient {
                case .contact(let address):
                    thread = TSContactThread.getOrCreateThread(withContactAddress: address,
                                                               transaction: transaction)
                case .group(let groupThread):
                    thread = groupThread
                }
                ThreadUtil.enqueueMessage(withText: self.approvalMessageText,
                                          mediaAttachments: approvedAttachments,
                                          in: thread,
                                          quotedReplyModel: nil,
                                          linkPreviewDraft: nil,
                                          transaction: transaction)
            }
        }

        self.delegate?.cameraFirstCaptureSendFlowDidComplete(self)
    }
}
