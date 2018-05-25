//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc
enum MessageMetadataViewMode: UInt {
    case focusOnMessage
    case focusOnMetadata
}

class MessageDetailViewController: OWSViewController, MediaGalleryDataSourceDelegate, OWSMessageBubbleViewDelegate, ContactShareViewHelperDelegate {

    // MARK: Properties

    let contactsManager: OWSContactsManager

    let uiDatabaseConnection: YapDatabaseConnection

    let bubbleFactory = OWSMessagesBubbleImageFactory()
    var bubbleView: UIView?

    let mode: MessageMetadataViewMode
    let viewItem: ConversationViewItem
    var message: TSMessage
    var wasDeleted: Bool = false

    var messageBubbleView: OWSMessageBubbleView?
    var messageBubbleViewWidthLayoutConstraint: NSLayoutConstraint?
    var messageBubbleViewHeightLayoutConstraint: NSLayoutConstraint?

    var scrollView: UIScrollView!
    var contentView: UIView?

    var attachment: TSAttachment?
    var dataSource: DataSource?
    var attachmentStream: TSAttachmentStream?
    var messageBody: String?

    private var contactShareViewHelper: ContactShareViewHelper

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("\(#function) is unimplemented.")
    }

    @objc
    required init(viewItem: ConversationViewItem, message: TSMessage, mode: MessageMetadataViewMode) {
        self.contactsManager = Environment.current().contactsManager
        self.viewItem = viewItem
        self.message = message
        self.mode = mode
        self.uiDatabaseConnection = OWSPrimaryStorage.shared().newDatabaseConnection()
        self.contactShareViewHelper = ContactShareViewHelper(contactsManager: contactsManager)
        super.init(nibName: nil, bundle: nil)

        contactShareViewHelper.delegate = self
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.uiDatabaseConnection.beginLongLivedReadTransaction()
        updateDBConnectionAndMessageToLatest()

        self.navigationItem.title = NSLocalizedString("MESSAGE_METADATA_VIEW_TITLE",
                                                      comment: "Title for the 'message metadata' view.")

        createViews()

        self.view.layoutIfNeeded()

        NotificationCenter.default.addObserver(self,
            selector: #selector(yapDatabaseModified),
            name: NSNotification.Name.YapDatabaseModified,
            object: OWSPrimaryStorage.shared().dbNotificationObject)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateMessageBubbleViewLayout()

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
        view.backgroundColor = UIColor.white

        let scrollView = UIScrollView()
        self.scrollView = scrollView
        view.addSubview(scrollView)
        scrollView.autoPinWidthToSuperview(withMargin: 0)
        scrollView.autoPin(toTopLayoutGuideOf: self, withInset: 0)

        let contentView = UIView.container()
        self.contentView = contentView
        scrollView.addSubview(contentView)
        contentView.autoPinLeadingToSuperviewMargin()
        contentView.autoPinTrailingToSuperviewMargin()
        contentView.autoPinEdge(toSuperviewEdge: .top)
        contentView.autoPinEdge(toSuperviewEdge: .bottom)
        scrollView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        if hasMediaAttachment {
            let footer = UIToolbar()
            footer.barTintColor = UIColor.ows_materialBlue
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
            scrollView.applyInsetsFix()

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
            owsFail("\(logTag) Missing contentView")
            return
        }

        // Remove any existing content views.
        for subview in contentView.subviews {
            subview.removeFromSuperview()
        }

        var rows = [UIView]()
        let contactsManager = Environment.current().contactsManager!

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
                    divider.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
                    divider.autoSetDimension(.height, toSize: 0.5)
                    groupRows.append(divider)
                }

                let messageRecipientIds = outgoingMessage.recipientIds()

                for recipientId in messageRecipientIds {
                    guard let recipientState = outgoingMessage.recipientState(forRecipientId: recipientId) else {
                        owsFail("\(self.logTag) no message status for recipient: \(recipientId).")
                        continue
                    }

                    let (recipientStatus, shortStatusMessage, _) = MessageRecipientStatusUtils.recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage, recipientState: recipientState, referenceView: self.view)

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

                    let cell = ContactTableViewCell()
                    cell.configure(withRecipientId: recipientId, contactsManager: self.contactsManager)
                    let statusLabel = UILabel()
                    // We use the "short" status message to avoid being redundant with the section title.
                    statusLabel.text = shortStatusMessage
                    statusLabel.textColor = UIColor.ows_darkGray
                    statusLabel.font = .ows_dynamicTypeFootnote
                    statusLabel.adjustsFontSizeToFitWidth = true
                    statusLabel.sizeToFit()
                    cell.accessoryView = statusLabel
                    cell.autoSetDimension(.height, toSize: ContactTableViewCell.rowHeight())
                    cell.setContentHuggingLow()
                    cell.isUserInteractionEnabled = false
                    groupRows.append(cell)
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

        rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_SENT_DATE_TIME",
                                                     comment: "Label for the 'sent date & time' field of the 'message metadata' view."),
                             value: DateUtil.formatPastTimestampRelativeToNow(message.timestamp,
                                                                              isRTL: self.view.isRTL())))

        if message as? TSIncomingMessage != nil {
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_RECEIVED_DATE_TIME",
                                                         comment: "Label for the 'received date & time' field of the 'message metadata' view."),
                                 value: DateUtil.formatPastTimestampRelativeToNow(message.timestampForSorting(),
                                                                                  isRTL: self.view.isRTL())))
        }

        rows += addAttachmentMetadataRows()

        // TODO: We could include the "disappearing messages" state here.

        var lastRow: UIView?
        for row in rows {
            contentView.addSubview(row)
            row.autoPinLeadingToSuperviewMargin()
            row.autoPinTrailingToSuperviewMargin()

            if let lastRow = lastRow {
                row.autoPinEdge(.top, to: .bottom, of: lastRow, withOffset: 5)
            } else {
                row.autoPinEdge(toSuperviewEdge: .top, withInset: 20)
            }

            lastRow = row
        }
        if let lastRow = lastRow {
            lastRow.autoPinEdge(toSuperviewEdge: .bottom, withInset: 20)
        }

        updateMessageBubbleViewLayout()
    }

    private func displayableTextIfText() -> String? {
        guard viewItem.hasBodyText else {
                return nil
        }
        guard let displayableText = viewItem.displayableBodyText() else {
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

        if hasMediaAttachment {
            rows += addAttachmentRows()
        }

        let messageBubbleView = OWSMessageBubbleView(frame: CGRect.zero)
        messageBubbleView.delegate = self
        messageBubbleView.addTapGestureHandler()
        self.messageBubbleView = messageBubbleView
        messageBubbleView.viewItem = viewItem
        messageBubbleView.cellMediaCache = NSCache()
        messageBubbleView.contentWidth = contentWidth()
        messageBubbleView.alwaysShowBubbleTail = true
        messageBubbleView.configureViews()
        messageBubbleView.loadContent()

        assert(messageBubbleView.isUserInteractionEnabled)

        let row = UIView()
        row.addSubview(messageBubbleView)
        messageBubbleView.autoPinHeightToSuperview()

        let isIncoming = self.message as? TSIncomingMessage != nil
        messageBubbleView.autoPinEdge(toSuperviewEdge: isIncoming ? .leading : .trailing, withInset: bubbleViewHMargin)

        self.messageBubbleViewWidthLayoutConstraint = messageBubbleView.autoSetDimension(.width, toSize: 0)
        self.messageBubbleViewHeightLayoutConstraint = messageBubbleView.autoSetDimension(.height, toSize: 0)
        rows.append(row)

        if rows.count == 0 {
            // Neither attachment nor body.
            owsFail("\(self.logTag) Message has neither attachment nor body.")
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
        guard let attachmentId = message.attachmentIds.firstObject as? String else {
            return nil
        }

        guard let attachment = TSAttachment.fetch(uniqueId: attachmentId, transaction: transaction) else {
            Logger.warn("\(logTag) Missing attachment. Was it deleted?")
            return nil
        }

        return attachment
    }

    private func addAttachmentRows() -> [UIView] {
        var rows = [UIView]()

        guard let attachment = self.attachment else {
            Logger.warn("\(logTag) Missing attachment. Was it deleted?")
            return rows
        }

        guard let attachmentStream = attachment as? TSAttachmentStream else {
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_NOT_YET_DOWNLOADED",
                                                         comment: "Label for 'not yet downloaded' attachments in the 'message metadata' view."),
                                 value: ""))
            return rows
        }
        self.attachmentStream = attachmentStream

        return rows
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

    private func nameLabel(text: String) -> UILabel {
        let label = UILabel()
        label.textColor = UIColor.black
        label.font = UIFont.ows_mediumFont(withSize: 14)
        label.text = text
        label.setContentHuggingHorizontalHigh()
        return label
    }

    private func valueLabel(text: String) -> UILabel {
        let label = UILabel()
        label.textColor = UIColor.black
        label.font = UIFont.ows_regularFont(withSize: 14)
        label.text = text
        label.setContentHuggingHorizontalLow()
        return label
    }

    private func valueRow(name: String, value: String, subtitle: String = "") -> UIView {
        let row = UIView.container()
        let nameLabel = self.nameLabel(text: name)
        let valueLabel = self.valueLabel(text: value)
        row.addSubview(nameLabel)
        row.addSubview(valueLabel)
        nameLabel.autoPinLeadingToSuperviewMargin(withInset: 20)
        valueLabel.autoPinTrailingToSuperviewMargin(withInset: 20)
        valueLabel.autoPinLeading(toTrailingEdgeOf: nameLabel, offset: 10)
        nameLabel.autoPinEdge(toSuperviewEdge: .top)
        valueLabel.autoPinEdge(toSuperviewEdge: .top)

        if subtitle.count > 0 {
            let subtitleLabel = self.valueLabel(text: subtitle)
            subtitleLabel.textColor = UIColor.ows_darkGray
            row.addSubview(subtitleLabel)
            subtitleLabel.autoPinTrailingToSuperviewMargin()
            subtitleLabel.autoPinLeading(toTrailingEdgeOf: nameLabel, offset: 10)
            subtitleLabel.autoPinEdge(.top, to: .bottom, of: valueLabel, withOffset: 1)
            subtitleLabel.autoPinEdge(toSuperviewEdge: .bottom)
        } else if value.count > 0 {
            valueLabel.autoPinEdge(toSuperviewEdge: .bottom)
        } else {
            nameLabel.autoPinEdge(toSuperviewEdge: .bottom)
        }

        return row
    }

    // MARK: - Actions

    @objc func shareButtonPressed() {
        guard let attachmentStream = attachmentStream else {
            Logger.error("\(logTag) Share button should only be shown with attachment, but no attachment found.")
            return
        }
        AttachmentSharing.showShareUI(forAttachment: attachmentStream)
    }

    // MARK: - Actions

    // This method should be called after self.databaseConnection.beginLongLivedReadTransaction().
    private func updateDBConnectionAndMessageToLatest() {

        SwiftAssertIsOnMainThread(#function)

        self.uiDatabaseConnection.read { transaction in
            guard let uniqueId = self.message.uniqueId else {
                Logger.error("\(self.logTag) Message is missing uniqueId.")
                return
            }
            guard let newMessage = TSInteraction.fetch(uniqueId: uniqueId, transaction: transaction) as? TSMessage else {
                Logger.error("\(self.logTag) Couldn't reload message.")
                return
            }
            self.message = newMessage
            self.attachment = self.fetchAttachment(transaction: transaction)
        }
    }

    @objc internal func yapDatabaseModified(notification: NSNotification) {
        SwiftAssertIsOnMainThread(#function)

        guard !wasDeleted else {
            // Item was deleted. Don't bother re-rendering, it will fail and we'll soon be dismissed.
            return
        }

        let notifications = self.uiDatabaseConnection.beginLongLivedReadTransaction()

        guard let uniqueId = self.message.uniqueId else {
            Logger.error("\(self.logTag) Message is missing uniqueId.")
            return
        }
        guard self.uiDatabaseConnection.hasChange(forKey: uniqueId,
                                                 inCollection: TSInteraction.collection(),
                                                 in: notifications) else {
                                                    Logger.debug("\(logTag) No relevant changes.")
                                                    return
        }

        updateDBConnectionAndMessageToLatest()
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

    private func contentWidth() -> Int32 {
        return Int32(round(self.view.width() - (2 * bubbleViewHMargin)))
    }

    private func updateMessageBubbleViewLayout() {
        guard let messageBubbleView = messageBubbleView else {
            return
        }
        guard let messageBubbleViewWidthLayoutConstraint = messageBubbleViewWidthLayoutConstraint else {
            return
        }
        guard let messageBubbleViewHeightLayoutConstraint = messageBubbleViewHeightLayoutConstraint else {
            return
        }

        messageBubbleView.contentWidth = contentWidth()

        let messageBubbleSize = messageBubbleView.size(forContentWidth: contentWidth())
        messageBubbleViewWidthLayoutConstraint.constant = messageBubbleSize.width
        messageBubbleViewHeightLayoutConstraint.constant = messageBubbleSize.height
    }

    // MARK: OWSMessageBubbleViewDelegate

    func didTapImageViewItem(_ viewItem: ConversationViewItem, attachmentStream: TSAttachmentStream, imageView: UIView) {
        let mediaGalleryViewController = MediaGalleryViewController(thread: self.thread, uiDatabaseConnection: self.uiDatabaseConnection)

        mediaGalleryViewController.addDataSourceDelegate(self)
        mediaGalleryViewController.presentDetailView(fromViewController: self, mediaMessage: self.message, replacingView: imageView)
    }

    func didTapVideoViewItem(_ viewItem: ConversationViewItem, attachmentStream: TSAttachmentStream, imageView: UIView) {
        let mediaGalleryViewController = MediaGalleryViewController(thread: self.thread, uiDatabaseConnection: self.uiDatabaseConnection)

        mediaGalleryViewController.addDataSourceDelegate(self)
        mediaGalleryViewController.presentDetailView(fromViewController: self, mediaMessage: self.message, replacingView: imageView)
    }

    func didTapContactShare(_ viewItem: ConversationViewItem) {
        guard let contactShare = viewItem.contactShare else {
            owsFail("\(logTag) missing contact.")
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

    var audioAttachmentPlayer: OWSAudioPlayer?

    func didTapAudioViewItem(_ viewItem: ConversationViewItem, attachmentStream: TSAttachmentStream) {
        SwiftAssertIsOnMainThread(#function)

        guard let mediaURL = attachmentStream.mediaURL() else {
            owsFail("\(logTag) in \(#function) mediaURL was unexpectedly nil for attachment: \(attachmentStream)")
            return
        }

        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            owsFail("\(logTag) in \(#function) audio file missing at path: \(mediaURL)")
            return
        }

        if let audioAttachmentPlayer = self.audioAttachmentPlayer {
            // Is this player associated with this media adapter?
            if (audioAttachmentPlayer.owner as? ConversationViewItem == viewItem) {
                // Tap to pause & unpause.
                audioAttachmentPlayer.togglePlayState()
                return
            }
            audioAttachmentPlayer.stop()
            self.audioAttachmentPlayer = nil
        }

        let audioAttachmentPlayer = OWSAudioPlayer(mediaUrl: mediaURL, delegate: viewItem)
        self.audioAttachmentPlayer = audioAttachmentPlayer

        // Associate the player with this media adapter.
        audioAttachmentPlayer.owner = viewItem
        audioAttachmentPlayer.playWithPlaybackAudioCategory()
    }

    func didTapTruncatedTextMessage(_ conversationItem: ConversationViewItem) {
        guard let navigationController = self.navigationController else {
            owsFail("\(logTag) in \(#function) navigationController was unexpectedly nil")
            return
        }

        let viewController = LongTextViewController(viewItem: viewItem)
        navigationController.pushViewController(viewController, animated: true)
    }

    func didTapFailedIncomingAttachment(_ viewItem: ConversationViewItem, attachmentPointer: TSAttachmentPointer) {
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

    // MediaGalleryDataSourceDelegate

    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, willDelete items: [MediaGalleryItem], initiatedBy: MediaGalleryDataSourceDelegate) {
        Logger.info("\(self.logTag) in \(#function)")

        guard (items.map({ $0.message }) == [self.message]) else {
            // Should only be one message we can delete when viewing message details
            owsFail("\(logTag) in \(#function) Unexpectedly informed of irrelevant message deletion")
            return
        }

        self.wasDeleted = true
    }

    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, deletedSections: IndexSet, deletedItems: [IndexPath]) {
        self.dismiss(animated: true) {
            self.navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - ContactShareViewHelperDelegate

    public func didCreateOrEditContact() {
        updateContent()
        self.dismiss(animated: true)
    }
}
