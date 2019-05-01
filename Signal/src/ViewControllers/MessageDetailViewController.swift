//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc
enum MessageMetadataViewMode: UInt {
    case focusOnMessage
    case focusOnMetadata
}

@objc
protocol MessageDetailViewDelegate: AnyObject {
    func detailViewMessageWasDeleted(_ messageDetailViewController: MessageDetailViewController)
}

@objc
class MessageDetailViewController: OWSViewController {

    @objc
    weak var delegate: MessageDetailViewDelegate?

    // MARK: Properties

    let uiDatabaseConnection: YapDatabaseConnection

    var bubbleView: UIView?

    let mode: MessageMetadataViewMode
    let viewItem: ConversationViewItem
    var message: TSMessage
    var wasDeleted: Bool = false

    var messageView: OWSMessageView?
    var messageViewWidthLayoutConstraint: NSLayoutConstraint?
    var messageViewHeightLayoutConstraint: NSLayoutConstraint?

    var scrollView: UIScrollView!
    var contentView: UIView?

    var attachment: TSAttachment?
    var dataSource: DataSource?
    var attachmentStream: TSAttachmentStream?
    var messageBody: String?

    lazy var shouldShowUD: Bool = {
        return self.preferences.shouldShowUnidentifiedDeliveryIndicators()
    }()

    var conversationStyle: ConversationStyle

    private var contactShareViewHelper: ContactShareViewHelper!

    // MARK: Dependencies

    var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    var audioAttachmentPlayer: OWSAudioPlayer?

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    required init(viewItem: ConversationViewItem, message: TSMessage, thread: TSThread, mode: MessageMetadataViewMode) {
        self.viewItem = viewItem
        self.message = message
        self.mode = mode
        self.uiDatabaseConnection = OWSPrimaryStorage.shared().uiDatabaseConnection
        self.conversationStyle = ConversationStyle(thread: thread)

        super.init(nibName: nil, bundle: nil)
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        self.contactShareViewHelper = ContactShareViewHelper(contactsManager: contactsManager)
        contactShareViewHelper.delegate = self

        do {
            try updateMessageToLatest()
        } catch DetailViewError.messageWasDeleted {
            self.delegate?.detailViewMessageWasDeleted(self)
        } catch {
            owsFailDebug("unexpected error")
        }

        self.conversationStyle.viewWidth = view.width()

        self.navigationItem.title = NSLocalizedString("MESSAGE_METADATA_VIEW_TITLE",
                                                      comment: "Title for the 'message metadata' view.")

        createViews()

        self.view.layoutIfNeeded()

        NotificationCenter.default.addObserver(self,
            selector: #selector(uiDatabaseDidUpdate),
            name: .OWSUIDatabaseConnectionDidUpdate,
            object: OWSPrimaryStorage.shared().dbNotificationObject)
    }

    override public func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        Logger.debug("")

        super.viewWillTransition(to: size, with: coordinator)

        self.conversationStyle.viewWidth = size.width
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateMessageViewLayout()

        if mode == .focusOnMetadata {
            if let bubbleView = self.bubbleView {
                // Force layout.
                view.setNeedsLayout()
                view.layoutIfNeeded()

                let contentHeight = scrollView.contentSize.height
                let scrollViewHeight = scrollView.frame.size.height
                guard contentHeight >=  scrollViewHeight else {
                    // All content is visible within the scroll view. No need to offset.
                    return
                }

                // We want to include at least a little portion of the message, but scroll no farther than necessary.
                let showAtLeast: CGFloat = 50
                let bubbleViewBottom = bubbleView.superview!.convert(bubbleView.frame, to: scrollView).maxY
                let maxOffset =  bubbleViewBottom - showAtLeast
                let lastPage = contentHeight - scrollViewHeight

                let offset = CGPoint(x: 0, y: min(maxOffset, lastPage))

                scrollView.setContentOffset(offset, animated: false)
            }
        }
    }

    // MARK: - Create Views

    private func createViews() {
        view.backgroundColor = Theme.backgroundColor

        let scrollView = UIScrollView()
        self.scrollView = scrollView
        view.addSubview(scrollView)
        scrollView.autoPinWidthToSuperview(withMargin: 0)

        if scrollView.applyInsetsFix() {
            scrollView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        } else {
            scrollView.autoPinEdge(toSuperviewEdge: .top)
        }

        let contentView = UIView.container()
        self.contentView = contentView
        scrollView.addSubview(contentView)
        contentView.autoPinLeadingToSuperviewMargin()
        contentView.autoPinTrailingToSuperviewMargin()
        contentView.autoPinEdge(toSuperviewEdge: .top)
        contentView.autoPinEdge(toSuperviewEdge: .bottom)
        scrollView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.contentInset = UIEdgeInsets(top: 20, left: 0, bottom: 20, right: 0)

        if hasMediaAttachment {
            let footer = UIToolbar()
            view.addSubview(footer)
            footer.autoPinWidthToSuperview(withMargin: 0)
            footer.autoPinEdge(.top, to: .bottom, of: scrollView)
            footer.autoPin(toBottomLayoutGuideOf: self, withInset: 0)

            footer.items = [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareButtonPressed)),
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            ]
        } else {
            scrollView.autoPinEdge(toSuperviewEdge: .bottom)
        }

        updateContent()
    }

    lazy var thread: TSThread = {
        var thread: TSThread?
        self.uiDatabaseConnection.read { transaction in
            thread = self.message.thread(with: transaction)
        }
        return thread!
    }()

    private func updateContent() {
        guard let contentView = contentView else {
            owsFailDebug("Missing contentView")
            return
        }

        // Remove any existing content views.
        for subview in contentView.subviews {
            subview.removeFromSuperview()
        }

        var rows = [UIView]()

        // Content
        rows += contentRows()

        // Sender?
        if let incomingMessage = message as? TSIncomingMessage {
            let senderId = incomingMessage.authorId
            let senderName = contactsManager.contactOrProfileName(forPhoneIdentifier: senderId)
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_SENDER",
                                                         comment: "Label for the 'sender' field of the 'message metadata' view."),
                                 value: senderName))
        }

        // Recipient(s)
        if let outgoingMessage = message as? TSOutgoingMessage {

            let isGroupThread = thread.isGroupThread()

            let recipientStatusGroups: [MessageReceiptStatus] = [
                .read,
                .uploading,
                .delivered,
                .sent,
                .sending,
                .failed,
                .skipped
            ]
            for recipientStatusGroup in recipientStatusGroups {
                var groupRows = [UIView]()

                // TODO: It'd be nice to inset these dividers from the edge of the screen.
                let addDivider = {
                    let divider = UIView()
                    divider.backgroundColor = Theme.hairlineColor
                    divider.autoSetDimension(.height, toSize: CGHairlineWidth())
                    groupRows.append(divider)
                }

                let messageRecipientIds = outgoingMessage.recipientIds()

                for recipientId in messageRecipientIds {
                    guard let recipientState = outgoingMessage.recipientState(forRecipientId: recipientId) else {
                        owsFailDebug("no message status for recipient: \(recipientId).")
                        continue
                    }

                    // We use the "short" status message to avoid being redundant with the section title.
                    let (recipientStatus, shortStatusMessage, _) = MessageRecipientStatusUtils.recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage, recipientState: recipientState)

                    guard recipientStatus == recipientStatusGroup else {
                        continue
                    }

                    if groupRows.count < 1 {
                        if isGroupThread {
                            groupRows.append(valueRow(name: string(for: recipientStatusGroup),
                                                      value: ""))
                        }

                        addDivider()
                    }

                    // We use ContactCellView, not ContactTableViewCell.
                    // Table view cells don't layout properly outside the
                    // context of a table view.
                    let cellView = ContactCellView()
                    if self.shouldShowUD, recipientState.wasSentByUD {
                        let udAccessoryView = self.buildUDAccessoryView(text: shortStatusMessage)
                        cellView.setAccessory(udAccessoryView)
                    } else {
                        cellView.accessoryMessage = shortStatusMessage
                    }
                    cellView.configure(withRecipientId: recipientId)

                    let wrapper = UIView()
                    wrapper.layoutMargins = UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
                    wrapper.addSubview(cellView)
                    cellView.autoPinEdgesToSuperviewMargins()
                    groupRows.append(wrapper)
                }

                if groupRows.count > 0 {
                    addDivider()

                    let spacer = UIView()
                    spacer.autoSetDimension(.height, toSize: 10)
                    groupRows.append(spacer)
                }

                Logger.verbose("\(groupRows.count) rows for \(recipientStatusGroup)")
                guard groupRows.count > 0 else {
                    continue
                }
                rows += groupRows
            }
        }

        let sentText = DateUtil.formatPastTimestampRelativeToNow(message.timestamp)
        let sentRow: UIStackView = valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_SENT_DATE_TIME",
                                                                    comment: "Label for the 'sent date & time' field of the 'message metadata' view."),
                                            value: sentText)
        if let incomingMessage = message as? TSIncomingMessage {
            if self.shouldShowUD, incomingMessage.wasReceivedByUD {
                let icon = #imageLiteral(resourceName: "ic_secret_sender_indicator").withRenderingMode(.alwaysTemplate)
                let iconView = UIImageView(image: icon)
                iconView.tintColor = Theme.secondaryColor
                iconView.setContentHuggingHigh()
                sentRow.addArrangedSubview(iconView)
                // keep the icon close to the label.
                let spacerView = UIView()
                spacerView.setContentHuggingLow()
                sentRow.addArrangedSubview(spacerView)
            }
        }

        sentRow.isUserInteractionEnabled = true
        sentRow.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(didLongPressSent)))
        rows.append(sentRow)

        if message is TSIncomingMessage {
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_RECEIVED_DATE_TIME",
                                                         comment: "Label for the 'received date & time' field of the 'message metadata' view."),
                                 value: DateUtil.formatPastTimestampRelativeToNow(message.receivedAtTimestamp)))
        }

        rows += addAttachmentMetadataRows()

        // TODO: We could include the "disappearing messages" state here.

        let rowStack = UIStackView(arrangedSubviews: rows)
        rowStack.axis = .vertical
        rowStack.spacing = 5
        contentView.addSubview(rowStack)
        rowStack.autoPinEdgesToSuperviewMargins()
        contentView.layoutIfNeeded()
        updateMessageViewLayout()
    }

    private func displayableTextIfText() -> String? {
        guard viewItem.hasBodyText else {
                return nil
        }
        guard let displayableText = viewItem.displayableBodyText else {
                return nil
        }
        let messageBody = displayableText.fullText
        guard messageBody.count > 0  else {
            return nil
        }
        return messageBody
    }

    let bubbleViewHMargin: CGFloat = 10

    private func contentRows() -> [UIView] {
        var rows = [UIView]()

        let messageView: OWSMessageView
        if viewItem.messageCellType == .stickerMessage {
            let messageStickerView = OWSMessageStickerView(frame: CGRect.zero)
            messageStickerView.delegate = self
            messageView = messageStickerView
        } else {
            let messageBubbleView = OWSMessageBubbleView(frame: CGRect.zero)
            messageBubbleView.delegate = self
            messageView = messageBubbleView
        }

        messageView.addTapGestureHandler()
        self.messageView = messageView
        messageView.viewItem = viewItem
        messageView.cellMediaCache = NSCache()
        messageView.conversationStyle = conversationStyle
        messageView.configureViews()
        messageView.loadContent()

        assert(messageView.isUserInteractionEnabled)

        let row = UIView()
        row.addSubview(messageView)
        messageView.autoPinHeightToSuperview()

        let isIncoming = self.message as? TSIncomingMessage != nil
        messageView.autoPinEdge(toSuperviewEdge: isIncoming ? .leading : .trailing, withInset: bubbleViewHMargin)

        self.messageViewWidthLayoutConstraint = messageView.autoSetDimension(.width, toSize: 0)
        self.messageViewHeightLayoutConstraint = messageView.autoSetDimension(.height, toSize: 0)
        rows.append(row)

        if rows.isEmpty {
            // Neither attachment nor body.
            owsFailDebug("Message has neither attachment nor body.")
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_NO_ATTACHMENT_OR_BODY",
                                                         comment: "Label for messages without a body or attachment in the 'message metadata' view."),
                                 value: ""))
        }

        let spacer = UIView()
        spacer.autoSetDimension(.height, toSize: 15)
        rows.append(spacer)

        return rows
    }

    private func fetchAttachment(transaction: YapDatabaseReadTransaction) -> TSAttachment? {
        // TODO: Support multi-image messages.
        guard let attachmentId = message.attachmentIds.firstObject as? String else {
            return nil
        }

        guard let attachment = TSAttachment.fetch(uniqueId: attachmentId, transaction: transaction) else {
            Logger.warn("Missing attachment. Was it deleted?")
            return nil
        }

        return attachment
    }

    var hasMediaAttachment: Bool {
        guard let attachment = self.attachment else {
            return false
        }

        guard attachment.contentType != OWSMimeTypeOversizeTextMessage else {
            // to the user, oversized text attachments should behave
            // just like regular text messages.
            return false
        }

        return true
    }

    private func addAttachmentMetadataRows() -> [UIView] {
        guard hasMediaAttachment else {
            return []
        }

        var rows = [UIView]()

        if let attachment = self.attachment {
            // Only show MIME types in DEBUG builds.
            if _isDebugAssertConfiguration() {
                let contentType = attachment.contentType
                rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_MIME_TYPE",
                                                             comment: "Label for the MIME type of attachments in the 'message metadata' view."),
                                     value: contentType))
            }

            if let sourceFilename = attachment.sourceFilename {
                rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_SOURCE_FILENAME",
                                                             comment: "Label for the original filename of any attachment in the 'message metadata' view."),
                                     value: sourceFilename))
            }
        }

        if let dataSource = self.dataSource {
            let fileSize = dataSource.dataLength()
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_FILE_SIZE",
                                                         comment: "Label for file size of attachments in the 'message metadata' view."),
                                 value: OWSFormat.formatFileSize(UInt(fileSize))))
        }

        return rows
    }

    private func buildUDAccessoryView(text: String) -> UIView {
        let label = UILabel()
        label.textColor = Theme.secondaryColor
        label.text = text
        label.textAlignment = .right
        label.font = UIFont.ows_mediumFont(withSize: 13)

        let image = #imageLiteral(resourceName: "ic_secret_sender_indicator").withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = Theme.middleGrayColor

        let hStack = UIStackView(arrangedSubviews: [imageView, label])
        hStack.axis = .horizontal
        hStack.spacing = 8

        return hStack
    }

    private func nameLabel(text: String) -> UILabel {
        let label = UILabel()
        label.textColor = Theme.primaryColor
        label.font = UIFont.ows_mediumFont(withSize: 14)
        label.text = text
        label.setContentHuggingHorizontalHigh()
        return label
    }

    private func valueLabel(text: String) -> UILabel {
        let label = UILabel()
        label.textColor = Theme.primaryColor
        label.font = UIFont.ows_regularFont(withSize: 14)
        label.text = text
        label.setContentHuggingHorizontalLow()
        return label
    }

    private func valueRow(name: String, value: String, subtitle: String = "") -> UIStackView {
        let nameLabel = self.nameLabel(text: name)
        let valueLabel = self.valueLabel(text: value)
        let hStackView = UIStackView(arrangedSubviews: [nameLabel, valueLabel])
        hStackView.axis = .horizontal
        hStackView.spacing = 10
        hStackView.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        hStackView.isLayoutMarginsRelativeArrangement = true

        if subtitle.count > 0 {
            let subtitleLabel = self.valueLabel(text: subtitle)
            subtitleLabel.textColor = Theme.secondaryColor
            hStackView.addArrangedSubview(subtitleLabel)
        }

        return hStackView
    }

    // MARK: - Actions

    @objc func shareButtonPressed() {
        guard let attachmentStream = attachmentStream else {
            Logger.error("Share button should only be shown with attachment, but no attachment found.")
            return
        }
        AttachmentSharing.showShareUI(forAttachment: attachmentStream)
    }

    // MARK: - Actions

    enum DetailViewError: Error {
        case messageWasDeleted
    }

    // This method should be called after self.databaseConnection.beginLongLivedReadTransaction().
    private func updateMessageToLatest() throws {

        AssertIsOnMainThread()

        try self.uiDatabaseConnection.read { transaction in
            guard let uniqueId = self.message.uniqueId else {
                Logger.error("Message is missing uniqueId.")
                return
            }
            guard let newMessage = TSInteraction.fetch(uniqueId: uniqueId, transaction: transaction) as? TSMessage else {
                Logger.error("Message was deleted")
                throw DetailViewError.messageWasDeleted
            }
            self.message = newMessage
            self.attachment = self.fetchAttachment(transaction: transaction)
            self.attachmentStream = self.attachment as? TSAttachmentStream
        }
    }

    @objc internal func uiDatabaseDidUpdate(notification: NSNotification) {
        AssertIsOnMainThread()

        guard !wasDeleted else {
            // Item was deleted in the tile view gallery.
            // Don't bother re-rendering, it will fail and we'll soon be dismissed.
            return
        }

        guard let notifications = notification.userInfo?[OWSUIDatabaseConnectionNotificationsKey] as? [Notification] else {
            owsFailDebug("notifications was unexpectedly nil")
            return
        }

        guard let uniqueId = self.message.uniqueId else {
            Logger.error("Message is missing uniqueId.")
            return
        }

        guard self.uiDatabaseConnection.hasChange(forKey: uniqueId,
                                                 inCollection: TSInteraction.collection(),
                                                 in: notifications) else {
                                                    Logger.debug("No relevant changes.")
                                                    return
        }

        do {
            try updateMessageToLatest()
        } catch DetailViewError.messageWasDeleted {
            DispatchQueue.main.async {
                self.delegate?.detailViewMessageWasDeleted(self)
            }
            return
        } catch {
            owsFailDebug("unexpected error: \(error)")
        }
        updateContent()
    }

    private func string(for messageReceiptStatus: MessageReceiptStatus) -> String {
        switch messageReceiptStatus {
        case .uploading:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_UPLOADING",
                              comment: "Status label for messages which are uploading.")
        case .sending:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_SENDING",
                              comment: "Status label for messages which are sending.")
        case .sent:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_SENT",
                              comment: "Status label for messages which are sent.")
        case .delivered:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_DELIVERED",
                              comment: "Status label for messages which are delivered.")
        case .read:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_READ",
                              comment: "Status label for messages which are read.")
        case .failed:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_FAILED",
                                     comment: "Status label for messages which are failed.")
        case .skipped:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_SKIPPED",
                                     comment: "Status label for messages which were skipped.")
        }
    }

    // MARK: - Message Bubble Layout

    private func updateMessageViewLayout() {
        guard let messageView = messageView else {
            return
        }
        guard let messageViewWidthLayoutConstraint = messageViewWidthLayoutConstraint else {
            return
        }
        guard let messageViewHeightLayoutConstraint = messageViewHeightLayoutConstraint else {
            return
        }

        let messageBubbleSize = messageView.measureSize()
        messageViewWidthLayoutConstraint.constant = messageBubbleSize.width
        messageViewHeightLayoutConstraint.constant = messageBubbleSize.height
    }
}

extension MessageDetailViewController: OWSMessageBubbleViewDelegate {

    func didTapImageViewItem(_ viewItem: ConversationViewItem, attachmentStream: TSAttachmentStream, imageView: UIView) {
        let mediaGallery = MediaGallery(thread: self.thread)

        mediaGallery.addDataSourceDelegate(self)
        mediaGallery.presentDetailView(fromViewController: self, mediaAttachment: attachmentStream, replacingView: imageView)
    }

    func didTapVideoViewItem(_ viewItem: ConversationViewItem, attachmentStream: TSAttachmentStream, imageView: UIView) {
        let mediaGallery = MediaGallery(thread: self.thread)

        mediaGallery.addDataSourceDelegate(self)
        mediaGallery.presentDetailView(fromViewController: self, mediaAttachment: attachmentStream, replacingView: imageView)
    }

    func didTapContactShare(_ viewItem: ConversationViewItem) {
        guard let contactShare = viewItem.contactShare else {
            owsFailDebug("missing contact.")
            return
        }
        let contactViewController = ContactViewController(contactShare: contactShare)
        self.navigationController?.pushViewController(contactViewController, animated: true)
    }

    func didTapSendMessage(toContactShare contactShare: ContactShareViewModel) {
        contactShareViewHelper.sendMessage(contactShare: contactShare, fromViewController: self)
    }

    func didTapSendInvite(toContactShare contactShare: ContactShareViewModel) {
        contactShareViewHelper.showInviteContact(contactShare: contactShare, fromViewController: self)
    }

    func didTapShowAddToContactUI(forContactShare contactShare: ContactShareViewModel) {
        contactShareViewHelper.showAddToContacts(contactShare: contactShare, fromViewController: self)
    }

    func didTapAudioViewItem(_ viewItem: ConversationViewItem, attachmentStream: TSAttachmentStream) {
        AssertIsOnMainThread()

        guard let mediaURL = attachmentStream.originalMediaURL else {
            owsFailDebug("mediaURL was unexpectedly nil for attachment: \(attachmentStream)")
            return
        }

        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            owsFailDebug("audio file missing at path: \(mediaURL)")
            return
        }

        if let audioAttachmentPlayer = self.audioAttachmentPlayer {
            // Is this player associated with this media adapter?
            if audioAttachmentPlayer.owner === viewItem {
                // Tap to pause & unpause.
                audioAttachmentPlayer.togglePlayState()
                return
            }
            audioAttachmentPlayer.stop()
            self.audioAttachmentPlayer = nil
        }

        let audioAttachmentPlayer = OWSAudioPlayer(mediaUrl: mediaURL, audioBehavior: .audioMessagePlayback, delegate: viewItem)
        self.audioAttachmentPlayer = audioAttachmentPlayer

        // Associate the player with this media adapter.
        audioAttachmentPlayer.owner = viewItem
        audioAttachmentPlayer.play()
    }

    func didTapTruncatedTextMessage(_ conversationItem: ConversationViewItem) {
        guard let navigationController = self.navigationController else {
            owsFailDebug("navigationController was unexpectedly nil")
            return
        }

        let viewController = LongTextViewController(viewItem: viewItem)
        viewController.delegate = self
        navigationController.pushViewController(viewController, animated: true)
    }

    func didTapFailedIncomingAttachment(_ viewItem: ConversationViewItem) {
        // no - op
    }

    func didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {
        // no - op
    }

    func didTapConversationItem(_ viewItem: ConversationViewItem, quotedReply: OWSQuotedReplyModel) {
        // no - op
    }

    func didTapConversationItem(_ viewItem: ConversationViewItem, quotedReply: OWSQuotedReplyModel, failedThumbnailDownloadAttachmentPointer attachmentPointer: TSAttachmentPointer) {
        // no - op
    }

    func didTapConversationItem(_ viewItem: ConversationViewItem, linkPreview: OWSLinkPreview) {
        guard let urlString = linkPreview.urlString else {
            owsFailDebug("Missing url.")
            return
        }
        guard let url = URL(string: urlString) else {
            owsFailDebug("Invalid url: \(urlString).")
            return
        }
        UIApplication.shared.openURL(url)
    }

    @objc func didLongPressSent(sender: UIGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
        let messageTimestamp = "\(message.timestamp)"
        UIPasteboard.general.string = messageTimestamp
    }

    var lastSearchedText: String? {
        return nil
    }
}

extension MessageDetailViewController: MediaGalleryDataSourceDelegate {

    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, willDelete items: [MediaGalleryItem], initiatedBy: AnyObject) {
        Logger.info("")

        guard (items.map({ $0.message }) == [self.message]) else {
            // Should only be one message we can delete when viewing message details
            owsFailDebug("Unexpectedly informed of irrelevant message deletion")
            return
        }

        self.wasDeleted = true
    }

    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, deletedSections: IndexSet, deletedItems: [IndexPath]) {
        self.dismiss(animated: true) {
            self.navigationController?.popViewController(animated: true)
        }
    }
}

extension MessageDetailViewController: OWSMessageStickerViewDelegate {
    public func showStickerPack(_ stickerPackInfo: StickerPackInfo) {
        let packView = StickerPackViewController(stickerPackInfo: stickerPackInfo)
        let navigationController = OWSNavigationController(rootViewController: packView)
        present(packView, animated: true)
    }
}

extension MessageDetailViewController: ContactShareViewHelperDelegate {

    public func didCreateOrEditContact() {
        updateContent()
        self.dismiss(animated: true)
    }
}

extension MessageDetailViewController: LongTextViewDelegate {
    func longTextViewMessageWasDeleted(_ longTextViewController: LongTextViewController) {
        self.delegate?.detailViewMessageWasDeleted(self)
    }
}
