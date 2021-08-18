//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import PromiseKit

public protocol ForwardMessageDelegate: AnyObject {
    func forwardMessageFlowDidComplete(items: [ForwardMessageItem],
                                       recipientThreads: [TSThread])
    func forwardMessageFlowDidCancel()
}

// MARK: -

@objc
class ForwardMessageNavigationController: OWSNavigationController {

    public weak var forwardMessageDelegate: ForwardMessageDelegate?

    public typealias Item = ForwardMessageItem
    fileprivate typealias Content = ForwardMessageContent
    fileprivate typealias RecipientThread = ForwardMessageRecipientThread

    fileprivate var content: Content

    fileprivate var selectedConversations: [ConversationItem] = [] {
        didSet {
            updateCurrentMentionableAddresses()
        }
    }
    fileprivate var currentMentionableAddresses: [SignalServiceAddress] = []

    private init(content: Content) {
        self.content = content

        super.init()

        performStep(.firstStep)
    }

    public class func present(forItemViewModels itemViewModels: [CVItemViewModelImpl],
                              from fromViewController: UIViewController,
                              delegate: ForwardMessageDelegate) {
        do {
            let content: Content = try .build(itemViewModels: itemViewModels)
            present(content: content, from: fromViewController, delegate: delegate)
        } catch {
            ForwardMessageNavigationController.showAlertForForwardError(error: error,
                                                                        forwardedInteractionCount: itemViewModels.count)
        }
    }

    public class func present(forSelectionItems selectionItems: [CVSelectionItem],
                              from fromViewController: UIViewController,
                              delegate: ForwardMessageDelegate) {
        do {
            let content: Content = try Self.databaseStorage.read { transaction in
                try Content.build(selectionItems: selectionItems, transaction: transaction)
            }
            present(content: content, from: fromViewController, delegate: delegate)
        } catch {
            ForwardMessageNavigationController.showAlertForForwardError(error: error,
                                                                        forwardedInteractionCount: selectionItems.count)
        }
    }

    private class func present(content: Content,
                               from fromViewController: UIViewController,
                               delegate: ForwardMessageDelegate) {
        let modal = ForwardMessageNavigationController(content: content)
        modal.forwardMessageDelegate = delegate
        fromViewController.presentFormSheet(modal, animated: true)
    }

    fileprivate enum Step {
        case selectRecipients
        case send

        static var firstStep: Step { .selectRecipients }

        var nextStep: Step {
            switch self {
            case .selectRecipients:
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

    fileprivate func updateCurrentMentionableAddresses() {
        guard selectedConversations.count == 1,
              let conversationItem = selectedConversations.first else {
            self.currentMentionableAddresses = []
            return
        }

        do {
            try databaseStorage.write { transaction in
                let recipientThread = try RecipientThread.build(conversationItem: conversationItem,
                                                                transaction: transaction)
                self.currentMentionableAddresses = recipientThread.mentionCandidates
            }
        } catch {
            owsFailDebug("Error: \(error)")
            self.currentMentionableAddresses = []
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

    private func tryToSend() throws {
        let content = self.content

        let recipientConversations = self.selectedConversations
        firstly(on: .global()) {
            self.recipientThreads(for: recipientConversations)
        }.then(on: .main) { (recipientThreads: [RecipientThread]) -> Promise<Void> in
            try Self.databaseStorage.write { transaction in
                for recipientThread in recipientThreads {
                    // We're sending a message to this thread, approve any pending message request
                    ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimer(thread: recipientThread.thread,
                                                                                                    transaction: transaction)
                }

                func hasRenderableContent(interaction: TSInteraction) -> Bool {
                    guard let message = interaction as? TSMessage else {
                        return false
                    }
                    return message.hasRenderableContent()
                }

                // Make sure the message hasn't been deleted, etc. (e.g. view-once messages h
                for item in content.allItems {
                    let interactionId = item.interaction.uniqueId
                    guard let latestInteraction = TSInteraction.anyFetch(uniqueId: interactionId, transaction: transaction),
                          hasRenderableContent(interaction: latestInteraction) else {
                        throw ForwardError.missingInteraction
                    }
                }
            }

            // TODO: Ideally we would enqueue all with a single write tranasction.
            return firstly {
                // Maintain order of interactions.
                let sortedItems = content.allItems.sorted { lhs, rhs in
                    lhs.interaction.timestamp < rhs.interaction.timestamp
                }
                let promises = sortedItems.map { item in
                    self.send(item: item, toRecipientThreads: recipientThreads)
                }
                return when(resolved: promises).asVoid()
            }.map(on: .main) {
                let componentStates = content.allItems.map { $0.componentState }
                let threads = recipientThreads.map { $0.thread }
                self.forwardMessageDelegate?.forwardMessageFlowDidComplete(items: content.allItems,
                                                                           recipientThreads: threads)
            }
        }.catch(on: .main) { error in
            owsFailDebug("Error: \(error)")

            Self.showAlertForForwardError(error: error, forwardedInteractionCount: content.allItems.count)
        }
    }

    // TODO:
    private func send(item: Item, toRecipientThreads recipientThreads: [RecipientThread]) -> Promise<Void> {
        AssertIsOnMainThread()

        let componentState = item.componentState

        if let stickerMetadata = item.stickerMetadata {
            let stickerInfo = stickerMetadata.stickerInfo
            if StickerManager.isStickerInstalled(stickerInfo: stickerInfo) {
                return send(toRecipientThreads: recipientThreads) { recipientThread in
                    self.send(installedSticker: stickerInfo, thread: recipientThread.thread)
                }
            } else {
                guard let stickerAttachment = componentState.stickerAttachment else {
                    return Promise(error: OWSAssertionError("Missing stickerAttachment."))
                }
                do {
                    let stickerData = try stickerAttachment.readDataFromFile()
                    return send(toRecipientThreads: recipientThreads) { recipientThread in
                        self.send(uninstalledSticker: stickerMetadata,
                                  stickerData: stickerData,
                                  thread: recipientThread.thread)
                    }
                } catch {
                    return Promise(error: error)
                }
            }
        } else if let contactShare = item.contactShare {
            return send(toRecipientThreads: recipientThreads) { recipientThread in
                //                let contactShareCopy = contactShare.copyForResending()

                if let avatarImage = contactShare.avatarImage {
                    self.databaseStorage.write { transaction in
                        contactShare.dbRecord.saveAvatarImage(avatarImage, transaction: transaction)
                    }
                }
                return self.send(contactShare: contactShare, thread: recipientThread.thread)
            }
        } else if let attachments = item.attachments,
                  !attachments.isEmpty {
            // TODO: What about link previews in this case?
            let conversations = selectedConversationsForConversationPicker
            return AttachmentMultisend.sendApprovedMedia(conversations: conversations,
                                                         approvalMessageBody: item.messageBody,
                                                         approvedAttachments: attachments).asVoid()
        } else if let messageBody = item.messageBody {
            let linkPreviewDraft = item.linkPreviewDraft
            return send(toRecipientThreads: recipientThreads) { recipientThread in
                self.send(body: messageBody,
                          linkPreviewDraft: linkPreviewDraft,
                          thread: recipientThread.thread)
            }
        } else {
            return Promise(error: ForwardError.invalidInteraction)
        }
    }

    fileprivate func send(body: MessageBody, linkPreviewDraft: OWSLinkPreviewDraft?, thread: TSThread) -> Promise<Void> {
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(with: body,
                                      thread: thread,
                                      quotedReplyModel: nil,
                                      linkPreviewDraft: linkPreviewDraft,
                                      transaction: transaction)
        }
        return Promise.value(())
    }

    fileprivate func send(contactShare: ContactShareViewModel, thread: TSThread) -> Promise<Void> {
        ThreadUtil.enqueueMessage(withContactShare: contactShare.dbRecord, thread: thread)
        return Promise.value(())
    }

    fileprivate func send(body: MessageBody?, attachment: SignalAttachment, thread: TSThread) -> Promise<Void> {
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(with: body,
                                      mediaAttachments: [attachment],
                                      thread: thread,
                                      quotedReplyModel: nil,
                                      linkPreviewDraft: nil,
                                      transaction: transaction)
        }
        return Promise.value(())
    }

    fileprivate func send(installedSticker stickerInfo: StickerInfo, thread: TSThread) -> Promise<Void> {
        ThreadUtil.enqueueMessage(withInstalledSticker: stickerInfo, thread: thread)
        return Promise.value(())
    }

    fileprivate func send(uninstalledSticker stickerMetadata: StickerMetadata, stickerData: Data, thread: TSThread) -> Promise<Void> {
        ThreadUtil.enqueueMessage(withUninstalledSticker: stickerMetadata, stickerData: stickerData, thread: thread)
        return Promise.value(())
    }

    fileprivate func send(toRecipientThreads recipientThreads: [RecipientThread],
                          enqueueBlock: @escaping (RecipientThread) -> Promise<Void>) -> Promise<Void> {
        AssertIsOnMainThread()

        return when(fulfilled: recipientThreads.map { thread in enqueueBlock(thread) }).asVoid()
    }

    fileprivate func recipientThreads(for conversationItems: [ConversationItem]) -> Promise<[RecipientThread]> {
        firstly(on: .global()) {
            guard conversationItems.count > 0 else {
                throw OWSAssertionError("No recipients.")
            }

            return try self.databaseStorage.write { transaction in
                try conversationItems.map {
                    try RecipientThread.build(conversationItem: $0, transaction: transaction)
                }
            }
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
        .send
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
    public static func presentConversationAfterForwardIfNecessary(items: [Item],
                                                                  recipientThreads: [TSThread]) {
        let srcThreadIds = Set(items.compactMap { item in
            item.interaction.uniqueThreadId
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

// MARK: -

public enum ForwardError: Error {
    case missingInteraction
    case missingThread
    case invalidInteraction
}

// MARK: -

extension ForwardMessageNavigationController {

    public static func showAlertForForwardError(error: Error,
                                                forwardedInteractionCount: Int) {
        let genericErrorMessage = (forwardedInteractionCount > 1
                                    ? NSLocalizedString("ERROR_COULD_NOT_FORWARD_MESSAGES_N",
                                                        comment: "Error indicating that messages could not be forwarded.")
                                    : NSLocalizedString("ERROR_COULD_NOT_FORWARD_MESSAGES_1",
                                                        comment: "Error indicating that a message could not be forwarded."))

        guard let forwardError = error as? ForwardError else {
            owsFailDebug("Error: \(error).")
            OWSActionSheets.showErrorAlert(message: genericErrorMessage)
            return
        }

        switch forwardError {
        case .missingInteraction:
            let message = (forwardedInteractionCount > 1
                            ? NSLocalizedString("ERROR_COULD_NOT_FORWARD_MESSAGES_MISSING_N",
                                                comment: "Error indicating that messages could not be forwarded.")
                            : NSLocalizedString("ERROR_COULD_NOT_FORWARD_MESSAGES_MISSING_1",
                                                comment: "Error indicating that a message could not be forwarded."))
            OWSActionSheets.showErrorAlert(message: message)
        case .missingThread, .invalidInteraction:
            owsFailDebug("Error: \(error).")

            OWSActionSheets.showErrorAlert(message: genericErrorMessage)
        }
    }
}

// MARK: -

public struct ForwardMessageItem {
    fileprivate typealias Item = ForwardMessageItem

    let interaction: TSInteraction
    let componentState: CVComponentState

    let attachments: [SignalAttachment]?
    let contactShare: ContactShareViewModel?
    let messageBody: MessageBody?
    let linkPreviewDraft: OWSLinkPreviewDraft?
    let stickerMetadata: StickerMetadata?

    fileprivate class Builder {
        let interaction: TSInteraction
        let componentState: CVComponentState

        var attachments: [SignalAttachment]?
        var contactShare: ContactShareViewModel?
        var messageBody: MessageBody?
        var linkPreviewDraft: OWSLinkPreviewDraft?
        var stickerMetadata: StickerMetadata?

        init(interaction: TSInteraction, componentState: CVComponentState) {
            self.interaction = interaction
            self.componentState = componentState
        }

        func build() -> ForwardMessageItem {
            ForwardMessageItem(interaction: interaction,
                               componentState: componentState,
                               attachments: attachments,
                               contactShare: contactShare,
                               messageBody: messageBody,
                               linkPreviewDraft: linkPreviewDraft,
                               stickerMetadata: stickerMetadata)
        }
    }

    fileprivate var asBuilder: Builder {
        let builder = Builder(interaction: interaction, componentState: componentState)
        builder.attachments = attachments
        builder.contactShare = contactShare
        builder.messageBody = messageBody
        builder.linkPreviewDraft = linkPreviewDraft
        builder.stickerMetadata = stickerMetadata
        return builder
    }

    var isEmpty: Bool {
        if let attachments = attachments,
           !attachments.isEmpty {
            return false
        }
        if contactShare != nil ||
            messageBody != nil ||
            stickerMetadata != nil {
            return false
        }
        return true
    }

    fileprivate static func build(interaction: TSInteraction,
                                  componentState: CVComponentState,
                                  selectionType: CVSelectionType) throws -> Item {

        let builder = Builder(interaction: interaction, componentState: componentState)

        let shouldHaveText = (selectionType == .allContent ||
                                selectionType == .secondaryContent)
        let shouldHaveAttachments = (selectionType == .allContent ||
                                        selectionType == .primaryContent)

        guard shouldHaveText || shouldHaveAttachments else {
            throw ForwardError.invalidInteraction
        }

        if shouldHaveText,
           let displayableBodyText = componentState.displayableBodyText,
           !displayableBodyText.fullAttributedText.isEmpty {

            let attributedText = displayableBodyText.fullAttributedText
            builder.messageBody = MessageBody(attributedString: attributedText)

            // TODO: linkPreviewDraft
            // TODO: oversize text.
        }

        if shouldHaveAttachments {
            if let oldContactShare = componentState.contactShareModel {
                builder.contactShare = oldContactShare.copyForResending()
            }

            var attachmentStreams = [TSAttachmentStream]()
            attachmentStreams.append(contentsOf: componentState.bodyMediaAttachmentStreams)
            if let attachmentStream = componentState.audioAttachmentStream {
                attachmentStreams.append(attachmentStream)
            }
            if let attachmentStream = componentState.genericAttachmentStream {
                attachmentStreams.append(attachmentStream)
            }
            // TODO: Sticker.
//            if let attachmentStream = componentState.stic {
//                attachmentStreams.append(attachmentStream)
//            }

            if !attachmentStreams.isEmpty {
                builder.attachments = try attachmentStreams.map { attachmentStream in
                    try attachmentStream.cloneAsSignalAttachment()
                }
            }

            if let stickerMetadata = componentState.stickerMetadata {
                builder.stickerMetadata = stickerMetadata
            }

//            guard let stickerMetadata = componentState.stickerMetadata else {
//                return Promise(error: OWSAssertionError("Missing stickerInfo."))
//            }
//
//            let stickerInfo = stickerMetadata.stickerInfo
//            if StickerManager.isStickerInstalled(stickerInfo: stickerInfo) {
//                return send(toRecipientThreads: recipientThreads) { recipientThread in
//                    self.send(installedSticker: stickerInfo, thread: recipientThread.thread)
//                }
//            } else {
//                guard let stickerAttachment = componentState.stickerAttachment else {
//                    return Promise(error: OWSAssertionError("Missing stickerAttachment."))
//                }
//                do {
//                    let stickerData = try stickerAttachment.readDataFromFile()
//                    return send(toRecipientThreads: recipientThreads) { recipientThread in
//                        self.send(uninstalledSticker: stickerMetadata,
//                                  stickerData: stickerData,
//                                  thread: recipientThread.thread)
//                    }
//                } catch {
//                    return Promise(error: error)
//                }
//            }
        }

        let item = builder.build()
        guard !item.isEmpty else {
            throw ForwardError.invalidInteraction
        }
        return item
    }
}

// MARK: -

private enum ForwardMessageContent {
    fileprivate typealias Item = ForwardMessageItem

    case single(item: Item)
    case multiple(items: [Item])

    var allItems: [Item] {
        switch self {
        case .single(let item):
            return [item]
        case .multiple(let items):
            return items
        }
    }

    static func build(items: [Item]) -> ForwardMessageContent {
        if items.count == 1, let item = items.first {
            return .single(item: item)
        } else {
            return .multiple(items: items)
        }
    }

    static func build(itemViewModels: [CVItemViewModelImpl]) throws -> ForwardMessageContent {
        let items: [Item] = try itemViewModels.map { itemViewModel in
            try Item.build(interaction: itemViewModel.interaction,
                           componentState: itemViewModel.renderItem.componentState,
                           selectionType: .allContent)
        }
        return build(items: items)
    }

    static func build(selectionItems: [CVSelectionItem],
                      transaction: SDSAnyReadTransaction) throws -> ForwardMessageContent {
        let items: [Item] = try selectionItems.map { selectionItem in
            let interactionId = selectionItem.interactionId
            guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId,
                                                           transaction: transaction) else {
                throw ForwardError.invalidInteraction
            }
            let componentState = try buildComponentState(interactionId: interactionId,
                                                         transaction: transaction)
            return try Item.build(interaction: interaction,
                                  componentState: componentState,
                                  selectionType: selectionItem.selectionType)
        }
        return build(items: items)
    }

    private static func buildComponentState(interactionId: String,
                                            transaction: SDSAnyReadTransaction) throws -> CVComponentState {
        guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId,
                                                       transaction: transaction) else {
            throw ForwardError.missingInteraction
        }
        guard let componentState = CVLoader.buildStandaloneComponentState(interaction: interaction,
                                                                          transaction: transaction) else {
            throw ForwardError.invalidInteraction
        }
        return componentState
////        // TODO:
////        let containerView = UIView(frame: CGRect(origin: .zero, size: .square(800)))
////        guard let renderItem = CVLoader.buildStandaloneRenderItem(interaction: interaction,
////                                                                  thread: thread,
////                                                                  containerView: containerView,
////                                                                  transaction: transaction) else {
////            throw ForwardError.invalidInteraction
////        }
//        let item = CVComponentState(renderItem: renderItem)
//        return item
    }
}

// MARK: -

private struct ForwardMessageRecipientThread {
    let thread: TSThread
    let mentionCandidates: [SignalServiceAddress]

    static func build(conversationItem: ConversationItem,
                      transaction: SDSAnyWriteTransaction) throws -> ForwardMessageRecipientThread {

        guard let thread = conversationItem.thread(transaction: transaction) else {
            owsFailDebug("Missing thread for conversation")
            throw ForwardError.missingThread
        }

        let mentionCandidates = self.mentionCandidates(conversationItem: conversationItem,
                                                       thread: thread,
                                                       transaction: transaction)
        return ForwardMessageRecipientThread(thread: thread, mentionCandidates: mentionCandidates)
    }

    private static func mentionCandidates(conversationItem: ConversationItem,
                                          thread: TSThread,
                                          transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        guard let groupThread = thread as? TSGroupThread,
              Mention.threadAllowsMentionSend(groupThread) else {
            return []
        }
        return groupThread.recipientAddresses
    }
}
