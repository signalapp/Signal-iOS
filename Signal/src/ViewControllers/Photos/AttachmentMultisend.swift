//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

class AttachmentMultisend {

    // MARK: Dependencies

    class var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    class var broadcastMediaMessageJobQueue: BroadcastMediaMessageJobQueue {
        return AppEnvironment.shared.broadcastMediaMessageJobQueue
    }

    // MARK: -

    class func sendApprovedMedia(conversations: [ConversationItem],
                                 approvalMessageText: String?,
                                 approvedAttachments: [SignalAttachment]) -> Promise<[TSThread]> {
        return DispatchQueue.global().async(.promise) {
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
                                              albumMessageId: nil,
                                              isBorderless: attachment.isBorderless)
            }

            var threads: [TSThread] = []
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

                    // If this thread has a pending message request, treat it as accepted.
                    ThreadUtil.addThread(toProfileWhitelistIfEmptyOrPendingRequest: thread, transaction: transaction)

                    let message = try! ThreadUtil.createUnsentMessage(withText: approvalMessageText,
                                                                      mediaAttachments: attachments,
                                                                      thread: thread,
                                                                      quotedReplyModel: nil,
                                                                      linkPreviewDraft: nil,
                                                                      transaction: transaction)
                    messages.append(message)
                    threads.append(thread)
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
            return threads
        }
    }
}
