//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import PromiseKit

@objc
public protocol ForwardMessageDelegate: AnyObject {
    func forwardMessageFlowDidComplete(itemViewModels: [CVItemViewModelImpl],
                                       recipientThreads: [TSThread])
    func forwardMessageFlowDidCancel()
}

// MARK: -

@objc
class ForwardMessageNavigationController: OWSNavigationController {

    @objc
    public weak var forwardMessageDelegate: ForwardMessageDelegate?

    fileprivate struct Item {
        let itemViewModel: CVItemViewModelImpl
        let attachments: [SignalAttachment]?
        let contactShare: ContactShareViewModel?
        let messageBody: MessageBody?
        let linkPreviewDraft: OWSLinkPreviewDraft?

        init(itemViewModel: CVItemViewModelImpl,
             attachments: [SignalAttachment]? = nil,
             contactShare: ContactShareViewModel? = nil,
             messageBody: MessageBody? = nil,
             linkPreviewDraft: OWSLinkPreviewDraft? = nil) {
            self.itemViewModel = itemViewModel
            self.attachments = attachments
            self.contactShare = contactShare
            self.messageBody = messageBody
            self.linkPreviewDraft = linkPreviewDraft
        }

        func with(messageBody: MessageBody?) -> Item {
            Item(itemViewModel: self.itemViewModel,
                 attachments: self.attachments,
                 contactShare: self.contactShare,
                 messageBody: messageBody,
                 linkPreviewDraft: self.linkPreviewDraft)
        }

        func with(attachments: [SignalAttachment]) -> Item {
            Item(itemViewModel: self.itemViewModel,
                 attachments: attachments,
                 contactShare: self.contactShare,
                 messageBody: self.messageBody,
                 linkPreviewDraft: self.linkPreviewDraft)
        }

        func with(contactShare: ContactShareViewModel) -> Item {
            Item(itemViewModel: self.itemViewModel,
                 attachments: self.attachments,
                 contactShare: contactShare,
                 messageBody: self.messageBody,
                 linkPreviewDraft: self.linkPreviewDraft)
        }

        func with(linkPreviewDraft: OWSLinkPreviewDraft?) -> Item {
            Item(itemViewModel: self.itemViewModel,
                 attachments: self.attachments,
                 contactShare: self.contactShare,
                 messageBody: self.messageBody,
                 linkPreviewDraft: linkPreviewDraft)
        }
    }

    // TODO:
    var mentionCandidates: [SignalServiceAddress] = []
    var selectedConversations: [ConversationItem] = [] {
        didSet {
            updateMentionCandidates()
        }
    }

    fileprivate enum Content {
        case single(item: Item)
        case multiple(items: [Item])

        var singleItem: Item? {
            switch self {
            case .single(let item):
                return item
            case .multiple:
                owsFailDebug("Single item requested in multiple item mode.")
                return nil
            }
        }

        var allItems: [Item] {
            switch self {
            case .single(let item):
                return [item]
            case .multiple(let items):
                return items
            }
        }

        static func build(itemViewModels: [CVItemViewModelImpl]) -> Content {
            if itemViewModels.count == 1,
               let itemViewModel = itemViewModels.first {
                if let displayableBodyText = itemViewModel.displayableBodyText {
                    let attributedText = displayableBodyText.fullAttributedText
                    let messageBody = MessageBody(attributedString: attributedText)
                    let item = Item(itemViewModel: itemViewModel, messageBody: messageBody)
                    return .single(item: item)
                } else {
                    let item = Item(itemViewModel: itemViewModel)
                    return .single(item: item)
                }
            } else {
                let items = itemViewModels.map { Item(itemViewModel: $0) }
                return .multiple(items: items)
            }
        }

        var needsApproval: Bool {
            switch self {
            case .single(let item):
                let itemViewModel = item.itemViewModel
                guard ![.audio,
                        .genericAttachment,
                        .stickerMessage].contains(itemViewModel.messageCellType) else { return false }

                let isBorderless: Bool = {
                    let bodyMediaAttachmentStreams = itemViewModel.bodyMediaAttachmentStreams
                    guard !bodyMediaAttachmentStreams.isEmpty else {
                        return false
                    }

                    return bodyMediaAttachmentStreams.count == 1 && bodyMediaAttachmentStreams.first?.isBorderless == true
                }()

                guard !isBorderless else { return false }

                return true
            case .multiple:
                return false
            }
        }
    }

    fileprivate var content: Content

    private init(content: Content) {
        self.content = content

        super.init()

        performStep(.selectRecipients)
    }

    @objc
    public class func present(for itemViewModels: [CVItemViewModelImpl],
                              from fromViewController: UIViewController,
                              delegate: ForwardMessageDelegate) {
        let modal = ForwardMessageNavigationController(content: .build(itemViewModels: itemViewModels))
        modal.forwardMessageDelegate = delegate
        fromViewController.presentFormSheet(modal, animated: true)
    }

    fileprivate enum Step {
        case selectRecipients
        case approve
        case send

        var nextStep: Step {
            switch self {
            case .selectRecipients:
                return .approve
            case .approve:
                return .send
            case .send:
                owsFailDebug("There is no next step.")
                return .send
            }
        }
    }

    private func performStep(_ step: Step) {
        switch step {
        case .selectRecipients:
            selectRecipientsStep()
        case .approve:
            approveStep()
        case .send:
            sendStep()
        }
    }

    private func selectRecipientsStep() {
        let pickerVC = ConversationPickerViewController()
        pickerVC.delegate = self

        setViewControllers([
            pickerVC
        ], animated: false)
    }

}

// MARK: - Approval

extension ForwardMessageNavigationController {

    func approveStep() {
        do {
            if content.needsApproval,
               let item = content.singleItem {
                try showApprovalUI(item: item)
            } else {
                // Skip approval for these message types.
                try autoApproveContent()
            }
        } catch {
            owsFailDebug("Error: \(error)")

            self.forwardMessageDelegate?.forwardMessageFlowDidCancel()
        }
    }

    private func showApprovalUI(item: Item) throws {
        let itemViewModel = item.itemViewModel

        switch itemViewModel.messageCellType {
        case .textOnlyMessage:
            guard let body = item.messageBody,
                body.text.count > 0 else {
                    throw OWSAssertionError("Missing body.")
            }

            let approvalView = TextApprovalViewController(messageBody: body)
            approvalView.delegate = self
            pushViewController(approvalView, animated: true)
        case .contactShare:
            guard let oldContactShare = itemViewModel.contactShare else {
                throw OWSAssertionError("Missing contactShareViewModel.")
            }
            let newContactShare = oldContactShare.copyForResending()
            let approvalView = ContactShareApprovalViewController(contactShare: newContactShare)
            approvalView.delegate = self
            pushViewController(approvalView, animated: true)
        case .audio,
             .genericAttachment,
             .stickerMessage:
            throw OWSAssertionError("Message type does not need approval.")
        case .bodyMedia:
            let options: AttachmentApprovalViewControllerOptions = .hasCancel
            let sendButtonImageName = "send-solid-24"

            let bodyMediaAttachmentStreams = itemViewModel.bodyMediaAttachmentStreams
            guard !bodyMediaAttachmentStreams.isEmpty else {
                throw OWSAssertionError("Missing bodyMediaAttachmentStreams.")
            }

            var attachmentApprovalItems = [AttachmentApprovalItem]()
            for attachmentStream in bodyMediaAttachmentStreams {
                let signalAttachment = try attachmentStream.cloneAsSignalAttachment()
                let attachmentApprovalItem = AttachmentApprovalItem(attachment: signalAttachment, canSave: false)
                attachmentApprovalItems.append(attachmentApprovalItem)
            }
            let approvalViewController = AttachmentApprovalViewController(options: options,
                                                                          sendButtonImageName: sendButtonImageName,
                                                                          attachmentApprovalItems: attachmentApprovalItems)
            approvalViewController.approvalDelegate = self
            approvalViewController.messageBody = item.messageBody

            pushViewController(approvalViewController, animated: true)
        case .unknown, .viewOnce, .dateHeader, .unreadIndicator, .typingIndicator,
             .threadDetails, .systemMessage, .unknownThreadWarning, .defaultDisappearingMessageTimer:
            throw OWSAssertionError("Invalid message type.")
        }
    }

    private func autoApproveContent() throws {
        let items = try content.allItems.map { try autoApprove(item: $0) }
        if items.count == 1,
           let item = items.first {
            self.content = .single(item: item)
        } else {
            self.content = .multiple(items: items)
        }
        performStep(Step.approve.nextStep)
    }

    private func autoApprove(item: Item) throws -> Item {
        let itemViewModel = item.itemViewModel
        switch itemViewModel.messageCellType {
        case .textOnlyMessage:
            return item
        case .contactShare:
            guard let oldContactShare = itemViewModel.contactShare else {
                return item
            }
            let newContactShare = oldContactShare.copyForResending()
            return item.with(contactShare: newContactShare)
        case .audio,
             .genericAttachment,
             .stickerMessage:
            return item
        case .bodyMedia:
            let bodyMediaAttachmentStreams = itemViewModel.bodyMediaAttachmentStreams
            guard !bodyMediaAttachmentStreams.isEmpty else {
                throw OWSAssertionError("Missing bodyMediaAttachmentStreams.")
            }
            let signalAttachments = try bodyMediaAttachmentStreams.map { attachmentStream in
                try attachmentStream.cloneAsSignalAttachment()
            }
            return item.with(attachments: signalAttachments)
        case .unknown, .viewOnce, .dateHeader, .unreadIndicator, .typingIndicator,
             .threadDetails, .systemMessage, .unknownThreadWarning, .defaultDisappearingMessageTimer:
            return item
        }
    }
}

// MARK: - Sending

extension ForwardMessageNavigationController {

    func sendStep() {
        do {
            try tryToSend()
        } catch {
            owsFailDebug("Error: \(error)")

            self.forwardMessageDelegate?.forwardMessageFlowDidCancel()
        }
    }

    func tryToSend() throws {
        switch itemViewModel.messageCellType {
        case .textOnlyMessage:
            guard let body = approvalMessageBody,
                body.text.count > 0 else {
                    throw OWSAssertionError("Missing body.")
            }

            let linkPreviewDraft = approvalLinkPreviewDraft

            send { thread in
                self.send(body: body, linkPreviewDraft: linkPreviewDraft, thread: thread)
            }
        case .contactShare:
            guard let contactShare = approvedContactShare else {
                throw OWSAssertionError("Missing contactShare.")
            }

            send { thread in
                let contactShareCopy = contactShare.copyForResending()

                if let avatarImage = contactShareCopy.avatarImage {
                    self.databaseStorage.write { transaction in
                        contactShareCopy.dbRecord.saveAvatarImage(avatarImage, transaction: transaction)
                    }
                }

                self.send(contactShare: contactShareCopy, thread: thread)
            }
        case .stickerMessage:
            guard let stickerMetadata = itemViewModel.stickerMetadata else {
                throw OWSAssertionError("Missing stickerInfo.")
            }

            let stickerInfo = stickerMetadata.stickerInfo
            if StickerManager.isStickerInstalled(stickerInfo: stickerInfo) {
                send { thread in
                    self.send(installedSticker: stickerInfo, thread: thread)
                }
            } else {
                guard let stickerAttachment = itemViewModel.stickerAttachment else {
                    owsFailDebug("Missing stickerAttachment.")
                    return
                }
                let stickerData = try stickerAttachment.readDataFromFile()
                send { thread in
                    self.send(uninstalledSticker: stickerMetadata, stickerData: stickerData, thread: thread)
                }
            }
        case .audio:
            guard let attachmentStream = itemViewModel.audioAttachmentStream else {
                throw OWSAssertionError("Missing attachmentStream.")
            }
            send { thread in
                let attachment = try attachmentStream.cloneAsSignalAttachment()
                self.send(body: nil, attachment: attachment, thread: thread)
            }
        case .genericAttachment:
            guard let attachmentStream = itemViewModel.genericAttachmentStream else {
                throw OWSAssertionError("Missing attachmentStream.")
            }
            send { thread in
                let attachment = try attachmentStream.cloneAsSignalAttachment()
                self.send(body: nil, attachment: attachment, thread: thread)
            }
        case .bodyMedia:
            // TODO: Why are stickers special-cased here?
//            if isBorderless {
//                guard let attachmentStream = itemViewModel.firstValidAlbumAttachment() else {
//                    throw OWSAssertionError("Missing attachmentStream.")
//                }
//
//                send { thread in
//                    let attachment = try attachmentStream.cloneAsSignalAttachment()
//                    self.send(body: nil, attachment: attachment, thread: thread)
//                }
//            } else {
                guard let approvedAttachments = approvedAttachments else {
                    throw OWSAssertionError("Missing approvedAttachments.")
                }

                let conversations = selectedConversationsForConversationPicker
                firstly {
                    AttachmentMultisend.sendApprovedMedia(conversations: conversations,
                                                          approvalMessageBody: self.approvalMessageBody,
                                                          approvedAttachments: approvedAttachments)
                }.done { threads in
                    let itemViewModels = content.allItems.map { $0.itemViewModel }
                    self.forwardMessageDelegate?.forwardMessageFlowDidComplete(itemViewModels: itemViewModels,
                                                                               recipientThreads: threads)
                }.catch { error in
                    owsFailDebug("Error: \(error)")
                    // TODO: Do we need to call a delegate method?
                }
//            }
        case .unknown, .viewOnce, .dateHeader, .unreadIndicator, .typingIndicator,
             .threadDetails, .systemMessage, .unknownThreadWarning, .defaultDisappearingMessageTimer:
            throw OWSAssertionError("Invalid message type.")
        }
    }

    func send(body: MessageBody, linkPreviewDraft: OWSLinkPreviewDraft?, thread: TSThread) {
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(with: body, thread: thread, quotedReplyModel: nil, linkPreviewDraft: linkPreviewDraft, transaction: transaction)
        }
    }

    func send(contactShare: ContactShareViewModel, thread: TSThread) {
        ThreadUtil.enqueueMessage(withContactShare: contactShare.dbRecord, thread: thread)
    }

    func send(body: MessageBody?, attachment: SignalAttachment, thread: TSThread) {
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(with: body,
                                      mediaAttachments: [attachment],
                                      thread: thread,
                                      quotedReplyModel: nil,
                                      linkPreviewDraft: nil,
                                      transaction: transaction)
        }
    }

    func send(installedSticker stickerInfo: StickerInfo, thread: TSThread) {
        ThreadUtil.enqueueMessage(withInstalledSticker: stickerInfo, thread: thread)
    }

    func send(uninstalledSticker stickerMetadata: StickerMetadata, stickerData: Data, thread: TSThread) {
        ThreadUtil.enqueueMessage(withUninstalledSticker: stickerMetadata, stickerData: stickerData, thread: thread)
    }

    func send(enqueueBlock: @escaping (TSThread) throws -> Void) {
        AssertIsOnMainThread()

        let conversations = self.selectedConversationsForConversationPicker
        firstly {
            self.threads(for: conversations)
        }.done { (threads: [TSThread]) in
            for thread in threads {
                try enqueueBlock(thread)

                // We're sending a message to this thread, approve any pending message request
                ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
            }

            let itemViewModels = content.allItems.map { $0.itemViewModel }
            self.forwardMessageDelegate?.forwardMessageFlowDidComplete(itemViewModels: itemViewModels,
                                                                       recipientThreads: threads)
        }.catch { error in
            owsFailDebug("Error: \(error)")
            // TODO: Do we need to call a delegate methoad?
        }
    }

    func threads(for conversationItems: [ConversationItem]) -> Promise<[TSThread]> {
        return DispatchQueue.global().async(.promise) {
            guard conversationItems.count > 0 else {
                throw OWSAssertionError("No recipients.")
            }

            var threads: [TSThread] = []

            self.databaseStorage.write { transaction in
                for conversation in conversationItems {
                    guard let thread = conversation.thread(transaction: transaction) else {
                        owsFailDebug("Missing thread for conversation")
                        continue
                    }
                    threads.append(thread)
                }
            }
            return threads
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

// MARK: -

extension ForwardMessageNavigationController: ConversationPickerDelegate {
    var selectedConversationsForConversationPicker: [ConversationItem] {
        selectedConversations
    }

    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didSelectConversation conversation: ConversationItem) {
        selectedConversations.append(conversation)
    }

    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didDeselectConversation conversation: ConversationItem) {
        self.selectedConversations = self.selectedConversations.filter {
            $0.messageRecipient != conversation.messageRecipient
        }
    }

    func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController) {
        performStep(Step.selectRecipients.nextStep)
    }

    func conversationPickerCanCancel(_ conversationPickerViewController: ConversationPickerViewController) -> Bool {
        true
    }

    func conversationPickerDidCancel(_ conversationPickerViewController: ConversationPickerViewController) {
        forwardMessageDelegate?.forwardMessageFlowDidCancel()
    }

    func approvalMode(_ conversationPickerViewController: ConversationPickerViewController) -> ApprovalMode {
        content.needsApproval ? .next : .send
    }
}

// MARK: -

extension ForwardMessageNavigationController: TextApprovalViewControllerDelegate {
    func textApproval(_ textApproval: TextApprovalViewController,
                      didApproveMessage messageBody: MessageBody?,
                      linkPreviewDraft: OWSLinkPreviewDraft?) {
        assert(messageBody?.text.count ?? 0 > 0)

        guard let item = content.singleItem else {
            return
        }
        self.content = .single(item: item.with(messageBody: messageBody).with(linkPreviewDraft: linkPreviewDraft))

        performStep(Step.approve.nextStep)
    }

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController) {
        forwardMessageDelegate?.forwardMessageFlowDidCancel()
    }

    func textApprovalCustomTitle(_ textApproval: TextApprovalViewController) -> String? {
        return NSLocalizedString("FORWARD_MESSAGE", comment: "Label and title for 'message forwarding' views.")
    }

    func textApprovalRecipientsDescription(_ textApproval: TextApprovalViewController) -> String? {
        let conversations = selectedConversationsForConversationPicker
        guard conversations.count > 0 else {
            return nil
        }
        return conversations.map { $0.title }.joined(separator: ", ")
    }

    func textApprovalMode(_ textApproval: TextApprovalViewController) -> ApprovalMode {
        return .send
    }
}

// MARK: -

extension ForwardMessageNavigationController: ContactShareApprovalViewControllerDelegate {
    func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
                             didApproveContactShare contactShare: ContactShareViewModel) {
        guard let item = content.singleItem else {
            return
        }
        self.content = .single(item: item.with(contactShare: contactShare))

        performStep(Step.approve.nextStep)
    }

    func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
                             didCancelContactShare contactShare: ContactShareViewModel) {
        forwardMessageDelegate?.forwardMessageFlowDidCancel()
    }

    func contactApprovalCustomTitle(_ contactApproval: ContactShareApprovalViewController) -> String? {
        return NSLocalizedString("FORWARD_CONTACT", comment: "Label and title for 'contact forwarding' views.")
    }

    func contactApprovalRecipientsDescription(_ contactApproval: ContactShareApprovalViewController) -> String? {
        let conversations = selectedConversationsForConversationPicker
        guard conversations.count > 0 else {
            return nil
        }
        return conversations.map { $0.title }.joined(separator: ", ")
    }

    func contactApprovalMode(_ contactApproval: ContactShareApprovalViewController) -> ApprovalMode {
        return .send
    }
}

// MARK: -

extension ForwardMessageNavigationController: AttachmentApprovalViewControllerDelegate {

    func attachmentApprovalDidAppear(_ attachmentApproval: AttachmentApprovalViewController) {
        // We can ignore this event.
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageBody newMessageBody: MessageBody?) {
        guard let item = content.singleItem else {
            return
        }
        self.content = .single(item: item.with(messageBody: newMessageBody))
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment) {
        // We can ignore this event.
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                            didApproveAttachments attachments: [SignalAttachment],
                            messageBody: MessageBody?) {
        guard let item = content.singleItem else {
            return
        }
        self.content = .single(item: item.with(messageBody: messageBody).with(attachments: attachments))

        performStep(ForwardMessageNavigationController.Step.approve.nextStep)
    }

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
        forwardMessageDelegate?.forwardMessageFlowDidCancel()
    }

    func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController) {
        owsFailDebug("Cannot add more to message forwards.")
    }

    var attachmentApprovalTextInputContextIdentifier: String? {
        return nil
    }

    var attachmentApprovalRecipientNames: [String] {
        selectedConversationsForConversationPicker.map { $0.title }
    }

    var attachmentApprovalMentionableAddresses: [SignalServiceAddress] {
        mentionCandidates
    }
}

// MARK: -

extension TSAttachmentStream {
    func cloneAsSignalAttachment() throws -> SignalAttachment {
        guard let sourceUrl = originalMediaURL else {
            throw OWSAssertionError("Missing originalMediaURL.")
        }
        guard let dataUTI = MIMETypeUtil.utiType(forMIMEType: contentType) else {
            throw OWSAssertionError("Missing dataUTI.")
        }
        let newUrl = OWSFileSystem.temporaryFileUrl(fileExtension: sourceUrl.pathExtension)
        try FileManager.default.copyItem(at: sourceUrl, to: newUrl)

        let clonedDataSource = try DataSourcePath.dataSource(with: newUrl,
                                                             shouldDeleteOnDeallocation: true)
        clonedDataSource.sourceFilename = sourceFilename

        var signalAttachment: SignalAttachment
        if isVoiceMessage {
            signalAttachment = SignalAttachment.voiceMessageAttachment(dataSource: clonedDataSource, dataUTI: dataUTI)
        } else {
            signalAttachment = SignalAttachment.attachment(dataSource: clonedDataSource, dataUTI: dataUTI)
        }
        signalAttachment.captionText = caption
        signalAttachment.isBorderless = isBorderless
        signalAttachment.isLoopingVideo = isLoopingVideo
        return signalAttachment
    }
}

// MARK: -

extension ForwardMessageNavigationController {
    public static func presentConversationAfterForwardIfNecessary(itemViewModels: [CVItemViewModelImpl],
                                                                  recipientThreads: [TSThread]) {
        let srcThreadIds = Set(itemViewModels.compactMap { itemViewModel in
            itemViewModel.interaction.uniqueThreadId
        })
        let dstThreadIds = Set(recipientThreads.compactMap { thread in
            thread.uniqueId
        })
        // If the user forwarded to just one recipient thread, and it's different from
        // the current thread, navigate to the recipient thread.
        guard srcThreadIds != dstThreadIds,
              dstThreadIds.count == 1,
              let thread = recipientThreads.first else {
            return
        }
        SignalApp.shared().presentConversation(for: thread, animated: true)
    }
}
