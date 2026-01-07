//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol ForwardMessageDelegate: AnyObject {
    func forwardMessageFlowDidComplete(items: [ForwardMessageItem], recipientThreads: [TSThread])
    func forwardMessageFlowDidCancel()
}

class ForwardMessageViewController: OWSNavigationController {

    private let pickerVC: ConversationPickerViewController

    weak var forwardMessageDelegate: ForwardMessageDelegate?

    private typealias Content = ForwardMessageContent

    private var content: Content

    private var textMessage: String?

    private let selection = ConversationPickerSelection()
    var selectedConversations: [ConversationItem] { selection.conversations }

    private init(content: Content) {
        self.content = content
        self.pickerVC = ConversationPickerViewController(
            selection: selection,
            overrideTitle: OWSLocalizedString(
                "FORWARD_MESSAGE_TITLE",
                comment: "Title for the 'forward message(s)' view.",
            ),
        )

        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
            self.pickerVC.backgroundStyle = .none
        }

        super.init()

        if self.content.canSendToStories {
            if self.content.canSendToNonStories {
                self.pickerVC.sectionOptions.insert(.stories)
            } else {
                self.pickerVC.sectionOptions = .storiesOnly
            }
        } else {
            self.pickerVC.shouldHideRecentConversationsTitle = true
        }

        pickerVC.pickerDelegate = self
        pickerVC.shouldBatchUpdateIdentityKeys = true

        viewControllers = [pickerVC]

        modalPresentationStyle = .formSheet
        sheetPresentationController?.detents = [.medium(), .large()]
        sheetPresentationController?.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    class func present(
        forItemViewModel itemViewModel: CVItemViewModelImpl,
        from fromViewController: UIViewController,
        delegate: ForwardMessageDelegate,
    ) {
        do {
            let content: Content = try SSKEnvironment.shared.databaseStorageRef.read { tx in
                return try Content.build(itemViewModel: itemViewModel, tx: tx)
            }
            present(content: content, from: fromViewController, delegate: delegate)
        } catch {
            ForwardMessageViewController.showAlertForForwardError(error: error, forwardedInteractionCount: 1)
        }
    }

    class func present(
        forSelectionItems selectionItems: [CVSelectionItem],
        from fromViewController: UIViewController,
        delegate: ForwardMessageDelegate,
    ) {
        do {
            let content: Content = try SSKEnvironment.shared.databaseStorageRef.read { tx in
                try Content.build(selectionItems: selectionItems, tx: tx)
            }
            present(content: content, from: fromViewController, delegate: delegate)
        } catch {
            ForwardMessageViewController.showAlertForForwardError(error: error, forwardedInteractionCount: selectionItems.count)
        }
    }

    class func present(
        forAttachmentStreams attachmentStreams: [ReferencedAttachmentStream],
        fromMessage message: TSMessage,
        from fromViewController: UIViewController,
        delegate: ForwardMessageDelegate,
    ) {
        do {
            let attachments = try attachmentStreams.map { attachmentStream in
                try SignalAttachmentCloner.cloneAsSignalAttachment(attachment: attachmentStream)
            }
            present(
                content: ForwardMessageContent(allItems: [ForwardMessageItem(interaction: message, attachments: attachments)]),
                from: fromViewController,
                delegate: delegate,
            )
        } catch let error {
            ForwardMessageViewController.showAlertForForwardError(
                error: error,
                forwardedInteractionCount: 1,
            )
        }
    }

    class func present(
        forStoryMessage storyMessage: StoryMessage,
        from fromViewController: UIViewController,
        delegate: ForwardMessageDelegate,
    ) {
        var attachments: [PreviewableAttachment] = []
        var textAttachment: TextAttachment?
        switch storyMessage.attachment {
        case .media:
            let attachment: ReferencedAttachmentStream? = SSKEnvironment.shared.databaseStorageRef.read { tx in
                guard
                    let rowId = storyMessage.id,
                    let referencedStream = DependenciesBridge.shared.attachmentStore.fetchAnyReferencedAttachment(
                        for: .storyMessageMedia(storyMessageRowId: rowId),
                        tx: tx,
                    )?.asReferencedStream
                else {
                    return nil
                }
                return referencedStream
            }
            do {
                guard let attachment else {
                    throw OWSAssertionError("Missing attachment stream for forwarded story message")
                }
                let signalAttachment = try SignalAttachmentCloner.cloneAsSignalAttachment(attachment: attachment)
                attachments = [signalAttachment]
            } catch let error {
                ForwardMessageViewController.showAlertForForwardError(
                    error: error,
                    forwardedInteractionCount: 1,
                )
                return
            }
        case .text(let _textAttachment):
            textAttachment = _textAttachment
        }
        present(
            content: ForwardMessageContent(allItems: [ForwardMessageItem(attachments: attachments, textAttachment: textAttachment)]),
            from: fromViewController,
            delegate: delegate,
        )
    }

    class func present(
        forMessageBody messageBody: MessageBody,
        from fromViewController: UIViewController,
        delegate: ForwardMessageDelegate,
    ) {
        present(
            content: ForwardMessageContent(allItems: [ForwardMessageItem(messageBody: messageBody)]),
            from: fromViewController,
            delegate: delegate,
        )
    }

    private class func present(
        content: Content,
        from fromViewController: UIViewController,
        delegate: ForwardMessageDelegate,
    ) {
        let sheet = ForwardMessageViewController(content: content)
        sheet.forwardMessageDelegate = delegate
        fromViewController.present(sheet, animated: true) {
            UIApplication.shared.hideKeyboard()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        ensureBottomFooterVisibility()

        DispatchQueue.main.async {
            self.pickerVC.updateTableMargins()
        }
    }

    private func ensureBottomFooterVisibility() {
        AssertIsOnMainThread()

        if selectedConversations.allSatisfy({ $0.outgoingMessageType == .storyMessage }) {
            pickerVC.approvalTextMode = .none
        } else {
            let placeholderText = OWSLocalizedString(
                "FORWARD_MESSAGE_TEXT_PLACEHOLDER",
                comment: "Indicates that the user can add a text message to forwarded messages.",
            )
            pickerVC.approvalTextMode = .active(placeholderText: placeholderText)
        }

        pickerVC.shouldHideBottomFooter = selectedConversations.isEmpty
    }

    private func maximizeHeight() {
        sheetPresentationController?.animateChanges {
            sheetPresentationController?.selectedDetentIdentifier = .large
        }
    }
}

extension ForwardMessageViewController: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        forwardMessageDelegate?.forwardMessageFlowDidCancel()
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        // Alleviates an issue where the keyboard layout guide gets positioned
        // wrong after swiping between detents.
        DispatchQueue.main.async {
            sheetPresentationController.animateChanges {
                self.pickerVC.bottomFooter?.setNeedsLayout()
                self.pickerVC.bottomFooter?.layoutIfNeeded()
            }
        }
    }
}

// MARK: - Sending

extension ForwardMessageViewController {
    func sendStep() {
        AssertIsOnMainThread()

        Task {
            await _tryToSend()
        }
    }

    private func _tryToSend() async {
        let content = self.content
        let textMessage = self.textMessage?.strippedOrNil

        let recipientConversations = self.selectedConversations
        do {
            let outgoingMessageRecipientThreads = try await self.outgoingMessageRecipientThreads(for: recipientConversations)
            try SSKEnvironment.shared.databaseStorageRef.write { transaction in
                for recipientThread in outgoingMessageRecipientThreads {
                    // We're sending a message to this thread, approve any pending message request
                    ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(
                        recipientThread,
                        setDefaultTimerIfNecessary: true,
                        tx: transaction,
                    )
                }

                func hasRenderableContent(interaction: TSInteraction, tx: DBReadTransaction) -> Bool {
                    guard let message = interaction as? TSMessage else {
                        return false
                    }
                    return message.hasRenderableContent(tx: tx)
                }

                // Make sure the message and its content haven't been deleted (view-once
                // messages, remove delete, disappearing messages, manual deletion, etc.).
                for item in content.allItems where item.interaction != nil {
                    guard
                        let interactionId = item.interaction?.uniqueId,
                        let latestInteraction = TSInteraction.anyFetch(
                            uniqueId: interactionId,
                            transaction: transaction,
                            ignoreCache: true,
                        ),
                        hasRenderableContent(interaction: latestInteraction, tx: transaction)
                    else {
                        throw ForwardError.missingInteraction
                    }
                }
            }

            // TODO: Ideally we would enqueue all with a single write transaction.

            // Maintain order of interactions.
            let sortedItems = content.allItems.sorted { lhs, rhs in
                lhs.interaction?.sortId ?? 0 < rhs.interaction?.sortId ?? 0
            }
            // _Enqueue_ each item serially.
            for item in sortedItems {
                try await self.send(item: item, toOutgoingMessageRecipientThreads: outgoingMessageRecipientThreads)
            }
            // The user may have added an additional text message to the forward.
            // It should be sent last.
            if let textMessage {
                let messageBody = MessageBody(text: textMessage, ranges: .empty)
                await enqueueMessageViaThreadUtil(toRecipientThreads: outgoingMessageRecipientThreads) { recipientThread in
                    self.send(body: messageBody, recipientThread: recipientThread)
                }
            }

            self.forwardMessageDelegate?.forwardMessageFlowDidComplete(
                items: content.allItems,
                recipientThreads: outgoingMessageRecipientThreads,
            )
        } catch {
            owsFailDebug("Error: \(error)")

            Self.showAlertForForwardError(error: error, forwardedInteractionCount: content.allItems.count)
        }
    }

    private func send(item: ForwardMessageItem, toOutgoingMessageRecipientThreads outgoingMessageRecipientThreads: [TSThread]) async throws {
        if let stickerMetadata = item.stickerMetadata {
            let stickerInfo = stickerMetadata.stickerInfo
            if StickerManager.isStickerInstalled(stickerInfo: stickerInfo) {
                await enqueueMessageViaThreadUtil(toRecipientThreads: outgoingMessageRecipientThreads) { recipientThread in
                    self.send(installedSticker: stickerInfo, thread: recipientThread)
                }
            } else {
                guard let stickerAttachment = item.stickerAttachment else {
                    throw OWSAssertionError("Missing stickerAttachment.")
                }
                let stickerData = try stickerAttachment.decryptedRawData()
                await enqueueMessageViaThreadUtil(toRecipientThreads: outgoingMessageRecipientThreads) { recipientThread in
                    self.send(uninstalledSticker: stickerMetadata, stickerData: stickerData, thread: recipientThread)
                }
            }
        } else if let contactShare = item.contactShare {
            await enqueueMessageViaThreadUtil(toRecipientThreads: outgoingMessageRecipientThreads) { recipientThread in
                self.send(contactShare: contactShare.copyForResending(), thread: recipientThread)
            }
        } else if !item.attachments.isEmpty {
            // TODO: What about link previews in this case?
            let conversations = selectedConversations
            _ = try await AttachmentMultisend.enqueueApprovedMedia(
                conversations: conversations,
                approvedMessageBody: item.messageBody,
                approvedAttachments: ApprovedAttachments(nonViewOnceAttachments: item.attachments, imageQuality: .high),
            )
        } else if let textAttachment = item.textAttachment {
            // TODO: we want to reuse the uploaded link preview image attachment instead of re-uploading
            // if the original was sent recently (if not the image could be stale)
            _ = try await AttachmentMultisend.enqueueTextAttachment(
                textAttachment.asUnsentAttachment(),
                to: selectedConversations,
            )
        } else if let messageBody = item.messageBody {
            let linkPreviewDraft = item.linkPreviewDraft
            await enqueueMessageViaThreadUtil(toRecipientThreads: outgoingMessageRecipientThreads) { recipientThread in
                self.send(body: messageBody, linkPreviewDraft: linkPreviewDraft, recipientThread: recipientThread)
            }

            // Send the text message to any selected story recipients as a text story
            // with default styling.
            _ = try await StorySharing.enqueueTextStory(with: messageBody, linkPreviewDraft: linkPreviewDraft, to: selectedConversations)
        } else {
            throw ForwardError.invalidInteraction
        }
    }

    private func send(body: MessageBody, linkPreviewDraft: OWSLinkPreviewDraft? = nil, recipientThread: TSThread) {
        let body = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return body.forForwarding(to: recipientThread, transaction: transaction).asMessageBodyForForwarding()
        }
        ThreadUtil.enqueueMessage(
            body: body,
            thread: recipientThread,
            linkPreviewDraft: linkPreviewDraft,
        )
    }

    private func send(contactShare: ContactShareDraft, thread: TSThread) {
        ThreadUtil.enqueueMessage(withContactShare: contactShare, thread: thread)
    }

    private func send(installedSticker stickerInfo: StickerInfo, thread: TSThread) {
        ThreadUtil.enqueueMessage(withInstalledSticker: stickerInfo, thread: thread)
    }

    private func send(uninstalledSticker stickerMetadata: any StickerMetadata, stickerData: Data, thread: TSThread) {
        ThreadUtil.enqueueMessage(withUninstalledSticker: stickerMetadata, stickerData: stickerData, thread: thread)
    }

    private func enqueueMessageViaThreadUtil(
        toRecipientThreads recipientThreads: [TSThread],
        enqueueBlock: (TSThread) -> Void,
    ) async {
        for recipientThread in recipientThreads {
            enqueueBlock(recipientThread)
        }
        // This should be changed in the future, but waiting on this queue will
        // ensure that `enqueueBlock` (the prior line) has finished its work.
        try? await ThreadUtil.enqueueSendQueue.enqueue(operation: {}).value
    }

    private func outgoingMessageRecipientThreads(for conversationItems: [ConversationItem]) async throws -> [TSThread] {
        guard conversationItems.count > 0 else {
            throw OWSAssertionError("No recipients.")
        }

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        return try await databaseStorage.awaitableWrite { transaction in
            try conversationItems.lazy.filter { $0.outgoingMessageType == .message }.map {
                guard let thread = $0.getOrCreateThread(transaction: transaction) else {
                    throw ForwardError.missingThread
                }
                return thread
            }
        }
    }
}

// MARK: -

extension ForwardMessageViewController: ConversationPickerDelegate {
    func conversationPickerSelectionDidChange(_ conversationPickerViewController: ConversationPickerViewController) {
        ensureBottomFooterVisibility()
    }

    func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController) {
        self.textMessage = conversationPickerViewController.textInput?.strippedOrNil

        sendStep()
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

    func conversationPickerDidBeginEditingText() {
        AssertIsOnMainThread()

        maximizeHeight()
    }

    func conversationPickerSearchBarActiveDidChange(_ conversationPickerViewController: ConversationPickerViewController) {
        maximizeHeight()
    }
}

// MARK: -

extension ForwardMessageViewController {
    static func finalizeForward(
        items: [ForwardMessageItem],
        recipientThreads: [TSThread],
        fromViewController: UIViewController,
    ) {
        let toast: String
        if items.count > 1 {
            toast = OWSLocalizedString(
                "FORWARD_MESSAGE_MESSAGES_SENT_N",
                comment: "Indicates that multiple messages were forwarded.",
            )
        } else {
            toast = OWSLocalizedString(
                "FORWARD_MESSAGE_MESSAGES_SENT_1",
                comment: "Indicates that a single message was forwarded.",
            )
        }
        fromViewController.presentToast(text: toast)
    }
}

// MARK: -

enum ForwardError: Error {
    case missingInteraction
    case missingThread
    case invalidInteraction
}

// MARK: -

extension ForwardMessageViewController {

    static func showAlertForForwardError(
        error: Error,
        forwardedInteractionCount: Int,
    ) {
        let genericErrorMessage = (forwardedInteractionCount > 1
            ? OWSLocalizedString(
                "ERROR_COULD_NOT_FORWARD_MESSAGES_N",
                comment: "Error indicating that messages could not be forwarded.",
            )
            : OWSLocalizedString(
                "ERROR_COULD_NOT_FORWARD_MESSAGES_1",
                comment: "Error indicating that a message could not be forwarded.",
            ))

        guard let forwardError = error as? ForwardError else {
            owsFailDebug("Error: \(error).")
            OWSActionSheets.showErrorAlert(message: genericErrorMessage)
            return
        }

        switch forwardError {
        case .missingInteraction:
            let message = (forwardedInteractionCount > 1
                ? OWSLocalizedString(
                    "ERROR_COULD_NOT_FORWARD_MESSAGES_MISSING_N",
                    comment: "Error indicating that messages could not be forwarded.",
                )
                : OWSLocalizedString(
                    "ERROR_COULD_NOT_FORWARD_MESSAGES_MISSING_1",
                    comment: "Error indicating that a message could not be forwarded.",
                ))
            OWSActionSheets.showErrorAlert(message: message)
        case .missingThread, .invalidInteraction:
            owsFailDebug("Error: \(error).")

            OWSActionSheets.showErrorAlert(message: genericErrorMessage)
        }
    }
}

// MARK: -

struct ForwardMessageItem {
    let interaction: TSInteraction?

    let attachments: [PreviewableAttachment]
    let contactShare: ContactShareViewModel?
    let messageBody: MessageBody?
    let linkPreviewDraft: OWSLinkPreviewDraft?
    let stickerMetadata: (any StickerMetadata)?
    let stickerAttachment: AttachmentStream?
    let textAttachment: TextAttachment?

    fileprivate init(
        interaction: TSInteraction? = nil,
        attachments: [PreviewableAttachment] = [],
        contactShare: ContactShareViewModel? = nil,
        messageBody: MessageBody? = nil,
        linkPreviewDraft: OWSLinkPreviewDraft? = nil,
        stickerMetadata: (any StickerMetadata)? = nil,
        stickerAttachment: AttachmentStream? = nil,
        textAttachment: TextAttachment? = nil,
    ) {
        self.interaction = interaction
        self.attachments = attachments
        self.contactShare = contactShare
        self.messageBody = messageBody
        self.linkPreviewDraft = linkPreviewDraft
        self.stickerMetadata = stickerMetadata
        self.stickerAttachment = stickerAttachment
        self.textAttachment = textAttachment
    }

    fileprivate static func build(
        interaction: TSInteraction,
        componentState: CVComponentState,
        selectionType: CVSelectionType,
        transaction: DBReadTransaction,
    ) throws -> Self {
        let shouldHaveText = (selectionType == .allContent || selectionType == .secondaryContent)
        let shouldHaveAttachments = (selectionType == .allContent || selectionType == .primaryContent)

        guard shouldHaveText || shouldHaveAttachments else {
            throw ForwardError.invalidInteraction
        }

        var messageBody: MessageBody?
        var linkPreviewDraft: OWSLinkPreviewDraft?
        if
            shouldHaveText,
            let displayableBodyText = componentState.displayableBodyText,
            !displayableBodyText.fullTextValue.isEmpty
        {
            switch displayableBodyText.fullTextValue {
            case .text(let text):
                messageBody = MessageBody(text: text, ranges: .empty)
            case .attributedText(let text):
                messageBody = MessageBody(text: text.string, ranges: .empty)
            case .messageBody(let hydratedBody):
                messageBody = hydratedBody.asMessageBodyForForwarding(preservingAllMentions: true)
            }

            if let linkPreview = componentState.linkPreviewModel, let message = interaction as? TSMessage {
                linkPreviewDraft = Self.tryToCloneLinkPreview(
                    linkPreview: linkPreview,
                    parentMessage: message,
                    transaction: transaction,
                )
            }
        }

        var attachments: [PreviewableAttachment] = []
        var contactShare: ContactShareViewModel?
        var stickerMetadata: (any StickerMetadata)?
        var stickerAttachment: AttachmentStream?
        if shouldHaveAttachments {
            if let oldContactShare = componentState.contactShareModel {
                contactShare = oldContactShare.copyForRendering()
            }

            var attachmentStreams = [ReferencedAttachmentStream]()
            attachmentStreams.append(contentsOf: componentState.bodyMediaAttachmentStreams)
            if let attachmentStream = componentState.audioAttachmentStream {
                attachmentStreams.append(attachmentStream)
            }
            if let attachmentStream = componentState.genericAttachmentStream {
                attachmentStreams.append(attachmentStream)
            }

            attachments = try attachmentStreams.map { attachmentStream in
                try SignalAttachmentCloner.cloneAsSignalAttachment(attachment: attachmentStream)
            }

            stickerMetadata = componentState.stickerMetadata
            stickerAttachment = (stickerMetadata != nil) ? componentState.stickerAttachment : nil
        }

        let isEmpty: Bool = (
            attachments.isEmpty
                && contactShare == nil
                && messageBody == nil
                && stickerMetadata == nil,
        )
        guard !isEmpty else {
            throw ForwardError.invalidInteraction
        }

        return Self(
            interaction: interaction,
            attachments: attachments,
            contactShare: contactShare,
            messageBody: messageBody,
            linkPreviewDraft: linkPreviewDraft,
            stickerMetadata: stickerMetadata,
            stickerAttachment: stickerAttachment,
        )
    }

    private static func tryToCloneLinkPreview(
        linkPreview: OWSLinkPreview,
        parentMessage: TSMessage,
        transaction: DBReadTransaction,
    ) -> OWSLinkPreviewDraft? {
        guard
            let urlString = linkPreview.urlString,
            let url = URL(string: urlString)
        else {
            owsFailDebug("Missing or invalid urlString.")
            return nil
        }
        struct LinkPreviewImage {
            let imageData: Data
            let mimetype: String

            static func load(
                attachmentId: Attachment.IDType,
                transaction: DBReadTransaction,
            ) -> LinkPreviewImage? {
                guard
                    let attachment = DependenciesBridge.shared.attachmentStore
                        .fetch(id: attachmentId, tx: transaction)?
                        .asStream()
                else {
                    owsFailDebug("Missing attachment.")
                    return nil
                }
                guard let mimeType = attachment.mimeType.nilIfEmpty else {
                    owsFailDebug("Missing mimeType.")
                    return nil
                }
                do {
                    let imageData = try attachment.decryptedRawData()
                    return LinkPreviewImage(imageData: imageData, mimetype: mimeType)
                } catch {
                    owsFailDebug("Error: \(error).")
                    return nil
                }
            }
        }
        var linkPreviewImage: LinkPreviewImage?
        if
            let parentMessageRowId = parentMessage.sqliteRowId,
            let imageAttachmentId = DependenciesBridge.shared.attachmentStore.fetchAnyReference(
                owner: .messageLinkPreview(messageRowId: parentMessageRowId),
                tx: transaction,
            )?.attachmentRowId,
            let image = LinkPreviewImage.load(
                attachmentId: imageAttachmentId,
                transaction: transaction,
            )
        {
            linkPreviewImage = image
        }
        return OWSLinkPreviewDraft(
            url: url,
            title: linkPreview.title,
            imageData: linkPreviewImage?.imageData,
            imageMimeType: linkPreviewImage?.mimetype,
            previewDescription: linkPreview.previewDescription,
            date: linkPreview.date,
            isForwarded: true,
        )
    }
}

// MARK: -

private struct ForwardMessageContent {
    let allItems: [ForwardMessageItem]

    var canSendToStories: Bool {
        return allItems.allSatisfy { item in
            if !item.attachments.isEmpty {
                return item.attachments.allSatisfy({ $0.isImage || $0.isVideo })
            } else if item.textAttachment != nil {
                return true
            } else if item.messageBody != nil {
                return true
            } else {
                return false
            }
        }
    }

    var canSendToNonStories: Bool {
        return allItems.allSatisfy { $0.textAttachment == nil }
    }

    static func build(
        itemViewModel: CVItemViewModelImpl,
        tx: DBReadTransaction,
    ) throws -> Self {
        return Self(allItems: [try ForwardMessageItem.build(
            interaction: itemViewModel.interaction,
            componentState: itemViewModel.renderItem.componentState,
            selectionType: .allContent,
            transaction: tx,
        )])
    }

    static func build(
        selectionItems: [CVSelectionItem],
        tx: DBReadTransaction,
    ) throws -> Self {
        let items = try selectionItems.map { selectionItem throws -> ForwardMessageItem in
            let interactionId = selectionItem.interactionId
            guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId, transaction: tx) else {
                throw ForwardError.missingInteraction
            }
            let componentState = try buildComponentState(interaction: interaction, tx: tx)
            return try ForwardMessageItem.build(
                interaction: interaction,
                componentState: componentState,
                selectionType: selectionItem.selectionType,
                transaction: tx,
            )
        }
        return Self(allItems: items)
    }

    private static func buildComponentState(
        interaction: TSInteraction,
        tx: DBReadTransaction,
    ) throws(ForwardError) -> CVComponentState {
        guard
            let componentState = CVLoader.buildStandaloneComponentState(
                interaction: interaction,
                spoilerState: SpoilerRenderState(), // Nothing revealed, doesn't matter.
                transaction: tx,
            )
        else {
            throw .invalidInteraction
        }
        return componentState
    }
}
