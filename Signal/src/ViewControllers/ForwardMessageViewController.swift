//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit

public protocol ForwardMessageDelegate: AnyObject {
    func forwardMessageFlowDidComplete(items: [ForwardMessageItem],
                                       recipientThreads: [TSThread])
    func forwardMessageFlowDidCancel()
}

// MARK: -

@objc
class ForwardMessageViewController: InteractiveSheetViewController {

    private let pickerVC: ForwardPickerViewController
    private let forwardNavigationViewController = ForwardNavigationViewController()

    override var interactiveScrollViews: [UIScrollView] { [ pickerVC.tableView ] }

    public weak var forwardMessageDelegate: ForwardMessageDelegate?

    public typealias Item = ForwardMessageItem
    fileprivate typealias Content = ForwardMessageContent

    fileprivate var content: Content

    fileprivate var textMessage: String?

    private let selection = ConversationPickerSelection()
    var selectedConversations: [ConversationItem] { selection.conversations }

    override var sheetBackgroundColor: UIColor {
        ForwardPickerViewController.tableBackgroundColor(isUsingPresentedStyle: true)
    }

    private init(content: Content) {
        self.content = content
        self.pickerVC = ForwardPickerViewController(selection: selection)

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

        selectRecipientsStep()

        minimizedHeight = 576
    }

    required init() {
        fatalError("init() has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public class func present(forItemViewModels itemViewModels: [CVItemViewModelImpl],
                              from fromViewController: UIViewController,
                              delegate: ForwardMessageDelegate) {
        do {
            let content: Content = try Self.databaseStorage.read { transaction in
                try Content.build(itemViewModels: itemViewModels, transaction: transaction)
            }
            present(content: content, from: fromViewController, delegate: delegate)
        } catch {
            ForwardMessageViewController.showAlertForForwardError(error: error,
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
            ForwardMessageViewController.showAlertForForwardError(error: error,
                                                                        forwardedInteractionCount: selectionItems.count)
        }
    }

    public class func present(
        forAttachmentStreams attachmentStreams: [TSAttachmentStream],
        fromMessage message: TSMessage,
        from fromViewController: UIViewController,
        delegate: ForwardMessageDelegate
    ) {
        do {
            let builder = Item.Builder(interaction: message)

            builder.attachments = try attachmentStreams.map { attachmentStream in
                try attachmentStream.cloneAsSignalAttachment()
            }

            let item: Item = builder.build()

            present(
                content: .single(item: item),
                from: fromViewController,
                delegate: delegate
            )
        } catch let error {
            ForwardMessageViewController.showAlertForForwardError(
                error: error,
                forwardedInteractionCount: 1
            )
        }
    }

    public class func present(
        forStoryMessage storyMessage: StoryMessage,
        from fromViewController: UIViewController,
        delegate: ForwardMessageDelegate
    ) {
        let builder = Item.Builder()
        switch storyMessage.attachment {
        case .file(let attachmentId):
            guard let attachmentStream = databaseStorage.read(block: {
                TSAttachmentStream.anyFetchAttachmentStream(uniqueId: attachmentId, transaction: $0)
            }) else {
                ForwardMessageViewController.showAlertForForwardError(
                    error: OWSAssertionError("Missing attachment stream for forwarded story message"),
                    forwardedInteractionCount: 1
                )
                return
            }
            do {
                let signalAttachment = try attachmentStream.cloneAsSignalAttachment()
                builder.attachments = [signalAttachment]
            } catch {
                ForwardMessageViewController.showAlertForForwardError(
                    error: error,
                    forwardedInteractionCount: 1
                )
                return
            }
        case .text(let textAttachment):
            builder.textAttachment = textAttachment
        }
        present(content: .single(item: builder.build()), from: fromViewController, delegate: delegate)
    }

    private class func present(content: Content,
                               from fromViewController: UIViewController,
                               delegate: ForwardMessageDelegate) {

        let sheet = ForwardMessageViewController(content: content)
        sheet.forwardMessageDelegate = delegate
        fromViewController.present(sheet, animated: true) {
            UIApplication.shared.hideKeyboard()
        }
    }

    public override func themeDidChange() {
        super.themeDidChange()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        ensureBottomFooterVisibility()
    }

    private func selectRecipientsStep() {
        pickerVC.forwardMessageViewController = self
        pickerVC.shouldShowSearchBar = false
        pickerVC.shouldHideSearchBarIfCancelled = true
        pickerVC.pickerDelegate = self
        pickerVC.shouldBatchUpdateIdentityKeys = true

        forwardNavigationViewController.forwardMessageViewController = self
        forwardNavigationViewController.viewControllers = [ pickerVC ]
        self.addChild(forwardNavigationViewController)

        let navView = forwardNavigationViewController.view!
        self.contentView.addSubview(navView)
        navView.autoPinEdgesToSuperviewEdges()
    }

    fileprivate func selectSearchBar() {
        AssertIsOnMainThread()

        pickerVC.selectSearchBar()
        ensureHeaderVisibility()
    }

    fileprivate func ensureHeaderVisibility() {
        AssertIsOnMainThread()

        forwardNavigationViewController.setNavigationBarHidden(pickerVC.isSearchBarActive, animated: false)
        if pickerVC.isSearchBarActive {
            maximizeHeight()
        }
    }

    fileprivate func ensureBottomFooterVisibility() {
        AssertIsOnMainThread()

        if selectedConversations.allSatisfy({ $0.outgoingMessageClass == OutgoingStoryMessage.self }) {
            pickerVC.approvalTextMode = .none
        } else {
            let placeholderText = OWSLocalizedString(
                "FORWARD_MESSAGE_TEXT_PLACEHOLDER",
                comment: "Indicates that the user can add a text message to forwarded messages."
            )
            pickerVC.approvalTextMode = .active(placeholderText: placeholderText)
        }

        pickerVC.shouldHideBottomFooter = selectedConversations.isEmpty
    }

    public override func willDismissInteractively() {
        AssertIsOnMainThread()

        forwardMessageDelegate?.forwardMessageFlowDidCancel()
    }
}

// MARK: - Sending

extension ForwardMessageViewController {

    private static let keyValueStore = SDSKeyValueStore(collection: "ForwardMessageViewController")
    private static let hasForwardedKey = "hasForwardedKey"

    private var hasForwardedWithSneakyTransaction: Bool {
        databaseStorage.read { transaction in
            Self.keyValueStore.getBool(Self.hasForwardedKey, defaultValue: false, transaction: transaction)
        }
    }
    private static func markHasForwardedWithSneakyTransaction() {
        databaseStorage.write { transaction in
            Self.keyValueStore.setBool(true, key: Self.hasForwardedKey, transaction: transaction)
        }
    }

    func sendStep() {
        if hasForwardedWithSneakyTransaction {
            tryToSend()
        } else {
            showFirstForwardAlert()
        }
    }

    private func showFirstForwardAlert() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString("FORWARD_MESSAGE_FIRST_FORWARD_TITLE",
                                     comment: "Title for alert with information about forwarding messages."),
            message: OWSLocalizedString("FORWARD_MESSAGE_FIRST_FORWARD_MESSAGE",
                                     comment: "Message for alert with information about forwarding messages.")
            )

        let format = OWSLocalizedString("FORWARD_MESSAGE_FIRST_FORWARD_PROCEED_%d", tableName: "PluralAware",
                                       comment: "Format for label for button to proceed with forwarding multiple messages. Embeds: {{ the number of forwarded messages. }}")
        let actionTitle = String.localizedStringWithFormat(format, content.allItems.count)
        actionSheet.addAction(ActionSheetAction(title: actionTitle) { [weak self] _ in
            Self.markHasForwardedWithSneakyTransaction()

            self?.tryToSend()
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func tryToSend() {
        AssertIsOnMainThread()

        do {
            try tryToSendThrows()
        } catch {
            owsFailDebug("Error: \(error)")

            self.forwardMessageDelegate?.forwardMessageFlowDidCancel()
        }
    }

    private func tryToSendThrows() throws {
        let content = self.content
        let textMessage = self.textMessage?.strippedOrNil

        let recipientConversations = self.selectedConversations
        firstly(on: DispatchQueue.global()) {
            self.outgoingMessageRecipientThreads(for: recipientConversations)
        }.then(on: DispatchQueue.main) { (outgoingMessageRecipientThreads: [TSThread]) -> Promise<Void> in
            try Self.databaseStorage.write { transaction in
                for recipientThread in outgoingMessageRecipientThreads {
                    // We're sending a message to this thread, approve any pending message request
                    ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimer(thread: recipientThread,
                                                                                                    transaction: transaction)
                }

                func hasRenderableContent(interaction: TSInteraction) -> Bool {
                    guard let message = interaction as? TSMessage else {
                        return false
                    }
                    return message.hasRenderableContent()
                }

                // Make sure the message and its content haven't been deleted (view-once
                // messages, remove delete, disappearing messages, manual deletion, etc.).
                for item in content.allItems where item.interaction != nil {
                    guard
                        let interactionId = item.interaction?.uniqueId,
                        let latestInteraction = TSInteraction.anyFetch(
                            uniqueId: interactionId,
                            transaction: transaction
                        ),
                        hasRenderableContent(interaction: latestInteraction)
                    else {
                        throw ForwardError.missingInteraction
                    }
                }
            }

            // TODO: Ideally we would enqueue all with a single write transaction.
            return firstly { () -> Promise<Void> in
                // Maintain order of interactions.
                let sortedItems = content.allItems.sorted { lhs, rhs in
                    lhs.interaction?.timestamp ?? 0 < rhs.interaction?.timestamp ?? 0
                }
                let promises: [Promise<Void>] = sortedItems.map { item in
                    self.send(item: item, toOutgoingMessageRecipientThreads: outgoingMessageRecipientThreads)
                }
                return firstly(on: DispatchQueue.main) { () -> Promise<Void> in
                    Promise.when(resolved: promises).asVoid()
                }.then(on: DispatchQueue.main) { _ -> Promise<Void> in
                    // The user may have added an additional text message to the forward.
                    // It should be sent last.
                    if let textMessage = textMessage {
                        let messageBody = MessageBody(text: textMessage, ranges: .empty)
                        return self.send(toRecipientThreads: outgoingMessageRecipientThreads) { recipientThread in
                            self.send(body: messageBody, recipientThread: recipientThread)
                        }
                    } else {
                        return Promise.value(())
                    }
                }
            }.map(on: DispatchQueue.main) {
                self.forwardMessageDelegate?.forwardMessageFlowDidComplete(
                    items: content.allItems,
                    recipientThreads: outgoingMessageRecipientThreads
                )
            }
        }.catch(on: DispatchQueue.main) { error in
            owsFailDebug("Error: \(error)")

            Self.showAlertForForwardError(error: error, forwardedInteractionCount: content.allItems.count)
        }
    }

    private func send(item: Item, toOutgoingMessageRecipientThreads outgoingMessageRecipientThreads: [TSThread]) -> Promise<Void> {
        AssertIsOnMainThread()

        if let stickerMetadata = item.stickerMetadata {
            let stickerInfo = stickerMetadata.stickerInfo
            if StickerManager.isStickerInstalled(stickerInfo: stickerInfo) {
                return send(toRecipientThreads: outgoingMessageRecipientThreads) { recipientThread in
                    self.send(installedSticker: stickerInfo, thread: recipientThread)
                }
            } else {
                guard let stickerAttachment = item.stickerAttachment else {
                    return Promise(error: OWSAssertionError("Missing stickerAttachment."))
                }
                do {
                    let stickerData = try stickerAttachment.readDataFromFile()
                    return send(toRecipientThreads: outgoingMessageRecipientThreads) { recipientThread in
                        self.send(uninstalledSticker: stickerMetadata,
                                  stickerData: stickerData,
                                  thread: recipientThread)
                    }
                } catch {
                    return Promise(error: error)
                }
            }
        } else if let contactShare = item.contactShare {
            return send(toRecipientThreads: outgoingMessageRecipientThreads) { recipientThread in
                if let avatarImage = contactShare.avatarImage {
                    self.databaseStorage.write { transaction in
                        contactShare.dbRecord.saveAvatarImage(avatarImage, transaction: transaction)
                    }
                }
                return self.send(contactShare: contactShare, thread: recipientThread)
            }
        } else if let attachments = item.attachments,
                  !attachments.isEmpty {
            // TODO: What about link previews in this case?
            let conversations = selectedConversations
            return AttachmentMultisend.sendApprovedMedia(conversations: conversations,
                                                         approvalMessageBody: item.messageBody,
                                                         approvedAttachments: attachments).asVoid()
        } else if let textAttachment = item.textAttachment {
            // TODO: we want to reuse the uploaded link preview image attachment instead of re-uploading
            // if the original was sent recently (if not the image could be stale)
            return AttachmentMultisend.sendTextAttachment(textAttachment.asUnsentAttachment(), to: selectedConversations).asVoid()
        } else if let messageBody = item.messageBody {
            let linkPreviewDraft = item.linkPreviewDraft
            let nonStorySendPromise = send(toRecipientThreads: outgoingMessageRecipientThreads) { recipientThread in
                self.send(
                    body: messageBody,
                    linkPreviewDraft: linkPreviewDraft,
                    recipientThread: recipientThread
                )
            }

            // Send the text message to any selected story recipients
            // as a text story with default styling.
            let storyConversations = selectedConversations.filter { $0.outgoingMessageClass == OutgoingStoryMessage.self }
            let storySendPromise = StorySharing.sendTextStory(with: messageBody, linkPreviewDraft: linkPreviewDraft, to: storyConversations)

            return Promise<Void>.when(fulfilled: [nonStorySendPromise, storySendPromise])
        } else {
            return Promise(error: ForwardError.invalidInteraction)
        }
    }

    fileprivate func send(body: MessageBody, linkPreviewDraft: OWSLinkPreviewDraft? = nil, recipientThread: TSThread) -> Promise<Void> {
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(
                body: body.forNewContext(recipientThread, transaction: transaction.unwrapGrdbRead),
                thread: recipientThread,
                linkPreviewDraft: linkPreviewDraft,
                transaction: transaction
            )
        }
        return Promise.value(())
    }

    fileprivate func send(contactShare: ContactShareViewModel, thread: TSThread) -> Promise<Void> {
        ThreadUtil.enqueueMessage(withContactShare: contactShare.dbRecord, thread: thread)
        return Promise.value(())
    }

    fileprivate func send(body: MessageBody, attachment: SignalAttachment, thread: TSThread) -> Promise<Void> {
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(body: body,
                                      mediaAttachments: [attachment],
                                      thread: thread,
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

    fileprivate func send(toRecipientThreads recipientThreads: [TSThread],
                          enqueueBlock: @escaping (TSThread) -> Promise<Void>) -> Promise<Void> {
        AssertIsOnMainThread()

        return Promise.when(fulfilled: recipientThreads.map { thread in enqueueBlock(thread) }).asVoid()
    }

    fileprivate func outgoingMessageRecipientThreads(for conversationItems: [ConversationItem]) -> Promise<[TSThread]> {
        firstly(on: DispatchQueue.global()) {
            guard conversationItems.count > 0 else {
                throw OWSAssertionError("No recipients.")
            }

            return try self.databaseStorage.write { transaction in
                try conversationItems.lazy.filter { $0.outgoingMessageClass == TSOutgoingMessage.self }.map {
                    guard let thread = $0.getOrCreateThread(transaction: transaction) else {
                        throw ForwardError.missingThread
                    }
                    return thread
                }
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
        false
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
        ensureHeaderVisibility()
    }
}

// MARK: -

extension TSAttachmentStream {
    /// The purpose of this request is to make it possible to cloneAsSignalAttachment without an instance of the original TSAttachmentStream.
    /// See the note in VideoDurationHelper for why.
    struct CloneAsSignalAttachmentRequest {
        var uniqueId: String
        fileprivate var sourceUrl: URL
        fileprivate var dataUTI: String
        fileprivate var sourceFilename: String?
        fileprivate var isVoiceMessage: Bool
        fileprivate var caption: String?
        fileprivate var isBorderless: Bool
        fileprivate var isLoopingVideo: Bool
    }

    func cloneAsSignalAttachmentRequest() throws -> CloneAsSignalAttachmentRequest {
        guard let sourceUrl = originalMediaURL else {
            throw OWSAssertionError("Missing originalMediaURL.")
        }
        guard let dataUTI = MIMETypeUtil.utiType(forMIMEType: contentType) else {
            throw OWSAssertionError("Missing dataUTI.")
        }
        return CloneAsSignalAttachmentRequest(uniqueId: self.uniqueId,
                                              sourceUrl: sourceUrl,
                                              dataUTI: dataUTI,
                                              sourceFilename: sourceFilename,
                                              isVoiceMessage: isVoiceMessage,
                                              caption: caption,
                                              isBorderless: isBorderless,
                                              isLoopingVideo: isLoopingVideo)
    }

    func cloneAsSignalAttachment() throws -> SignalAttachment {
        let request = try cloneAsSignalAttachmentRequest()
        return try Self.cloneAsSignalAttachment(request: request)
    }

    static func cloneAsSignalAttachment(request: CloneAsSignalAttachmentRequest) throws -> SignalAttachment {
        let newUrl = OWSFileSystem.temporaryFileUrl(fileExtension: request.sourceUrl.pathExtension)
        try FileManager.default.copyItem(at: request.sourceUrl, to: newUrl)

        let clonedDataSource = try DataSourcePath.dataSource(with: newUrl,
                                                             shouldDeleteOnDeallocation: true)
        clonedDataSource.sourceFilename = request.sourceFilename

        var signalAttachment: SignalAttachment
        if request.isVoiceMessage {
            signalAttachment = SignalAttachment.voiceMessageAttachment(dataSource: clonedDataSource, dataUTI: request.dataUTI)
        } else {
            signalAttachment = SignalAttachment.attachment(dataSource: clonedDataSource, dataUTI: request.dataUTI)
        }
        signalAttachment.captionText = request.caption
        signalAttachment.isBorderless = request.isBorderless
        signalAttachment.isLoopingVideo = request.isLoopingVideo
        return signalAttachment
    }
}

// MARK: -

extension ForwardMessageViewController {
    public static func finalizeForward(items: [Item],
                                       recipientThreads: [TSThread],
                                       fromViewController: UIViewController) {
        let toast: String
        if items.count > 1 {
            toast = OWSLocalizedString("FORWARD_MESSAGE_MESSAGES_SENT_N",
                                      comment: "Indicates that multiple messages were forwarded.")
        } else {
            toast = OWSLocalizedString("FORWARD_MESSAGE_MESSAGES_SENT_1",
                                      comment: "Indicates that a single message was forwarded.")
        }
        fromViewController.presentToast(text: toast)
    }
}

// MARK: -

public enum ForwardError: Error {
    case missingInteraction
    case missingThread
    case invalidInteraction
}

// MARK: -

extension ForwardMessageViewController {

    public static func showAlertForForwardError(error: Error,
                                                forwardedInteractionCount: Int) {
        let genericErrorMessage = (forwardedInteractionCount > 1
                                    ? OWSLocalizedString("ERROR_COULD_NOT_FORWARD_MESSAGES_N",
                                                        comment: "Error indicating that messages could not be forwarded.")
                                    : OWSLocalizedString("ERROR_COULD_NOT_FORWARD_MESSAGES_1",
                                                        comment: "Error indicating that a message could not be forwarded."))

        guard let forwardError = error as? ForwardError else {
            owsFailDebug("Error: \(error).")
            OWSActionSheets.showErrorAlert(message: genericErrorMessage)
            return
        }

        switch forwardError {
        case .missingInteraction:
            let message = (forwardedInteractionCount > 1
                            ? OWSLocalizedString("ERROR_COULD_NOT_FORWARD_MESSAGES_MISSING_N",
                                                comment: "Error indicating that messages could not be forwarded.")
                            : OWSLocalizedString("ERROR_COULD_NOT_FORWARD_MESSAGES_MISSING_1",
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

    let interaction: TSInteraction?

    let attachments: [SignalAttachment]?
    let contactShare: ContactShareViewModel?
    let messageBody: MessageBody?
    let linkPreviewDraft: OWSLinkPreviewDraft?
    let stickerMetadata: StickerMetadata?
    let stickerAttachment: TSAttachmentStream?
    let textAttachment: TextAttachment?

    fileprivate class Builder {
        let interaction: TSInteraction?

        var attachments: [SignalAttachment]?
        var contactShare: ContactShareViewModel?
        var messageBody: MessageBody?
        var linkPreviewDraft: OWSLinkPreviewDraft?
        var stickerMetadata: StickerMetadata?
        var stickerAttachment: TSAttachmentStream?
        var textAttachment: TextAttachment?

        init(interaction: TSInteraction? = nil) {
            self.interaction = interaction
        }

        func build() -> ForwardMessageItem {
            ForwardMessageItem(
                interaction: interaction,
                attachments: attachments,
                contactShare: contactShare,
                messageBody: messageBody,
                linkPreviewDraft: linkPreviewDraft,
                stickerMetadata: stickerMetadata,
                stickerAttachment: stickerAttachment,
                textAttachment: textAttachment
            )
        }
    }

    fileprivate var asBuilder: Builder {
        let builder = Builder(interaction: interaction)
        builder.attachments = attachments
        builder.contactShare = contactShare
        builder.messageBody = messageBody
        builder.linkPreviewDraft = linkPreviewDraft
        builder.stickerMetadata = stickerMetadata
        builder.stickerAttachment = stickerAttachment
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

    fileprivate static func build(
        interaction: TSInteraction,
        componentState: CVComponentState,
        selectionType: CVSelectionType,
        transaction: SDSAnyReadTransaction
    ) throws -> Item {

        let builder = Builder(interaction: interaction)

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

            if let linkPreview = componentState.linkPreviewModel {
                builder.linkPreviewDraft = Self.tryToCloneLinkPreview(linkPreview: linkPreview,
                                                                      transaction: transaction)
            }
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

            if !attachmentStreams.isEmpty {
                builder.attachments = try attachmentStreams.map { attachmentStream in
                    try attachmentStream.cloneAsSignalAttachment()
                }
            }

            if let stickerMetadata = componentState.stickerMetadata {
                builder.stickerMetadata = stickerMetadata

                if let stickerAttachment = componentState.stickerAttachment {
                    builder.stickerAttachment = stickerAttachment
                }
            }
        }

        let item = builder.build()
        guard !item.isEmpty else {
            throw ForwardError.invalidInteraction
        }
        return item
    }

    private static func tryToCloneLinkPreview(linkPreview: OWSLinkPreview,
                                              transaction: SDSAnyReadTransaction) -> OWSLinkPreviewDraft? {
        guard let urlString = linkPreview.urlString,
              let url = URL(string: urlString) else {
            owsFailDebug("Missing or invalid urlString.")
            return nil
        }
        struct LinkPreviewImage {
            let imageData: Data
            let mimetype: String

            static func load(attachmentId: String,
                             transaction: SDSAnyReadTransaction) -> LinkPreviewImage? {
                guard let attachment = TSAttachmentStream.anyFetchAttachmentStream(uniqueId: attachmentId,
                                                                                   transaction: transaction) else {
                    owsFailDebug("Missing attachment.")
                    return nil
                }
                guard let mimeType = attachment.contentType.nilIfEmpty else {
                    owsFailDebug("Missing mimeType.")
                    return nil
                }
                do {
                    let imageData = try attachment.readDataFromFile()
                    return LinkPreviewImage(imageData: imageData, mimetype: mimeType)
                } catch {
                    owsFailDebug("Error: \(error).")
                    return nil
                }
            }
        }
        var linkPreviewImage: LinkPreviewImage?
        if let imageAttachmentId = linkPreview.imageAttachmentId,
           let image = LinkPreviewImage.load(attachmentId: imageAttachmentId,
                                             transaction: transaction) {
            linkPreviewImage = image
        }
        let draft = OWSLinkPreviewDraft(url: url,
                                        title: linkPreview.title,
                                        imageData: linkPreviewImage?.imageData,
                                        imageMimeType: linkPreviewImage?.mimetype)
        draft.previewDescription = linkPreview.previewDescription
        draft.date = linkPreview.date
        return draft
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

    var canSendToStories: Bool {
        allItems.allSatisfy { item in
            if let attachments = item.attachments {
                return attachments.allSatisfy({ $0.isValidImage || $0.isValidVideo })
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
        allItems.allSatisfy { $0.textAttachment == nil }
    }

    private static func build(items: [Item]) -> ForwardMessageContent {
        if items.count == 1, let item = items.first {
            return .single(item: item)
        } else {
            return .multiple(items: items)
        }
    }

    fileprivate static func build(
        itemViewModels: [CVItemViewModelImpl],
        transaction: SDSAnyReadTransaction
    ) throws -> ForwardMessageContent {
        let items: [Item] = try itemViewModels.map { itemViewModel in
            try Item.build(interaction: itemViewModel.interaction,
                           componentState: itemViewModel.renderItem.componentState,
                           selectionType: .allContent,
                           transaction: transaction)
        }
        return build(items: items)
    }

    fileprivate static func build(
        selectionItems: [CVSelectionItem],
        transaction: SDSAnyReadTransaction
    ) throws -> ForwardMessageContent {
        let items: [Item] = try selectionItems.map { selectionItem in
            let interactionId = selectionItem.interactionId
            guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId,
                                                           transaction: transaction) else {
                throw ForwardError.missingInteraction
            }
            let componentState = try buildComponentState(interaction: interaction,
                                                         transaction: transaction)
            return try Item.build(interaction: interaction,
                                  componentState: componentState,
                                  selectionType: selectionItem.selectionType,
                                  transaction: transaction)
        }
        return build(items: items)
    }

    private static func buildComponentState(interaction: TSInteraction,
                                            transaction: SDSAnyReadTransaction) throws -> CVComponentState {
        guard let componentState = CVLoader.buildStandaloneComponentState(interaction: interaction,
                                                                          transaction: transaction) else {
            throw ForwardError.invalidInteraction
        }
        return componentState
    }
}

// MARK: -

private class ForwardNavigationViewController: OWSNavigationController {
    weak var forwardMessageViewController: ForwardMessageViewController?

}

// MARK: -

private class ForwardPickerViewController: ConversationPickerViewController {
    weak var forwardMessageViewController: ForwardMessageViewController?

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        updateNavigationItem()
    }

    public func updateNavigationItem() {
        title = OWSLocalizedString("FORWARD_MESSAGE_TITLE",
                                  comment: "Title for the 'forward message(s)' view.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: Theme.iconImage(.cancel24),
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(didPressCancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: Theme.iconImage(.settingsSearch),
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(didPressSearch))
    }

    @objc
    private func didPressCancel() {
        AssertIsOnMainThread()

        pickerDelegate?.conversationPickerDidCancel(self)
    }

    @objc
    private func didPressSearch() {
        AssertIsOnMainThread()

        forwardMessageViewController?.selectSearchBar()
    }
}
