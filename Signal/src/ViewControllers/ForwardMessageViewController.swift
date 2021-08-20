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
class ForwardMessageViewController: InteractiveSheetViewController {

    public weak var forwardMessageDelegate: ForwardMessageDelegate?

    public typealias Item = ForwardMessageItem
    fileprivate typealias Content = ForwardMessageContent
    fileprivate typealias RecipientThread = ForwardMessageRecipientThread

    fileprivate var content: Content

    fileprivate var textMessage: String?

    private let selection = ConversationPickerSelection()
    var selectedConversations: [ConversationItem] { selection.conversations }

    fileprivate var currentMentionableAddresses: [SignalServiceAddress] = []

    private init(content: Content) {
        self.content = content

        super.init()

        selectRecipientsStep()
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

    private class func present(content: Content,
                               from fromViewController: UIViewController,
                               delegate: ForwardMessageDelegate) {
        let sheet = ForwardMessageViewController(content: content)
        sheet.forwardMessageDelegate = delegate
        fromViewController.present(sheet, animated: true, completion: nil)
    }

    private let header = UIStackView()
    private var pickerVC: ConversationPickerViewController?

    private func selectRecipientsStep() {

        let handle = UIView()
        handle.backgroundColor = Theme.tableView2PresentedSeparatorColor
        handle.autoSetDimensions(to: CGSize(width: 36, height: 5))
        handle.layer.cornerRadius = 5 / 2

        let handleContainer = UIView()
        handleContainer.addSubview(handle)
        handle.autoPinHeightToSuperview(withMargin: 12)
        handle.autoHCenterInSuperview()

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("FORWARD_MESSAGE_TITLE",
                                            comment: "Title for the 'forward message(s)' view.")
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = UIFont.ows_dynamicTypeBody.ows_semibold

        func buildButton(icon: ThemeIcon, handler: @escaping () -> Void) -> UIView {
            let button = OWSButton(block: handler)
            let iconSize: CGFloat = 20
            let padding: CGFloat = 4
            button.imageEdgeInsets = UIEdgeInsets(hMargin: padding, vMargin: padding)
            button.autoSetDimensions(to: .square(iconSize + padding * 2))
            button.setTemplateImage(Theme.iconImage(icon), tintColor: Theme.primaryIconColor)
            return button
        }
        let cancelButton = buildButton(icon: .cancel20) { [weak self] in
            self?.forwardMessageDelegate?.forwardMessageFlowDidCancel()
            self?.dismiss(animated: true)
        }
        let searchButton = buildButton(icon: .settingsSearch) { [weak self] in
            self?.selectSearchBar()
        }

        let spacerFactory = SpacerFactory()
        header.addArrangedSubviews([
            cancelButton,
            spacerFactory.buildHSpacer(),
            titleLabel,
            spacerFactory.buildHSpacer(),
            searchButton
        ])
        spacerFactory.finalizeSpacers()
        header.axis = .horizontal
        header.spacing = 16
        header.alignment = .center
        header.layoutMargins = UIEdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16)
        header.isLayoutMarginsRelativeArrangement = true
        header.addBackgroundView(withBackgroundColor: Theme.actionSheetBackgroundColor)

        let pickerVC = ConversationPickerViewController(selection: selection)
        pickerVC.shouldShowSearchBar = false
        pickerVC.shouldHideSearchBarIfCancelled = true
        pickerVC.pickerDelegate = self
        self.pickerVC = pickerVC
        self.addChild(pickerVC)
        let pickerView = pickerVC.view!

        let stackView = UIStackView(arrangedSubviews: [
                                        handleContainer,
                                        header,
                                        pickerView ])
        stackView.axis = .vertical
        stackView.alignment = .fill

        self.contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
    }

    fileprivate func selectSearchBar() {
        AssertIsOnMainThread()

        pickerVC?.selectSearchBar()
        ensureHeaderVisibility()
    }

    fileprivate func ensureHeaderVisibility() {
        AssertIsOnMainThread()

        guard let pickerVC = pickerVC else {
            owsFailDebug("Missing pickerVC.")
            return
        }

        header.isHidden = pickerVC.isSearchBarActive
        if pickerVC.isSearchBarActive {
            maximizeHeight()
        }
    }

    public override func willDismissInteractively() {
        AssertIsOnMainThread()

        forwardMessageDelegate?.forwardMessageFlowDidCancel()
    }

    override var renderExternalHandle: Bool { false }
    override var minHeight: CGFloat { 576 }

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
            title: NSLocalizedString("FORWARD_MESSAGE_FIRST_FORWARD_TITLE",
                                     comment: "Title for alert with information about forwarding messages."),
            message: NSLocalizedString("FORWARD_MESSAGE_FIRST_FORWARD_MESSAGE",
                                     comment: "Message for alert with information about forwarding messages.")
            )

        let actionTitle: String
        if content.allItems.count > 1 {
            let format = NSLocalizedString("FORWARD_MESSAGE_FIRST_FORWARD_PROCEED_N_FORMAT",
                                           comment: "Format for label for button to proceed with forwarding multiple messages. Embeds: {{ the number of forwarded messages. }}")
            actionTitle = String(format: format, OWSFormat.formatInt(content.allItems.count))
        } else {
            actionTitle = NSLocalizedString("FORWARD_MESSAGE_FIRST_FORWARD_PROCEED_1",
                                          comment: "Label for button to proceed with forwarding a single message.")
        }
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
                var promises: [Promise<Void>] = sortedItems.map { item in
                    self.send(item: item, toRecipientThreads: recipientThreads)
                }
                if let textMessage = textMessage {
                    let messageBody = MessageBody(text: textMessage, ranges: .empty)
                    let textMessagePromise = self.send(toRecipientThreads: recipientThreads) { recipientThread in
                        self.send(body: messageBody,
                                  linkPreviewDraft: nil,
                                  thread: recipientThread.thread)
                    }
                    promises.append(textMessagePromise)
                }
                return when(resolved: promises).asVoid()
            }.map(on: .main) {
                let threads = recipientThreads.map { $0.thread }
                self.forwardMessageDelegate?.forwardMessageFlowDidComplete(items: content.allItems,
                                                                           recipientThreads: threads)
            }
        }.catch(on: .main) { error in
            owsFailDebug("Error: \(error)")

            Self.showAlertForForwardError(error: error, forwardedInteractionCount: content.allItems.count)
        }
    }

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
            let conversations = selectedConversations
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

extension ForwardMessageViewController: ConversationPickerDelegate {
    func conversationPickerSelectionDidChange(_ conversationPickerViewController: ConversationPickerViewController) {
        updateCurrentMentionableAddresses()
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

    var conversationPickerHasTextInput: Bool { true }

    var conversationPickerTextInputDefaultText: String? {
        NSLocalizedString("FORWARD_MESSAGE_TEXT_PLACEHOLDER",
                          comment: "Indicates that the user can add a text message to forwarded messages.")
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

extension ForwardMessageViewController {
    public static func finalizeForward(items: [Item],
                                       recipientThreads: [TSThread],
                                       fromViewController: UIViewController) {
        let toast: String
        if items.count > 1 {
            toast = NSLocalizedString("FORWARD_MESSAGE_MESSAGES_SENT_N",
                                      comment: "Indicates that multiple messages were forwarded.")
        } else {
            toast = NSLocalizedString("FORWARD_MESSAGE_MESSAGES_SENT_1",
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
                                  selectionType: CVSelectionType,
                                  transaction: SDSAnyReadTransaction) throws -> Item {

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

    static func build(items: [Item]) -> ForwardMessageContent {
        if items.count == 1, let item = items.first {
            return .single(item: item)
        } else {
            return .multiple(items: items)
        }
    }

    static func build(itemViewModels: [CVItemViewModelImpl],
                      transaction: SDSAnyReadTransaction) throws -> ForwardMessageContent {
        let items: [Item] = try itemViewModels.map { itemViewModel in
            try Item.build(interaction: itemViewModel.interaction,
                           componentState: itemViewModel.renderItem.componentState,
                           selectionType: .allContent,
                           transaction: transaction)
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
                                  selectionType: selectionItem.selectionType,
                                  transaction: transaction)
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
