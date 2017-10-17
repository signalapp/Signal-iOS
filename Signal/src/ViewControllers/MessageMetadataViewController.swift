//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

class MessageMetadataViewController: OWSViewController {

    static let TAG = "[MessageMetadataViewController]"
    let TAG = "[MessageMetadataViewController]"

    // MARK: Properties

    let contactsManager: OWSContactsManager

    let databaseConnection: YapDatabaseConnection

    let bubbleFactory = OWSMessagesBubbleImageFactory()
    var bubbleView: UIView?

    var message: TSMessage

    var mediaMessageView: MediaMessageView?

    var scrollView: UIScrollView?
    var contentView: UIView?

    var attachment: TSAttachment?
    var dataSource: DataSource?
    var attachmentStream: TSAttachmentStream?
    var messageBody: String?

    // MARK: Initializers

    @available(*, unavailable, message:"use message: constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        self.contactsManager = Environment.getCurrent().contactsManager
        self.message = TSMessage()
        self.databaseConnection = TSStorageManager.shared().newDatabaseConnection()!
        super.init(coder: aDecoder)
        owsFail("\(self.TAG) invalid constructor")
    }

    required init(message: TSMessage) {
        self.contactsManager = Environment.getCurrent().contactsManager
        self.message = message
        self.databaseConnection = TSStorageManager.shared().newDatabaseConnection()!
        super.init(nibName: nil, bundle: nil)
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.databaseConnection.beginLongLivedReadTransaction()
        updateDBConnectionAndMessageToLatest()

        self.navigationItem.title = NSLocalizedString("MESSAGE_METADATA_VIEW_TITLE",
                                                      comment: "Title for the 'message metadata' view.")

        createViews()

        self.view.layoutIfNeeded()
        if let bubbleView = self.bubbleView {
            let showAtLeast: CGFloat = 50
            let middleCenter = CGPoint(x: bubbleView.frame.origin.x + bubbleView.frame.width / 2,
                                       y: bubbleView.frame.origin.y + bubbleView.frame.height - showAtLeast)
            let offset = bubbleView.superview!.convert(middleCenter, to: scrollView)
            self.scrollView!.setContentOffset(offset, animated: false)
        }

        NotificationCenter.default.addObserver(self,
            selector: #selector(yapDatabaseModified),
            name: NSNotification.Name.YapDatabaseModified,
            object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        mediaMessageView?.viewWillAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        mediaMessageView?.viewWillDisappear(animated)
    }

    // MARK: - Create Views

    private func createViews() {
        view.backgroundColor = UIColor.white

        let scrollView = UIScrollView()
        self.scrollView = scrollView
        view.addSubview(scrollView)
        scrollView.autoPinWidthToSuperview(withMargin: 0)
        scrollView.autoPin(toTopLayoutGuideOf: self, withInset: 0)

        // See notes on how to use UIScrollView with iOS Auto Layout:
        //
        // https://developer.apple.com/library/content/releasenotes/General/RN-iOSSDK-6_0/
        let contentView = UIView.container()
        self.contentView = contentView
        scrollView.addSubview(contentView)
        contentView.autoPinLeadingToSuperview()
        contentView.autoPinTrailingToSuperview()
        contentView.autoPinEdge(toSuperviewEdge: .top)
        contentView.autoPinEdge(toSuperviewEdge: .bottom)
        scrollView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let hasAttachment = message.attachmentIds.count > 0

        if hasAttachment {
            let footer = UIToolbar()
            footer.barTintColor = UIColor.ows_materialBlue()
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
            scrollView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        }

        updateContent()
    }

    private func updateContent() {
        guard let contentView = contentView else {
            owsFail("\(TAG) Missing contentView")
            return
        }

        // Remove any existing content views.
        for subview in contentView.subviews {
            subview.removeFromSuperview()
        }

        var rows = [UIView]()
        let contactsManager = Environment.getCurrent().contactsManager!
        let thread = message.thread

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

            let isGroupThread = message.thread.isGroupThread()

            let recipientStatusGroups: [MessageRecipientStatus] = [
                .read,
                .uploading,
                .delivered,
                .sent,
                .sending,
                .failed
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

                for recipientId in thread.recipientIdentifiers {
                    let (recipientStatus, statusMessage) = MessageRecipientStatusUtils.recipientStatusAndStatusMessage(outgoingMessage: outgoingMessage, recipientId: recipientId, referenceView: self.view)

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
                    statusLabel.text = statusMessage
                    statusLabel.textColor = UIColor.ows_darkGray()
                    statusLabel.font = UIFont.ows_footnote()
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
                             value: DateUtil.formatPastTimestampRelativeToNow(message.timestamp)))

        if message as? TSIncomingMessage != nil {
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_RECEIVED_DATE_TIME",
                                                         comment: "Label for the 'received date & time' field of the 'message metadata' view."),
                                 value: DateUtil.formatPastTimestampRelativeToNow(message.timestampForSorting())))
        }

        rows += addAttachmentMetadataRows()

        // TODO: We could include the "disappearing messages" state here.

        var lastRow: UIView?
        for row in rows {
            contentView.addSubview(row)
            row.autoPinLeadingToSuperview()
            row.autoPinTrailingToSuperview()

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

        if let mediaMessageView = mediaMessageView {
            mediaMessageView.autoPinToSquareAspectRatio()
        }
    }

    private func contentRows() -> [UIView] {
        var rows = [UIView]()

        if message.attachmentIds.count > 0 {
            rows += addAttachmentRows()
        } else if let messageBody = message.body {
            // TODO: We should also display "oversize text messages" in a
            //       similar way.
            if messageBody.characters.count > 0 {
                self.messageBody = messageBody

                let isIncoming = self.message as? TSIncomingMessage != nil

                let bodyLabel = UILabel()
                bodyLabel.textColor = isIncoming ? UIColor.black : UIColor.white
                bodyLabel.font = UIFont.ows_regularFont(withSize: 16)
                bodyLabel.text = messageBody
                bodyLabel.numberOfLines = 0
                bodyLabel.lineBreakMode = .byWordWrapping

                let bubbleImageData = isIncoming ? bubbleFactory.incoming : bubbleFactory.outgoing

                let leadingMargin: CGFloat = isIncoming ? 15 : 10
                let trailingMargin: CGFloat = isIncoming ? 10 : 15

                let bubbleView = UIImageView(image: bubbleImageData.messageBubbleImage)
                self.bubbleView = bubbleView

                bubbleView.layer.cornerRadius = 10
                bubbleView.addSubview(bodyLabel)

                bodyLabel.autoPinEdge(toSuperviewEdge: .leading, withInset: leadingMargin)
                bodyLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: trailingMargin)
                bodyLabel.autoPinHeightToSuperview(withMargin: 10)

                // Try to hug content both horizontally and vertically, but *prefer* wide and short, to narrow and tall.
                // While never exceeding max width, and never cropping content.
                bodyLabel.setContentHuggingPriority(UILayoutPriorityDefaultLow, for: .horizontal)
                bodyLabel.setContentHuggingPriority(UILayoutPriorityDefaultHigh, for: .vertical)
                bodyLabel.setContentCompressionResistancePriority(UILayoutPriorityRequired, for: .vertical)
                bodyLabel.autoSetDimension(.width, toSize: ScaleFromIPhone5(210), relation: .lessThanOrEqual)

                let bubbleSpacer = UIView()

                let row = UIView()
                row.addSubview(bubbleView)
                row.addSubview(bubbleSpacer)

                bubbleView.autoPinHeightToSuperview()
                bubbleSpacer.autoPinHeightToSuperview()
                bubbleSpacer.setContentHuggingLow()

                if isIncoming {
                    bubbleView.autoPinLeadingToSuperview(withMargin: 10)
                    bubbleSpacer.autoPinLeading(toTrailingOf: bubbleView)
                    bubbleSpacer.autoPinTrailingToSuperview(withMargin: 10)
                } else {
                    bubbleSpacer.autoPinLeadingToSuperview(withMargin: 10)
                    bubbleView.autoPinLeading(toTrailingOf: bubbleSpacer)
                    bubbleView.autoPinTrailingToSuperview(withMargin: 10)
                }

                rows.append(row)
            } else {
                // Neither attachment nor body.
                owsFail("\(self.TAG) Message has neither attachment nor body.")
                rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_NO_ATTACHMENT_OR_BODY",
                                                             comment: "Label for messages without a body or attachment in the 'message metadata' view."),
                                     value: ""))
            }
        }

        let spacer = UIView()
        spacer.autoSetDimension(.height, toSize: 15)
        rows.append(spacer)

        return rows
    }

    private func addAttachmentRows() -> [UIView] {
        var rows = [UIView]()

        guard let attachmentId = message.attachmentIds[0] as? String else {
            owsFail("Invalid attachment")
            return rows
        }

        guard let attachment = TSAttachment.fetch(uniqueId: attachmentId) else {
            owsFail("Missing attachment")
            return rows
        }
        self.attachment = attachment

        guard let attachmentStream = attachment as? TSAttachmentStream else {
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_NOT_YET_DOWNLOADED",
                                                         comment: "Label for 'not yet downloaded' attachments in the 'message metadata' view."),
                                 value: ""))
            return rows
        }
        self.attachmentStream = attachmentStream

        if let filePath = attachmentStream.filePath() {
            dataSource = DataSourcePath.dataSource(withFilePath: filePath)
        }

        guard let dataSource = dataSource else {
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_MISSING_FILE",
                                                         comment: "Label for 'missing' attachments in the 'message metadata' view."),
                                 value: ""))
            return rows
        }

        let contentType = attachment.contentType
        if let dataUTI = MIMETypeUtil.utiType(forMIMEType: contentType) {
            let attachment = SignalAttachment(dataSource: dataSource, dataUTI: dataUTI)
            let mediaMessageView = MediaMessageView(attachment: attachment)
            self.mediaMessageView = mediaMessageView
            rows.append(mediaMessageView)
        }
        return rows
    }

    private func addAttachmentMetadataRows() -> [UIView] {
        var rows = [UIView]()

        if let attachment = self.attachment {
            let contentType = attachment.contentType
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_MIME_TYPE",
                                                         comment: "Label for the MIME type of attachments in the 'message metadata' view."),
                                 value: contentType))

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
                                 value: ViewControllerUtils.formatFileSize(UInt(fileSize))))
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
        nameLabel.autoPinLeadingToSuperview(withMargin: 20)
        valueLabel.autoPinTrailingToSuperview(withMargin: 20)
        valueLabel.autoPinLeading(toTrailingOf: nameLabel, margin: 10)
        nameLabel.autoPinEdge(toSuperviewEdge: .top)
        valueLabel.autoPinEdge(toSuperviewEdge: .top)

        if subtitle.characters.count > 0 {
            let subtitleLabel = self.valueLabel(text: subtitle)
            subtitleLabel.textColor = UIColor.ows_darkGray()
            row.addSubview(subtitleLabel)
            subtitleLabel.autoPinTrailingToSuperview()
            subtitleLabel.autoPinLeading(toTrailingOf: nameLabel, margin: 10)
            subtitleLabel.autoPinEdge(.top, to: .bottom, of: valueLabel, withOffset: 1)
            subtitleLabel.autoPinEdge(toSuperviewEdge: .bottom)
        } else if value.characters.count > 0 {
            valueLabel.autoPinEdge(toSuperviewEdge: .bottom)
        } else {
            nameLabel.autoPinEdge(toSuperviewEdge: .bottom)
        }

        return row
    }

    // MARK: - Actions

    func shareButtonPressed() {
        if let messageBody = messageBody {
            UIPasteboard.general.string = messageBody
            return
        }

        guard let attachmentStream = attachmentStream else {
            Logger.error("\(TAG) Message has neither attachment nor message body.")
            return
        }
        AttachmentSharing.showShareUI(forAttachment: attachmentStream)
    }

    func copyToPasteboard() {
        if let messageBody = messageBody {
            UIPasteboard.general.string = messageBody
            return
        }

        guard let attachmentStream = attachmentStream else {
            Logger.error("\(TAG) Message has neither attachment nor message body.")
            return
        }
        guard let utiType = MIMETypeUtil.utiType(forMIMEType: attachmentStream.contentType) else {
            Logger.error("\(TAG) Attachment has invalid MIME type: \(attachmentStream.contentType).")
            return
        }
        guard let dataSource = dataSource else {
            Logger.error("\(TAG) Attachment missing data source.")
            return
        }
        let data = dataSource.data()
        UIPasteboard.general.setData(data, forPasteboardType: utiType)
    }

    // MARK: - Actions

    // This method should be called after self.databaseConnection.beginLongLivedReadTransaction().
    private func updateDBConnectionAndMessageToLatest() {

        AssertIsOnMainThread()

        self.databaseConnection.read { transaction in
            guard let newMessage = TSInteraction.fetch(uniqueId: self.message.uniqueId, transaction: transaction) as? TSMessage else {
                Logger.error("\(self.TAG) Couldn't reload message.")
                return
            }
            self.message = newMessage
        }
    }

    internal func yapDatabaseModified(notification: NSNotification) {
        AssertIsOnMainThread()

        let notifications = self.databaseConnection.beginLongLivedReadTransaction()

        guard self.databaseConnection.hasChange(forKey: message.uniqueId,
                                                 inCollection: TSInteraction.collection(),
                                                 in: notifications) else {
                                                    Logger.debug("\(TAG) No relevant changes.")
                                                    return
        }

        updateDBConnectionAndMessageToLatest()

        updateContent()
    }

    private func string(for messageRecipientStatus: MessageRecipientStatus) -> String {
        switch messageRecipientStatus {
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
        }
    }
}
