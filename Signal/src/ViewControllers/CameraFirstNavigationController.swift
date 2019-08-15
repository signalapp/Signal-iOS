//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
    var approvalMessageText: String?

    var selectedConversations: [ConversationItem] = []

    // MARK: Dependencies

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    var broadcastMediaMessageJobQueue: BroadcastMediaMessageJobQueue {
        return AppEnvironment.shared.broadcastMediaMessageJobQueue
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

    var sendMediaNavCanSaveAttachments: Bool {
        return true
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

        let conversations = selectedConversationsForConversationPicker
        DispatchQueue.global().async(.promise) {
            // Duplicate attachments per conversation
            let conversationAttachments: [(ConversationItem, [SignalAttachment])] =
                try conversations.map { conversation in
                    return (conversation, try approvedAttachments.map { try $0.cloneAttachment() })
                }

            // We only upload one set of attachments, and then copy the upload details into
            // each conversation before sending.
            let attachmentsToUpload: [OutgoingAttachmentInfo] = approvedAttachments.map { attachment in
                return OutgoingAttachmentInfo(dataSource: attachment.dataSource,
                                              contentType: attachment.mimeType,
                                              sourceFilename: attachment.filenameOrDefault,
                                              caption: attachment.captionText,
                                              albumMessageId: nil)
            }

            self.databaseStorage.write { transaction in
                var messages: [TSOutgoingMessage] = []

                for (conversation, attachments) in conversationAttachments {
                    let thread: TSThread
                    switch conversation.messageRecipient {
                    case .contact(let address):
                        thread = TSContactThread.getOrCreateThread(withContactAddress: address,
                                                                   transaction: transaction)
                    case .group(let groupThread):
                        thread = groupThread
                    }

                    let message = try! ThreadUtil.createUnsentMessage(withText: self.approvalMessageText,
                                                                      mediaAttachments: attachments,
                                                                      in: thread,
                                                                      quotedReplyModel: nil,
                                                                      linkPreviewDraft: nil,
                                                                      transaction: transaction)
                    messages.append(message)
                }

                // map of attachments we'll upload to their copies in each recipient thread
                var attachmentIdMap: [String: [String]] = [:]
                let correspondingAttachmentIds = transpose(messages.map { $0.attachmentIds })
                for (index, attachmentInfo) in attachmentsToUpload.enumerated() {
                    do {
                        let attachmentToUpload = try attachmentInfo.asStreamConsumingDataSource(withIsVoiceMessage: false)
                        attachmentToUpload.anyInsert(transaction: transaction)

                        attachmentIdMap[attachmentToUpload.uniqueId] = correspondingAttachmentIds[index]
                    } catch {
                        owsFailDebug("error: \(error)")
                    }
                }

                self.broadcastMediaMessageJobQueue.add(attachmentIdMap: attachmentIdMap,
                                                       transaction: transaction)
            }
        }.done { _ in
            self.delegate?.cameraFirstCaptureSendFlowDidComplete(self)
        }.retainUntilComplete()
    }
}
