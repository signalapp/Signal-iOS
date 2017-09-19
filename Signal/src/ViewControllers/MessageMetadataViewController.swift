//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

class MessageMetadataViewController: OWSViewController {

    let TAG = "[MessageMetadataViewController]"

    // MARK: Properties

    let message: TSMessage

    var mediaMessageView: MediaMessageView?

    var scrollView: UIScrollView?
    var contentView: UIView?

    var dataSource: DataSource?
    var attachmentStream: TSAttachmentStream?
    var messageBody: String?

    // MARK: Initializers

    @available(*, unavailable, message:"use message: constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        self.message = TSMessage()
        super.init(coder: aDecoder)
        owsFail("\(self.TAG) invalid constructor")
    }

    required init(message: TSMessage) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = NSLocalizedString("MESSAGE_METADATA_VIEW_TITLE",
                                                      comment: "Title for the 'message metadata' view.")

        createViews()
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
        scrollView.autoPinWidthToSuperview(withMargin:0)
        scrollView.autoPin(toTopLayoutGuideOf: self, withInset:0)

        let footer = UIToolbar()
        footer.barTintColor = UIColor.ows_materialBlue()
        view.addSubview(footer)
        footer.autoPinWidthToSuperview(withMargin:0)
        footer.autoPinEdge(.top, to:.bottom, of:scrollView)
        footer.autoPin(toBottomLayoutGuideOf: self, withInset:0)

        footer.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareButtonPressed)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        ]

        // See notes on how to use UIScrollView with iOS Auto Layout:
        //
        // https://developer.apple.com/library/content/releasenotes/General/RN-iOSSDK-6_0/
        let contentView = UIView.container()
        self.contentView = contentView
        scrollView.addSubview(contentView)
        contentView.autoPinLeadingToSuperView()
        contentView.autoPinTrailingToSuperView()
        contentView.autoPinEdge(toSuperviewEdge:.top)
        contentView.autoPinEdge(toSuperviewEdge:.bottom)

        var rows = [UIView]()

        let contactsManager = Environment.getCurrent().contactsManager!

        // Group?
        let thread = message.thread
        if let groupThread = thread as? TSGroupThread {
            var groupName = groupThread.name()
            if groupName.characters.count < 1 {
                groupName = NSLocalizedString("NEW_GROUP_DEFAULT_TITLE", comment: "")
            }

            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_GROUP_NAME",
                                                         comment: "Label for the 'group name' field of the 'message metadata' view."),
                                 value:groupName))
        }

        // Sender?
        if let incomingMessage = message as? TSIncomingMessage {
            let senderId = incomingMessage.authorId
            let senderName = contactsManager.contactOrProfileName(forPhoneIdentifier:senderId)
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_SENDER",
                                                         comment: "Label for the 'sender' field of the 'message metadata' view."),
                                 value:senderName))
        }

        // Recipient(s)
        if let outgoingMessage = message as? TSOutgoingMessage {
            for recipientId in thread.recipientIdentifiers {
                let recipientName = contactsManager.contactOrProfileName(forPhoneIdentifier:recipientId)
                let recipientStatus = self.recipientStatus(forOutgoingMessage: outgoingMessage, recipientId: recipientId)

                rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_RECIPIENT",
                                                             comment: "Label for the 'recipient' field of the 'message metadata' view."),
                                     value:recipientName,
                                     subtitle:recipientStatus))
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .long

        let sentDate = NSDate.ows_date(withMillisecondsSince1970:message.timestamp)
        rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_SENT_DATE_TIME",
                                                     comment: "Label for the 'sent date & time' field of the 'message metadata' view."),
                             value:dateFormatter.string(from:sentDate)))

        if let _ = message as? TSIncomingMessage {
            let receivedDate = message.dateForSorting()
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_RECEIVED_DATE_TIME",
                                                         comment: "Label for the 'received date & time' field of the 'message metadata' view."),
                                 value:dateFormatter.string(from:receivedDate)))
        }

        // TODO: We could include the "disappearing messages" state here.

        if message.attachmentIds.count > 0 {
            rows += addAttachmentRows()
        } else if let messageBody = message.body {
            // TODO: We should also display "oversize text messages" in a
            //       similar way.
            if messageBody.characters.count > 0 {
                self.messageBody = messageBody

                rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_BODY_LABEL",
                                                             comment: "Label for the message body in the 'message metadata' view."),
                                     value:""))

                let bodyLabel = UILabel()
                bodyLabel.textColor = UIColor.black
                bodyLabel.font = UIFont.ows_regularFont(withSize:14)
                bodyLabel.text = messageBody
                bodyLabel.numberOfLines = 0
                bodyLabel.lineBreakMode = .byWordWrapping
                rows.append(bodyLabel)
            } else {
                // Neither attachment nor body.
                rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_NO_ATTACHMENT_OR_BODY",
                                                             comment: "Label for messages without a body or attachment in the 'message metadata' view."),
                                     value:""))
            }
        }

        var lastRow: UIView?
        for row in rows {
            contentView.addSubview(row)
            row.autoPinLeadingToSuperView()
            row.autoPinTrailingToSuperView()

            if let lastRow = lastRow {
                row.autoPinEdge(.top, to:.bottom, of:lastRow, withOffset:5)
            } else {
                row.autoPinEdge(toSuperviewEdge:.top, withInset:20)
            }

            lastRow = row
        }
        if let lastRow = lastRow {
            lastRow.autoPinEdge(toSuperviewEdge:.bottom, withInset:20)
        }

        if let mediaMessageView = mediaMessageView {
            mediaMessageView.autoPinToSquareAspectRatio()
        }

        // TODO: We might want to add a footer with share/save/copy/etc.
    }

    private func addAttachmentRows() -> [UIView] {
        var rows = [UIView]()

        guard let attachmentId = message.attachmentIds[0] as? String else {
            owsFail("Invalid attachment")
            return rows
        }

        guard let attachment = TSAttachment.fetch(uniqueId:attachmentId) else {
            owsFail("Missing attachment")
            return rows
        }

        let contentType = attachment.contentType
        rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_MIME_TYPE",
                                                     comment: "Label for the MIME type of attachments in the 'message metadata' view."),
                             value:contentType))

        if let sourceFilename = attachment.sourceFilename {
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_SOURCE_FILENAME",
                                                         comment: "Label for the original filename of any attachment in the 'message metadata' view."),
                                 value:sourceFilename))
        }

        guard let attachmentStream = attachment as? TSAttachmentStream else {
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_NOT_YET_DOWNLOADED",
                                                         comment: "Label for 'not yet downloaded' attachments in the 'message metadata' view."),
                                 value:""))
            return rows
        }
        self.attachmentStream = attachmentStream

        if let filePath = attachmentStream.filePath() {
            dataSource = DataSourcePath.dataSource(withFilePath:filePath)
        }

        guard let dataSource = dataSource else {
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_MISSING_FILE",
                                                         comment: "Label for 'missing' attachments in the 'message metadata' view."),
                                 value:""))
            return rows
        }

        let fileSize = dataSource.dataLength()
        rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_FILE_SIZE",
                                                     comment: "Label for file size of attachments in the 'message metadata' view."),
                             value:ViewControllerUtils.formatFileSize(UInt(fileSize))))

        if let dataUTI = MIMETypeUtil.utiType(forMIMEType:contentType) {
            if attachment.isVoiceMessage() {
                rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_VOICE_MESSAGE",
                                                             comment: "Label for voice messages of the 'message metadata' view."),
                                     value:""))
            } else {
                rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_MEDIA",
                                                             comment: "Label for media messages of the 'message metadata' view."),
                                     value:""))
            }
            let attachment = SignalAttachment(dataSource : dataSource, dataUTI: dataUTI)
            let mediaMessageView = MediaMessageView(attachment:attachment)
            self.mediaMessageView = mediaMessageView
            rows.append(mediaMessageView)
        }
        return rows
    }

    private func recipientStatus(forOutgoingMessage message: TSOutgoingMessage, recipientId: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .long

        let recipientReadMap = message.recipientReadMap
        if let readTimestamp = recipientReadMap[recipientId] {
            assert(message.messageState == .sentToService)
            let readDate = NSDate.ows_date(withMillisecondsSince1970:readTimestamp.uint64Value)
            return String(format:NSLocalizedString("MESSAGE_STATUS_READ_WITH_TIMESTAMP_FORMAT",
                                                   comment: "message status for messages read by the recipient. Embeds: {{the date and time the message was read}}."),
                          dateFormatter.string(from:readDate))
        }

        // TODO: We don't currently track delivery state on a per-recipient basis.
        //       We should.
        if message.wasDelivered {
            return NSLocalizedString("MESSAGE_STATUS_DELIVERED",
                                     comment:"message status for message delivered to their recipient.")
        }

        if message.messageState == .unsent {
            return NSLocalizedString("MESSAGE_STATUS_FAILED", comment:"message footer for failed messages")
        } else if (message.messageState == .sentToService ||
            message.wasSent(toRecipient:recipientId)) {
            return
                NSLocalizedString("MESSAGE_STATUS_SENT",
                                  comment:"message footer for sent messages")
        } else if message.hasAttachments() {
            return NSLocalizedString("MESSAGE_STATUS_UPLOADING",
                                     comment:"message footer while attachment is uploading")
        } else {
            assert(message.messageState == .attemptingOut)

            return NSLocalizedString("MESSAGE_STATUS_SENDING",
                                     comment:"message status while message is sending.")
        }
    }

    private func nameLabel(text: String) -> UILabel {
        let label = UILabel()
        label.textColor = UIColor.black
        label.font = UIFont.ows_mediumFont(withSize:14)
        label.text = text
        label.setContentHuggingHorizontalHigh()
        return label
    }

    private func valueLabel(text: String) -> UILabel {
        let label = UILabel()
        label.textColor = UIColor.black
        label.font = UIFont.ows_regularFont(withSize:14)
        label.text = text
        label.setContentHuggingHorizontalLow()
        return label
    }

    private func valueRow(name: String, value: String, subtitle: String = "") -> UIView {
        let row = UIView.container()
        let nameLabel = self.nameLabel(text:name)
        let valueLabel = self.valueLabel(text:value)
        row.addSubview(nameLabel)
        row.addSubview(valueLabel)
        nameLabel.autoPinLeadingToSuperView()
        valueLabel.autoPinTrailingToSuperView()
        valueLabel.autoPinLeading(toTrailingOf:nameLabel, margin: 10)
        nameLabel.autoPinEdge(toSuperviewEdge:.top)
        valueLabel.autoPinEdge(toSuperviewEdge:.top)

        if subtitle.characters.count > 0 {
            let subtitleLabel = self.valueLabel(text:subtitle)
            subtitleLabel.textColor = UIColor.ows_darkGray()
            row.addSubview(subtitleLabel)
            subtitleLabel.autoPinTrailingToSuperView()
            subtitleLabel.autoPinLeading(toTrailingOf:nameLabel, margin: 10)
            subtitleLabel.autoPinEdge(.top, to:.bottom, of:valueLabel, withOffset:1)
            subtitleLabel.autoPinEdge(toSuperviewEdge:.bottom)
        } else if value.characters.count > 0 {
            valueLabel.autoPinEdge(toSuperviewEdge:.bottom)
        } else {
            nameLabel.autoPinEdge(toSuperviewEdge:.bottom)
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
        AttachmentSharing.showShareUI(forAttachment:attachmentStream)
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
        guard let utiType = MIMETypeUtil.utiType(forMIMEType:attachmentStream.contentType) else {
            Logger.error("\(TAG) Attachment has invalid MIME type: \(attachmentStream.contentType).")
            return
        }
        guard let dataSource = dataSource else {
            Logger.error("\(TAG) Attachment missing data source.")
            return
        }
        let data = dataSource.data()
        UIPasteboard.general.setData(data, forPasteboardType:utiType)
    }
}
