//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import PromiseKit

//@objc
//public class ForwardMessageAction: NSObject, MessageAction {
//    private weak var delegate: MessageActionsDelegate?
//    private let message: TSMessage
//    private let conversationViewItem: ConversationViewItem
//
//    @objc
//    public required init(delegate: MessageActionsDelegate,
//                         message: TSMessage,
//                         conversationViewItem: ConversationViewItem) {
//        self.delegate = delegate
//        self.message = message
//        self.conversationViewItem = conversationViewItem
//
//        super.init()
//
//        delegate.messageActionDidStart(self)
//    }
//
////    @objc
////    public func showUI() {
////        ForwardMessageNavigationController *cameraModal =
////            [ForwardMessageNavigationController captureFirstCameraModal];
////        cameraModal.forwardMessageFlow.delegate = self;
////
////        [self presentFullScreenViewController:cameraModal animated:YES completion:nil];
////
//////        let pickerVC = ConversationPickerViewController()
//////        pickerVC.delegate = self
//////        sendMediaNavigationController.pushViewController(pickerVC, animated: true)
////    }
//
//}

// MARK: -

//@objc
//class ForwardMessageNavigationController: SendMediaNavigationController {
//    
//    @objc
//    private(set) var forwardMessageFlow: ForwardMessageFlow!
//    
//    @objc
//    public class func captureFirstCameraModal() -> ForwardMessageNavigationController {
//        let navController = ForwardMessageNavigationController()
//        navController.setViewControllers([navController.captureViewController], animated: false)
//        
//        let forwardMessageFlow = ForwardMessageFlow()
//        navController.forwardMessageFlow = forwardMessageFlow
//        navController.sendMediaNavDelegate = forwardMessageFlow
//        
//        return navController
//    }
//}

@objc
public protocol ForwardMessageDelegate: AnyObject {
    @objc(forwardMessageFlowDidComplete:)
    func forwardMessageFlowDidComplete(threads: [TSThread])
    func forwardMessageFlowDidCancel()
}

// MARK: -

//@objc
//public class ForwardMessageFlow: NSObject {
//    @objc
//    public weak var delegate: ForwardMessageDelegate?
//
//    var approvedAttachments: [SignalAttachment]?
//    var approvalMessageText: String?
//
//    var selectedConversations: [ConversationItem] = []
//
//    // MARK: Dependencies
//
//    var databaseStorage: SDSDatabaseStorage {
//        return SSKEnvironment.shared.databaseStorage
//    }
//
//    var broadcastMediaMessageJobQueue: BroadcastMediaMessageJobQueue {
//        return AppEnvironment.shared.broadcastMediaMessageJobQueue
//    }
//}

// MARK: - Approval

extension ForwardMessageNavigationController {
    private var needsApproval: Bool {
        switch conversationViewItem.messageCellType {
        case .textOnlyMessage:
            return true
        case .contactShare:
            return true
        case .audio,
             .genericAttachment:
            return false
        case .mediaMessage:
            return true
        case .unknown,
             .oversizeTextDownloading,
             .stickerMessage,
             .viewOnce:
            return false
        }
    }

    private func buildOutgoingMessage(for thread: TSThread,
                                      transaction: SDSAnyWriteTransaction) throws -> TSOutgoingMessage {
        switch conversationViewItem.messageCellType {
//        case .textOnlyMessage:
//            guard let body = message.body,
//                body.count > 0 else {
//                    throw OWSAssertionError("Missing body.")
//            }
//            return TSOutgoingMessage(in: thread, messageBody: body, attachmentId: nil)
        case .contactShare:
            throw OWSAssertionError("Invalid message.")
            //            guard let contactShareViewModel = conversationViewItem.contactShare
            //            ContactShareViewModel *contactShare
            //            OWSFailDebug(@"Invalid cell type.");
            //            break;
            //            TSOutgoingMessage(
            //            - (instancetype)initOutgoingMessageWithTimestamp:(uint64_t)timestamp
            //            inThread:(TSThread *)thread
            //            messageBody:(nullable NSString *)body
            //            attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
            //            expiresInSeconds:(uint32_t)expiresInSeconds
            //            expireStartedAt:(uint64_t)expireStartedAt
            //            isVoiceMessage:(BOOL)isVoiceMessage
            //            groupMetaMessage:(TSGroupMetaMessage)groupMetaMessage
            //            quotedMessage:(nullable TSQuotedMessage *)quotedMessage
            //            contactShare:(nullable OWSContact *)contactShare
            //            linkPreview:(nullable OWSLinkPreview *)linkPreview
            //            messageSticker:(nullable MessageSticker *)messageSticker
            //            isViewOnceMessage:(BOOL)isViewOnceMessage NS_DESIGNATED_INITIALIZER;
            //        case .audio, .genericAttachment:
            //            guard let attachmentStream = conversationViewItem.attachmentStream else {
            //                throw OWSAssertionError("Missing attachmentStream.")
            //            }
            //        case OWSMessageCellType_GenericAttachment:
            //            OWSFailDebug(@"Invalid cell type.");
            //            break;
            //        //          return self.attachmentStream != nil;
            //        case OWSMessageCellType_MediaMessage:
            //            OWSFailDebug(@"Invalid cell type.");
            //            break;
            //        //            return [self canSaveMedia];
            //        case OWSMessageCellType_Unknown:
            //        case OWSMessageCellType_OversizeTextDownloading:
            //        case OWSMessageCellType_StickerMessage:
            //        case OWSMessageCellType_ViewOnce:
            //            OWSFailDebug(@"Invalid cell type.");
        //            break;
        default:
            throw OWSAssertionError("Invalid cell type.")

        }
    }

}

// MARK: - Approval

extension ForwardMessageNavigationController {

    func approve() {
        do {
            try showApprovalUI()
        } catch {
            owsFailDebug("Error: \(error)")

            self.forwardMessageDelegate?.forwardMessageFlowDidCancel()
        }
    }

    func showApprovalUI() throws {
        switch conversationViewItem.messageCellType {
        case .textOnlyMessage:
            guard let body = approvalMessageText,
                body.count > 0 else {
                    throw OWSAssertionError("Missing body.")
            }

            let approvalView = TextApprovalViewController(messageText: body)
            approvalView.delegate = self
            self.pushViewController(approvalView, animated: true)
        case .contactShare:
            throw OWSAssertionError("Invalid message type.")
        case .audio,
             .genericAttachment,
             .stickerMessage:
            // Skip approval for these message types.
            send()
        case .mediaMessage:
            throw OWSAssertionError("Invalid message type.")
        case .unknown,
             .oversizeTextDownloading,
             .viewOnce:
            throw OWSAssertionError("Invalid message type.")
        }
    }
}

// MARK: - Sending

extension ForwardMessageNavigationController {

    func send() {
        do {
            try tryToSend()
        } catch {
            owsFailDebug("Error: \(error)")

            self.forwardMessageDelegate?.forwardMessageFlowDidCancel()
        }
    }

    func tryToSend() throws {
        switch conversationViewItem.messageCellType {
        case .textOnlyMessage:
            guard let body = approvalMessageText,
                body.count > 0 else {
                    throw OWSAssertionError("Missing body.")
            }

            send { (thread, transaction) in
                self.send(body: body, thread: thread, transaction: transaction)
            }
        case .contactShare:
            throw OWSAssertionError("Invalid message type.")
        case .audio,
             .genericAttachment,
             .stickerMessage:
            throw OWSAssertionError("Invalid message type.")
        case .mediaMessage:
            throw OWSAssertionError("Invalid message type.")
        case .unknown,
             .oversizeTextDownloading,
             .viewOnce:
            throw OWSAssertionError("Invalid message type.")
        }
    }

//    func tryToSend() throws {
//        guard let approvedAttachments = self.approvedAttachments else {
//            throw OWSAssertionError("Missing attachments.")
//        }
//
//        let conversations = selectedConversationsForConversationPicker
//
//        DispatchQueue.global().async(.promise) {
//            // Duplicate attachments per conversation
//            let conversationAttachments: [(ConversationItem, [SignalAttachment])] =
//                try conversations.map { conversation in
//                    return (conversation, try approvedAttachments.map { try $0.cloneAttachment() })
//            }
//
//            // We only upload one set of attachments, and then copy the upload details into
//            // each conversation before sending.
//            let attachmentsToUpload: [OutgoingAttachmentInfo] = approvedAttachments.map { attachment in
//                return OutgoingAttachmentInfo(dataSource: attachment.dataSource,
//                                              contentType: attachment.mimeType,
//                                              sourceFilename: attachment.filenameOrDefault,
//                                              caption: attachment.captionText,
//                                              albumMessageId: nil)
//            }
//
//            self.databaseStorage.write { transaction in
//                var messages: [TSOutgoingMessage] = []
//
//                for (conversation, attachments) in conversationAttachments {
//                    let thread: TSThread
//                    switch conversation.messageRecipient {
//                    case .contact(let address):
//                        thread = TSContactThread.getOrCreateThread(withContactAddress: address,
//                                                                   transaction: transaction)
//                    case .group(let groupThread):
//                        thread = groupThread
//                    }
//
//                    let message = try! ThreadUtil.createUnsentMessage(withText: self.approvalMessageText,
//                                                                      mediaAttachments: attachments,
//                                                                      in: thread,
//                                                                      quotedReplyModel: nil,
//                                                                      linkPreviewDraft: nil,
//                                                                      transaction: transaction)
//                    messages.append(message)
//                }
//
//                // map of attachments we'll upload to their copies in each recipient thread
//                var attachmentIdMap: [String: [String]] = [:]
//                let correspondingAttachmentIds = transpose(messages.map { $0.attachmentIds })
//                for (index, attachmentInfo) in attachmentsToUpload.enumerated() {
//                    do {
//                        let attachmentToUpload = try attachmentInfo.asStreamConsumingDataSource(withIsVoiceMessage: false)
//                        attachmentToUpload.anyInsert(transaction: transaction)
//
//                        attachmentIdMap[attachmentToUpload.uniqueId] = correspondingAttachmentIds[index]
//                    } catch {
//                        owsFailDebug("error: \(error)")
//                    }
//                }
//
//                self.broadcastMediaMessageJobQueue.add(attachmentIdMap: attachmentIdMap,
//                                                       transaction: transaction)
//            }
//            }.done { _ in
//                self.forwardMessageDelegate?.forwardMessageFlowDidComplete()
//            }.retainUntilComplete()
//    }

    func send(body: String, thread: TSThread, transaction: SDSAnyWriteTransaction) {
        let outgoingMessagePreparer = OutgoingMessagePreparer(fullMessageText: body, mediaAttachments: [], thread: thread, quotedReplyModel: nil, transaction: transaction)
////            [[OutgoingMessagePreparer alloc] initWithFullMessageText:fullMessageText
////                mediaAttachments:mediaAttachments
////                thread:thread
////                quotedReplyModel:quotedReplyModel
////                transaction:transaction];
//        
//        [BenchManager benchAsyncWithTitle:@"Saving outgoing message"
//            block:^(void (^benchmarkCompletion)(void)) {
//            [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *writeTransaction) {
        outgoingMessagePreparer.insertMessage(linkPreviewDraft: nil, transaction: transaction)
        messageSenderJobQueue.add(message: outgoingMessagePreparer, transaction: transaction)
//            [outgoingMessagePreparer insertMessageWithLinkPreviewDraft:linkPreviewDraft transaction:writeTransaction];
//            [self.messageSenderJobQueue addMessage:outgoingMessagePreparer transaction:writeTransaction];
//            }
//
//        let (promise, resolver) = Promise<Void>.pending()
////        ThreadUtil.sendMessageNonDurably(text: <#T##String#>, thread: <#T##TSThread#>, quotedReplyModel: <#T##OWSQuotedReplyModel?#>, messageSender: <#T##MessageSender#>)
////        ThreadUtil.sendMessageNonDurably(withContactShare: <#T##OWSContact#>, in: <#T##TSThread#>, messageSender: <#T##MessageSender#>, completion: <#T##(Error?) -> Void#>)
////        ThreadUtil.sendMessageNonDurably(withText: <#T##String#>, in: <#T##TSThread#>, quotedReplyModel: <#T##OWSQuotedReplyModel?#>, transaction: <#T##SDSAnyReadTransaction#>, messageSender: <#T##MessageSender#>, completion: <#T##(Error?) -> Void#>)
////        ThreadUtil.sendMessageNonDurably(withText: String, mediaAttachments: <#T##[SignalAttachment]#>, in: <#T##TSThread#>, quotedReplyModel: <#T##OWSQuotedReplyModel?#>, transaction: <#T##SDSAnyReadTransaction#>, messageSender: <#T##MessageSender#>, completion: <#T##(Error?) -> Void#>)
//        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
//            outgoingMessage = [ThreadUtil sendMessageNonDurablyWithText:messageText
//            mediaAttachments:attachments
//            inThread:self.thread
//            quotedReplyModel:nil
//            transaction:transaction
//            messageSender:self.messageSender
//            completion:^(NSError *_Nullable error) {
//            sendCompletion(error, outgoingMessage);
//            }];
//            }];
//        return promise
    }

    func send(enqueueBlock: @escaping (TSThread, SDSAnyWriteTransaction) -> Void) {
        AssertIsOnMainThread()

        let conversations = selectedConversationsForConversationPicker

        DispatchQueue.global().async(.promise) {
            guard conversations.count > 0 else {
                throw OWSAssertionError("No recipients.")
            }

//            var messages: [TSOutgoingMessage] = []
                        var threads: [TSThread] = []

            self.databaseStorage.write { transaction in
                for conversation in conversations {
                    let thread: TSThread
                    switch conversation.messageRecipient {
                    case .contact(let address):
                        thread = TSContactThread.getOrCreateThread(withContactAddress: address,
                                                                   transaction: transaction)
                    case .group(let groupThread):
                        thread = groupThread
                    }

                    enqueueBlock(thread, transaction)
                    threads.append(thread)
                }
            }

//                let preparer: OutgoingMessagePreparer = block(thread, transaction)
//                let message = block(thread, transaction)
//
//                OutgoingMessagePreparer *outgoingMessagePreparer =
//                    [[OutgoingMessagePreparer alloc] initWithFullMessageText:fullMessageText
//                        mediaAttachments:mediaAttachments
//                        thread:thread
//                        quotedReplyModel:quotedReplyModel
//                        transaction:transaction];
//
//                [BenchManager benchAsyncWithTitle:@"Saving outgoing message"
//                    block:^(void (^benchmarkCompletion)(void)) {
//                    [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *writeTransaction) {
//                    [outgoingMessagePreparer insertMessageWithLinkPreviewDraft:linkPreviewDraft transaction:writeTransaction];
//                    [self.messageSenderJobQueue addMessage:outgoingMessagePreparer transaction:writeTransaction];
//                    }
//                    completion:benchmarkCompletion];
//                    }];
//
//                return outgoingMessagePreparer.unpreparedMessage;
//
//
//                outgoingMessage = [ThreadUtil sendMessageNonDurablyWithText:messageText
//                    mediaAttachments:attachments
//                    inThread:self.thread
//                    quotedReplyModel:nil
//                    transaction:transaction
//                    messageSender:self.messageSender
//                    completion:^(NSError *_Nullable error) {
//                    sendCompletion(error, outgoingMessage);
//                    }];
//
////                let message = try! ThreadUtil.createUnsentMessage(withText: self.approvalMessageText,
////                                                                  mediaAttachments: attachments,
////                                                                  in: thread,
////                                                                  quotedReplyModel: nil,
////                                                                  linkPreviewDraft: nil,
////                                                                  transaction: transaction)
//                messages.append(message)
//            }
//
//            // map of attachments we'll upload to their copies in each recipient thread
//            var attachmentIdMap: [String: [String]] = [:]
//            let correspondingAttachmentIds = transpose(messages.map { $0.attachmentIds })
//            for (index, attachmentInfo) in attachmentsToUpload.enumerated() {
//                do {
//                    let attachmentToUpload = try attachmentInfo.asStreamConsumingDataSource(withIsVoiceMessage: false)
//                    attachmentToUpload.anyInsert(transaction: transaction)
//
//                    attachmentIdMap[attachmentToUpload.uniqueId] = correspondingAttachmentIds[index]
//                } catch {
//                    owsFailDebug("error: \(error)")
//                }
//            }
//
//            self.broadcastMediaMessageJobQueue.add(attachmentIdMap: attachmentIdMap,
//                                                   transaction: transaction)
//
//            for
//
//            [ThreadUtil addThreadToProfileWhitelistIfEmptyThreadWithSneakyTransaction:self.thread];
//            [self
//                tryToSendMessageWithBlock:^(SendCompletionBlock sendCompletion) {
//                OWSAssertIsOnMainThread();
//
//                __block TSOutgoingMessage *outgoingMessage = nil;
//                // DURABLE CLEANUP - SAE uses non-durable sending to make sure the app is running long enough to complete
//                // the sending operation. Alternatively, we could use a durable send, but do more to make sure the
//                // SAE runs as long as it needs.
//                // TODO ALBUMS - send album via SAE
//
//                [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
//                outgoingMessage = [ThreadUtil sendMessageNonDurablyWithText:messageText
//                mediaAttachments:attachments
//                inThread:self.thread
//                quotedReplyModel:nil
//                transaction:transaction
//                messageSender:self.messageSender
//                completion:^(NSError *_Nullable error) {
//                sendCompletion(error, outgoingMessage);
//                }];
//                }];
//
//                // This is necessary to show progress.
//                self.outgoingMessage = outgoingMessage;
//                }
//                fromViewController:attachmentApproval];
//        }
//
//
//
//
//            - (void)tryToSendMessageWithBlock:(SendMessageBlock)sendMessageBlock
//        fromViewController:(UIViewController *)fromViewController
//        {
//            // Reset progress in case we're retrying
//            self.progressView.progress = 0;
//
//            NSString *progressTitle = NSLocalizedString(@"SHARE_EXTENSION_SENDING_IN_PROGRESS_TITLE", @"Alert title");
//            UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:progressTitle
//                message:nil
//                preferredStyle:UIAlertControllerStyleAlert];
//
//            UIAlertAction *progressCancelAction = [UIAlertAction actionWithTitle:[CommonStrings cancelButton]
//                style:UIAlertActionStyleCancel
//                handler:^(UIAlertAction *_Nonnull action) {
//                [self.shareViewDelegate shareViewWasCancelled];
//                }];
//            [progressAlert addAction:progressCancelAction];
//
//
//            // We add a progress subview to an AlertController, which is a total hack.
//            // ...but it looks good, and given how short a progress view is and how
//            // little the alert controller changes, I'm not super worried about it.
//            [progressAlert.view addSubview:self.progressView];
//            [self.progressView autoPinWidthToSuperviewWithMargin:24];
//            [self.progressView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:progressAlert.view withOffset:4];
//            #ifdef DEBUG
//            if (@available(iOS 14, *)) {
//                // TODO: Congratulations! You survived to see another iOS release.
//                OWSFailDebug(@"Make sure the progress view still looks good, and increment the version canary.");
//}
//#endif
//
//SendCompletionBlock sendCompletion = ^(NSError *_Nullable error, TSOutgoingMessage *message) {
//
//    dispatch_async(dispatch_get_main_queue(), ^{
//        if (error) {
//            [fromViewController
//                dismissViewControllerAnimated:YES
//                completion:^{
//                OWSLogInfo(@"Sending message failed with error: %@", error);
//                [self showSendFailureAlertWithError:error
//                message:message
//                fromViewController:fromViewController];
//                }];
//            return;
//        }
//
//        OWSLogInfo(@"Sending message succeeded.");
//        [self.shareViewDelegate shareViewWasCompleted];
//        });
//};
//
//[fromViewController presentAlert:progressAlert
//    completion:^{
//    sendMessageBlock(sendCompletion);
//    }];
//}
//            // Duplicate attachments per conversation
//            let conversationAttachments: [(ConversationItem, [SignalAttachment])] =
//                try conversations.map { conversation in
//                    return (conversation, try approvedAttachments.map { try $0.cloneAttachment() })
//            }
//
//            // We only upload one set of attachments, and then copy the upload details into
//            // each conversation before sending.
//            let attachmentsToUpload: [OutgoingAttachmentInfo] = approvedAttachments.map { attachment in
//                return OutgoingAttachmentInfo(dataSource: attachment.dataSource,
//                                              contentType: attachment.mimeType,
//                                              sourceFilename: attachment.filenameOrDefault,
//                                              caption: attachment.captionText,
//                                              albumMessageId: nil)
//            }
//
//            self.databaseStorage.write { transaction in
//                var messages: [TSOutgoingMessage] = []
//
//                for (conversation, attachments) in conversationAttachments {
//                    let thread: TSThread
//                    switch conversation.messageRecipient {
//                    case .contact(let address):
//                        thread = TSContactThread.getOrCreateThread(withContactAddress: address,
//                                                                   transaction: transaction)
//                    case .group(let groupThread):
//                        thread = groupThread
//                    }
//
//                    let message = try! ThreadUtil.createUnsentMessage(withText: self.approvalMessageText,
//                                                                      mediaAttachments: attachments,
//                                                                      in: thread,
//                                                                      quotedReplyModel: nil,
//                                                                      linkPreviewDraft: nil,
//                                                                      transaction: transaction)
//                    messages.append(message)
//                }
//
//                // map of attachments we'll upload to their copies in each recipient thread
//                var attachmentIdMap: [String: [String]] = [:]
//                let correspondingAttachmentIds = transpose(messages.map { $0.attachmentIds })
//                for (index, attachmentInfo) in attachmentsToUpload.enumerated() {
//                    do {
//                        let attachmentToUpload = try attachmentInfo.asStreamConsumingDataSource(withIsVoiceMessage: false)
//                        attachmentToUpload.anyInsert(transaction: transaction)
//
//                        attachmentIdMap[attachmentToUpload.uniqueId] = correspondingAttachmentIds[index]
//                    } catch {
//                        owsFailDebug("error: \(error)")
//                    }
//                }
//
//                self.broadcastMediaMessageJobQueue.add(attachmentIdMap: attachmentIdMap,
//                                                       transaction: transaction)
//            }
                return threads
            }.done { threads in
                self.forwardMessageDelegate?.forwardMessageFlowDidComplete(threads: threads)
            }.retainUntilComplete()
    }
}

////
////  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
////
//
//import Foundation
//import PromiseKit
//
//@objc
//public protocol CameraFirstCaptureDelegate: AnyObject {
//    func forwardMessageFlowDidComplete(_ forwardMessageFlow: ForwardMessageFlow)
//    func forwardMessageFlowDidCancel(_ forwardMessageFlow: ForwardMessageFlow)
//}

//extension ForwardMessageFlow: SendMediaNavDelegate {
//    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController) {
//        delegate?.forwardMessageFlowDidCancel(self)
//    }
//
//    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didApproveAttachments attachments: [SignalAttachment], messageText: String?) {
//        self.approvedAttachments = attachments
//        self.approvalMessageText = messageText
//
//        let pickerVC = ConversationPickerViewController()
//        pickerVC.delegate = self
//        sendMediaNavigationController.pushViewController(pickerVC, animated: true)
//    }
//
//    func sendMediaNavInitialMessageText(_ sendMediaNavigationController: SendMediaNavigationController) -> String? {
//        return approvalMessageText
//    }
//
//    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeMessageText newMessageText: String?) {
//        self.approvalMessageText = newMessageText
//    }
//
//    var sendMediaNavApprovalButtonImageName: String {
//        return "arrow-right-24"
//    }
//
//    var sendMediaNavCanSaveAttachments: Bool {
//        return true
//    }
//
//    var sendMediaNavTextInputContextIdentifier: String? {
//        return nil
//    }
//}
//
//extension ForwardMessageFlow: ConversationPickerDelegate {
//    var selectedConversationsForConversationPicker: [ConversationItem] {
//        return selectedConversations
//    }
//
//    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
//                            didSelectConversation conversation: ConversationItem) {
//        self.selectedConversations.append(conversation)
//    }
//
//    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
//                            didDeselectConversation conversation: ConversationItem) {
//        self.selectedConversations = self.selectedConversations.filter {
//            $0.messageRecipient != conversation.messageRecipient
//        }
//    }
//
//    func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController) {
//        guard let approvedAttachments = self.approvedAttachments else {
//            owsFailDebug("approvedAttachments was unexpectedly nil")
//            delegate?.forwardMessageFlowDidCancel(self)
//            return
//        }
//
//        let conversations = selectedConversationsForConversationPicker
//        DispatchQueue.global().async(.promise) {
//            // Duplicate attachments per conversation
//            let conversationAttachments: [(ConversationItem, [SignalAttachment])] =
//                try conversations.map { conversation in
//                    return (conversation, try approvedAttachments.map { try $0.cloneAttachment() })
//            }
//
//            // We only upload one set of attachments, and then copy the upload details into
//            // each conversation before sending.
//            let attachmentsToUpload: [OutgoingAttachmentInfo] = approvedAttachments.map { attachment in
//                return OutgoingAttachmentInfo(dataSource: attachment.dataSource,
//                                              contentType: attachment.mimeType,
//                                              sourceFilename: attachment.filenameOrDefault,
//                                              caption: attachment.captionText,
//                                              albumMessageId: nil)
//            }
//
//            self.databaseStorage.write { transaction in
//                var messages: [TSOutgoingMessage] = []
//
//                for (conversation, attachments) in conversationAttachments {
//                    let thread: TSThread
//                    switch conversation.messageRecipient {
//                    case .contact(let address):
//                        thread = TSContactThread.getOrCreateThread(withContactAddress: address,
//                                                                   transaction: transaction)
//                    case .group(let groupThread):
//                        thread = groupThread
//                    }
//
//                    let message = try! ThreadUtil.createUnsentMessage(withText: self.approvalMessageText,
//                                                                      mediaAttachments: attachments,
//                                                                      in: thread,
//                                                                      quotedReplyModel: nil,
//                                                                      linkPreviewDraft: nil,
//                                                                      transaction: transaction)
//                    messages.append(message)
//                }
//
//                // map of attachments we'll upload to their copies in each recipient thread
//                var attachmentIdMap: [String: [String]] = [:]
//                let correspondingAttachmentIds = transpose(messages.map { $0.attachmentIds })
//                for (index, attachmentInfo) in attachmentsToUpload.enumerated() {
//                    do {
//                        let attachmentToUpload = try attachmentInfo.asStreamConsumingDataSource(withIsVoiceMessage: false)
//                        attachmentToUpload.anyInsert(transaction: transaction)
//
//                        attachmentIdMap[attachmentToUpload.uniqueId] = correspondingAttachmentIds[index]
//                    } catch {
//                        owsFailDebug("error: \(error)")
//                    }
//                }
//
//                self.broadcastMediaMessageJobQueue.add(attachmentIdMap: attachmentIdMap,
//                                                       transaction: transaction)
//            }
//            }.done { _ in
//                self.delegate?.forwardMessageFlowDidComplete(self)
//            }.retainUntilComplete()
//    }
//}

// MARK: -

@objc
class ForwardMessageNavigationController: OWSNavigationController {
//    class ForwardMessageNavigationController: SendMediaNavigationController {

    // MARK: Dependencies

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    var broadcastMediaMessageJobQueue: BroadcastMediaMessageJobQueue {
        return AppEnvironment.shared.broadcastMediaMessageJobQueue
    }

    var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    // MARK: -

    @objc
    public weak var forwardMessageDelegate: ForwardMessageDelegate?

    var approvedAttachments: [SignalAttachment]?
    var approvalMessageText: String?

    var selectedConversations: [ConversationItem] = []

//    @objc
//    public let forwardMessageFlow: ForwardMessageFlow

//    private weak var delegate: MessageActionsDelegate?
//    private let message: TSMessage
    private let conversationViewItem: ConversationViewItem

    @objc
    public init(conversationViewItem: ConversationViewItem) {
        self.conversationViewItem = conversationViewItem

        self.approvalMessageText = conversationViewItem.displayableBodyText?.fullText

//        forwardMessageFlow = ForwardMessageFlow()

        super.init(owsNavbar: ())

        let pickerVC = ConversationPickerViewController()
        pickerVC.delegate = self
//        sendMediaNavigationController.pushViewController(pickerVC, animated: true)

        setViewControllers([
            pickerVC
            //            navController.captureViewController
            ], animated: false)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

//    @objc
//    public class func forwardMessageModal(conversationViewItem: ConversationViewItem) -> ForwardMessageNavigationController {
//        let navController = ForwardMessageNavigationController(conversationViewItem: conversationViewItem)
//        navController.setViewControllers([
////            navController.captureViewController
//            ], animated: false)
//
////        let forwardMessageFlow = ForwardMessageFlow()
////        navController.forwardMessageFlow = forwardMessageFlow
////        navController.sendMediaNavDelegate = forwardMessageFlow
//
//        return navController
//    }

    //    @objc
//    public required init(
////        delegate: MessageActionsDelegate,
////                         message: TSMessage,
//                         conversationViewItem: ConversationViewItem) {
////        self.delegate = delegate
////        self.message = message
//        self.conversationViewItem = conversationViewItem
//
//
//        super.initWithOWSNavbar()
//
////        delegate.messageActionDidStart(self)
//    }

//    @objc
//    public class func captureFirstCameraModal() -> ForwardMessageNavigationController {
//        let navController = ForwardMessageNavigationController()
//        navController.setViewControllers([navController.captureViewController], animated: false)
//
//        let forwardMessageFlow = ForwardMessageFlow()
//        navController.forwardMessageFlow = forwardMessageFlow
//        navController.sendMediaNavDelegate = forwardMessageFlow
//
//        return navController
//    }
}

// MARK: -

extension ForwardMessageNavigationController: ConversationPickerDelegate {
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
        approve()
    }
}

// MARK: -

extension ForwardMessageNavigationController: TextApprovalViewControllerDelegate {
    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageText: String) {
        assert(messageText.count > 0)

        approvalMessageText = messageText.stripped.filterForDisplay

        send()
    }

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController) {
        forwardMessageDelegate?.forwardMessageFlowDidCancel()
    }
}
