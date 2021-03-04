//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import QuickLook
import SignalServiceKit
import SignalMessaging

enum MessageMetadataViewMode: UInt {
    case focusOnMessage
    case focusOnMetadata
}

protocol MessageDetailViewDelegate: AnyObject {
    func detailViewMessageWasDeleted(_ messageDetailViewController: MessageDetailViewController)
}

class MessageDetailViewController: OWSViewController {

    weak var delegate: MessageDetailViewDelegate?

    // MARK: Properties

    var bubbleView: UIView?

    let mode: MessageMetadataViewMode
    var message: TSMessage
    var wasDeleted: Bool = false

    let cellView = CVCellView()

    var scrollView: UIScrollView!
    var contentView: UIView?

    var attachments: [TSAttachment]?
    var attachmentStreams: [TSAttachmentStream]? {
        return attachments?.compactMap { $0 as? TSAttachmentStream }
    }
    var messageBody: String?

    lazy var shouldShowUD: Bool = {
        return self.preferences.shouldShowUnidentifiedDeliveryIndicators()
    }()

    private var contactShareViewHelper: ContactShareViewHelper!

    private var databaseUpdateTimer: Timer?

    // MARK: Initializers

    required init(message: TSMessage,
                  thread: TSThread,
                  mode: MessageMetadataViewMode) {
        self.message = message
        self.mode = mode

        super.init()
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        self.contactShareViewHelper = ContactShareViewHelper()
        contactShareViewHelper.delegate = self

        self.navigationItem.title = NSLocalizedString("MESSAGE_METADATA_VIEW_TITLE",
                                                      comment: "Title for the 'message metadata' view.")

        createViews()

        self.view.layoutIfNeeded()

        refreshContent()

        databaseStorage.appendUIDatabaseSnapshotDelegate(self)
    }

    override public func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        Logger.debug("")

        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { _ in
        },
        completion: { [weak self] _ in
            self?.refreshContent()
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

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
            footer.tintColor = Theme.primaryIconColor

            footer.items = [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                UIBarButtonItem(
                    image: Theme.iconImage(.messageActionShare),
                    style: .plain,
                    target: self,
                    action: #selector(shareButtonPressed)
                ),
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            ]
        } else {
            scrollView.autoPinEdge(toSuperviewEdge: .bottom)
        }
    }

    private var thread: TSThread? {
        renderItem?.itemModel.thread
    }

    private func updateContent() {
        guard let contentView = contentView else {
            owsFailDebug("Missing contentView.")
            return
        }
        guard let thread = thread else {
            owsFailDebug("Missing thread.")
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
            let senderName = contactsManager.displayName(for: incomingMessage.authorAddress)
            rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_SENDER",
                                                         comment: "Label for the 'sender' field of the 'message metadata' view."),
                                 value: senderName))
        }

        // Recipient(s)
        if let outgoingMessage = message as? TSOutgoingMessage {

            let isGroupThread = thread.isGroupThread

            let recipientStatusGroups: [MessageReceiptStatus] = [
                .read,
                .uploading,
                .delivered,
                .sent,
                .sending,
                .failed,
                .skipped
            ]

            let messageRecipientAddressesUnsorted = outgoingMessage.recipientAddresses()
            let messageRecipientAddressesSorted = databaseStorage.read { transaction in
                self.contactsManager.sortSignalServiceAddresses(messageRecipientAddressesUnsorted, transaction: transaction)
            }

            for recipientStatusGroup in recipientStatusGroups {
                var groupRows = [UIView]()

                // TODO: It'd be nice to inset these dividers from the edge of the screen.
                let addDivider = {
                    let divider = UIView()
                    divider.backgroundColor = Theme.hairlineColor
                    divider.autoSetDimension(.height, toSize: CGHairlineWidth())
                    groupRows.append(divider)
                }

                for recipientAddress in messageRecipientAddressesSorted {
                    guard let recipientState = outgoingMessage.recipientState(for: recipientAddress) else {
                        owsFailDebug("no message status for recipient: \(recipientAddress).")
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
                    cellView.configureWithSneakyTransaction(recipientAddress: recipientAddress)

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
                iconView.tintColor = Theme.secondaryTextAndIconColor
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
    }

    let bubbleViewHMargin: CGFloat = 10

    public static func buildRenderItem(interactionId: String,
                                       containerView: UIView) -> CVRenderItem? {
        databaseStorage.uiRead { transaction in
            guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId,
                                                           transaction: transaction) else {
                owsFailDebug("Missing interaction.")
                return nil
            }
            guard let thread = TSThread.anyFetch(uniqueId: interaction.uniqueThreadId,
                                                 transaction: transaction) else {
                owsFailDebug("Missing thread.")
                return nil
            }
            return CVLoader.buildStandaloneRenderItem(interaction: interaction,
                                                      thread: thread,
                                                      containerView: containerView,
                                                      transaction: transaction)
        }
    }

    private var renderItem: CVRenderItem?

    private func contentRows() -> [UIView] {

        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return []
        }

        cellView.reset()

        var rows = [UIView]()

        cellView.configure(renderItem: renderItem, componentDelegate: self)
        cellView.isCellVisible = true
        cellView.autoSetDimension(.height, toSize: renderItem.cellSize.height)

//         TODO: Add gesture handling.
//        messageView.addGestureHandlers()
//        messageView.panGesture.require(toFail: scrollView.panGestureRecognizer)

        let row = UIView()
        row.addSubview(cellView)
        cellView.autoPinHeightToSuperview()

        let isIncoming = self.message as? TSIncomingMessage != nil
        cellView.autoPinEdge(toSuperviewEdge: isIncoming ? .leading : .trailing, withInset: bubbleViewHMargin)

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

    var hasMediaAttachment: Bool {
        guard let attachmentStreams = self.attachmentStreams, !attachmentStreams.isEmpty else {
            return false
        }

        return true
    }

    private let byteCountFormatter: ByteCountFormatter = ByteCountFormatter()

    private func addAttachmentMetadataRows() -> [UIView] {
        guard hasMediaAttachment else {
            return []
        }

        var rows = [UIView]()

        if self.attachments?.count == 1, let attachment = self.attachments?.first {
            if let sourceFilename = attachment.sourceFilename {
                rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_SOURCE_FILENAME",
                                                             comment: "Label for the original filename of any attachment in the 'message metadata' view."),
                                     value: sourceFilename))
            }

            if DebugFlags.messageDetailsExtraInfo {
                let contentType = attachment.contentType
                rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_MIME_TYPE",
                                                             comment: "Label for the MIME type of attachments in the 'message metadata' view."),
                                     value: contentType))

                if let formattedByteCount = byteCountFormatter.string(for: attachment.byteCount) {
                    rows.append(valueRow(name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_FILE_SIZE",
                                                                 comment: "Label for file size of attachments in the 'message metadata' view."),
                                         value: formattedByteCount))
                } else {
                    owsFailDebug("formattedByteCount was unexpectedly nil")
                }
            }
        }

        return rows
    }

    private func buildUDAccessoryView(text: String) -> UIView {
        let label = UILabel()
        label.textColor = Theme.secondaryTextAndIconColor
        label.text = text
        label.textAlignment = .right
        label.font = UIFont.ows_semiboldFont(withSize: 13)

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
        label.textColor = Theme.primaryTextColor
        label.font = UIFont.ows_semiboldFont(withSize: 14)
        label.text = text
        label.setContentHuggingHorizontalHigh()
        return label
    }

    private func valueLabel(text: String) -> UILabel {
        let label = UILabel()
        label.textColor = Theme.primaryTextColor
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
            subtitleLabel.textColor = Theme.secondaryTextAndIconColor
            hStackView.addArrangedSubview(subtitleLabel)
        }

        return hStackView
    }

    // MARK: - Actions

    @objc func shareButtonPressed(_ sender: UIBarButtonItem) {
        guard let attachmentStreams = attachmentStreams, !attachmentStreams.isEmpty else {
            Logger.error("Share button should only be shown with attachments, but no attachments found.")
            return
        }
        AttachmentSharing.showShareUI(forAttachments: attachmentStreams, sender: sender)
    }

    // MARK: - Actions

    enum DetailViewError: Error {
        case messageWasDeleted
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
}

// MARK: -

extension MessageDetailViewController {
    @objc
    func didLongPressSent(sender: UIGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
        let messageTimestamp = "\(message.timestamp)"
        UIPasteboard.general.string = messageTimestamp
    }
}

// MARK: -

extension MessageDetailViewController: MediaGalleryDelegate {

    func mediaGallery(_ mediaGallery: MediaGallery, willDelete items: [MediaGalleryItem], initiatedBy: AnyObject) {
        Logger.info("")

        guard items.contains(where: { $0.message == self.message }) else {
            Logger.info("ignoring deletion of unrelated media")
            return
        }

        self.wasDeleted = true
    }

    func mediaGallery(_ mediaGallery: MediaGallery, deletedSections: IndexSet, deletedItems: [IndexPath]) {
        guard self.wasDeleted else {
            return
        }
        self.dismiss(animated: true) {
            self.navigationController?.popViewController(animated: true)
        }
    }

    func mediaGallery(_ mediaGallery: MediaGallery, didReloadItemsInSections sections: IndexSet) {
        // No action needed
    }
}

// MARK: -

extension MessageDetailViewController: ContactShareViewHelperDelegate {

    public func didCreateOrEditContact() {
        updateContent()
        self.dismiss(animated: true)
    }
}

extension MessageDetailViewController: LongTextViewDelegate {
    public func longTextViewMessageWasDeleted(_ longTextViewController: LongTextViewController) {
        self.delegate?.detailViewMessageWasDeleted(self)
    }
}

extension MessageDetailViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(item: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        guard case let .gallery(galleryItem) = item else {
            owsFailDebug("Unexpected media type")
            return nil
        }

        guard let mediaView = cellView.albumItemView(forAttachment: galleryItem.attachmentStream) else {
            owsFailDebug("itemView was unexpectedly nil")
            return nil
        }

        guard let mediaSuperview = mediaView.superview else {
            owsFailDebug("mediaSuperview was unexpectedly nil")
            return nil
        }

        let presentationFrame = coordinateSpace.convert(mediaView.frame, from: mediaSuperview)

        // TODO better corner rounding.
        return MediaPresentationContext(mediaView: mediaView,
                                        presentationFrame: presentationFrame,
                                        cornerRadius: kOWSMessageCellCornerRadius_Small * 2)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }

    func mediaWillDismiss(toContext: MediaPresentationContext) {
        // To avoid flicker when transition view is animated over the message bubble,
        // we initially hide the overlaying elements and fade them in.
        let mediaOverlayViews = toContext.mediaOverlayViews
        for mediaOverlayView in mediaOverlayViews {
            mediaOverlayView.alpha = 0
        }
    }

    func mediaDidDismiss(toContext: MediaPresentationContext) {
        // To avoid flicker when transition view is animated over the message bubble,
        // we initially hide the overlaying elements and fade them in.
        let mediaOverlayViews = toContext.mediaOverlayViews
        let duration: TimeInterval = kIsDebuggingMediaPresentationAnimations ? 1.5 : 0.2
        UIView.animate(
            withDuration: duration,
            animations: {
                for mediaOverlayView in mediaOverlayViews {
                    mediaOverlayView.alpha = 1
                }
            })
    }
}

// MARK: -

extension MediaPresentationContext {
    var mediaOverlayViews: [UIView] {
        guard let bodyMediaPresentationContext = mediaView.firstAncestor(ofType: BodyMediaPresentationContext.self) else {
            owsFailDebug("unexpected mediaView: \(mediaView)")
            return []
        }
        return bodyMediaPresentationContext.mediaOverlayViews
    }
}

// MARK: -

extension MessageDetailViewController: UIDatabaseSnapshotDelegate {

    public func uiDatabaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
    }

    public func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        AssertIsOnMainThread()

        guard databaseChanges.didUpdate(interaction: self.message) else {
            return
        }

        refreshContentForDatabaseUpdate()
    }

    public func uiDatabaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()

        refreshContentForDatabaseUpdate()
    }

    public func uiDatabaseSnapshotDidReset() {
        AssertIsOnMainThread()

        refreshContentForDatabaseUpdate()
    }

    private func refreshContentForDatabaseUpdate() {
        guard databaseUpdateTimer == nil else {
            return
        }
        // Updating this view is slightly expensive and there will be tons of relevant
        // database updates when sending to a large group. Update latency isn't that
        // imporant, so we de-bounce to never update this view more than once every N seconds.
        self.databaseUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0,
                                                        repeats: false) { [weak self] _ in
            guard let self = self else {
                return
            }
            assert(self.databaseUpdateTimer != nil)
            self.databaseUpdateTimer?.invalidate()
            self.databaseUpdateTimer = nil
            self.refreshContent()
        }
    }

    private func refreshContent() {
        AssertIsOnMainThread()

        guard !wasDeleted else {
            // Item was deleted in the tile view gallery.
            // Don't bother re-rendering, it will fail and we'll soon be dismissed.
            return
        }

        do {
            try databaseStorage.uiReadThrows { transaction in
                let uniqueId = self.message.uniqueId
                guard let newMessage = TSInteraction.anyFetch(uniqueId: uniqueId,
                                                              transaction: transaction) as? TSMessage else {
                    Logger.error("Message was deleted")
                    throw DetailViewError.messageWasDeleted
                }
                self.message = newMessage
                self.attachments = newMessage.mediaAttachments(with: transaction.unwrapGrdbRead)
            }

            guard let renderItem = Self.buildRenderItem(interactionId: message.uniqueId,
                                                        containerView: self.view) else {
                owsFailDebug("Could not build renderItem.")
                throw DetailViewError.messageWasDeleted
            }
            self.renderItem = renderItem

            updateContent()
        } catch DetailViewError.messageWasDeleted {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.detailViewMessageWasDeleted(self)
            }
        } catch {
            owsFailDebug("unexpected error: \(error)")
        }
    }
}

// MARK: -

extension MessageDetailViewController: CVComponentDelegate {

    // MARK: - Long Press

    // TODO:
    func cvc_didLongPressTextViewItem(_ cell: CVCell,
                                      itemViewModel: CVItemViewModelImpl,
                                      shouldAllowReply: Bool) {}

    // TODO:
    func cvc_didLongPressMediaViewItem(_ cell: CVCell,
                                       itemViewModel: CVItemViewModelImpl,
                                       shouldAllowReply: Bool) {}

    // TODO:
    func cvc_didLongPressQuote(_ cell: CVCell,
                               itemViewModel: CVItemViewModelImpl,
                               shouldAllowReply: Bool) {}

    // TODO:
    func cvc_didLongPressSystemMessage(_ cell: CVCell,
                                       itemViewModel: CVItemViewModelImpl) {}

    // TODO:
    func cvc_didLongPressSticker(_ cell: CVCell,
                                 itemViewModel: CVItemViewModelImpl,
                                 shouldAllowReply: Bool) {}

    // TODO:
    func cvc_didChangeLongpress(_ itemViewModel: CVItemViewModelImpl) {}

    // TODO:
    func cvc_didEndLongpress(_ itemViewModel: CVItemViewModelImpl) {}

    // TODO:
    func cvc_didCancelLongpress(_ itemViewModel: CVItemViewModelImpl) {}

    // MARK: -

    // TODO:
    func cvc_didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl) {}

    // TODO:
    func cvc_didTapSenderAvatar(_ interaction: TSInteraction) {}

    // TODO:
    func cvc_shouldAllowReplyForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool { false }

    // TODO:
    func cvc_didTapReactions(reactionState: InteractionReactionState,
                             message: TSMessage) {}

    func cvc_didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        let viewController = LongTextViewController(itemViewModel: itemViewModel)
        viewController.delegate = self
        navigationController?.pushViewController(viewController, animated: true)
    }

    // TODO:
    var cvc_hasPendingMessageRequest: Bool { false }

    func cvc_didTapFailedOrPendingDownloads(_ message: TSMessage) {}

    // MARK: - Messages

    func cvc_didTapBodyMedia(itemViewModel: CVItemViewModelImpl,
                         attachmentStream: TSAttachmentStream,
                         imageView: UIView) {
        guard let thread = thread else {
            owsFailDebug("Missing thread.")
            return
        }
        let mediaPageVC = MediaPageViewController(
            initialMediaAttachment: attachmentStream,
            thread: thread,
            showingSingleMessage: true
        )
        mediaPageVC.mediaGallery.addDelegate(self)
        present(mediaPageVC, animated: true)
    }

    func cvc_didTapGenericAttachment(_ attachment: CVComponentGenericAttachment) -> CVAttachmentTapAction {
        if attachment.canQuickLook {
            let previewController = QLPreviewController()
            previewController.dataSource = attachment
            present(previewController, animated: true)
            return .handledByDelegate
        } else {
            return .default
        }
    }

    func cvc_didTapQuotedReply(_ quotedReply: OWSQuotedReplyModel) {}

    func cvc_didTapLinkPreview(_ linkPreview: OWSLinkPreview) {
        guard let urlString = linkPreview.urlString else {
            owsFailDebug("Missing url.")
            return
        }
        guard let url = URL(string: urlString) else {
            owsFailDebug("Invalid url: \(urlString).")
            return
        }
        UIApplication.shared.open(url, options: [:])
    }

    func cvc_didTapContactShare(_ contactShare: ContactShareViewModel) {
        let contactViewController = ContactViewController(contactShare: contactShare)
        self.navigationController?.pushViewController(contactViewController, animated: true)
    }

    func cvc_didTapSendMessage(toContactShare contactShare: ContactShareViewModel) {
        contactShareViewHelper.sendMessage(contactShare: contactShare, fromViewController: self)
    }

    func cvc_didTapSendInvite(toContactShare contactShare: ContactShareViewModel) {
        contactShareViewHelper.showInviteContact(contactShare: contactShare, fromViewController: self)
    }

    func cvc_didTapAddToContacts(contactShare: ContactShareViewModel) {
        contactShareViewHelper.showAddToContacts(contactShare: contactShare, fromViewController: self)
    }

    func cvc_didTapStickerPack(_ stickerPackInfo: StickerPackInfo) {
        let packView = StickerPackViewController(stickerPackInfo: stickerPackInfo)
        packView.present(from: self, animated: true)
    }

    func cvc_didTapGroupInviteLink(url: URL) {
        GroupInviteLinksUI.openGroupInviteLink(url, fromViewController: self)
    }

    func cvc_didTapMention(_ mention: Mention) {}

    // MARK: - Selection

    // TODO:
    var isShowingSelectionUI: Bool { false }

    // TODO:
    func cvc_isMessageSelected(_ interaction: TSInteraction) -> Bool { false }

    // TODO:
    func cvc_didSelectViewItem(_ itemViewModel: CVItemViewModelImpl) {}

    // TODO:
    func cvc_didDeselectViewItem(_ itemViewModel: CVItemViewModelImpl) {}

    // MARK: - System Cell

    // TODO:
    func cvc_didTapNonBlockingIdentityChange(_ address: SignalServiceAddress) {}

    // TODO:
    func cvc_didTapInvalidIdentityKeyErrorMessage(_ message: TSInvalidIdentityKeyErrorMessage) {}

    // TODO:
    func cvc_didTapCorruptedMessage(_ message: TSErrorMessage) {}

    // TODO:
    func cvc_didTapSessionRefreshMessage(_ message: TSErrorMessage) {}

    // See: resendGroupUpdate
    // TODO:
    func cvc_didTapResendGroupUpdateForErrorMessage(_ errorMessage: TSErrorMessage) {}

    // TODO:
    func cvc_didTapShowFingerprint(_ address: SignalServiceAddress) {}

    // TODO:
    func cvc_didTapIndividualCall(_ call: TSCall) {}

    // TODO:
    func cvc_didTapGroupCall() {}

    // TODO:
    func cvc_didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {}

    // TODO:
    func cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: TSInfoMessage,
                                                          oldGroupModel: TSGroupModel,
                                                          newGroupModel: TSGroupModel) {}

    func cvc_didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) {}

    // TODO:
    func cvc_didTapShowConversationSettings() {}

    // TODO:
    func cvc_didTapShowConversationSettingsAndShowMemberRequests() {}

    // TODO:
    func cvc_didTapShowUpgradeAppUI() {}

    // TODO:
    func cvc_didTapUpdateSystemContact(_ address: SignalServiceAddress,
                                       newNameComponents: PersonNameComponents) {}

    func cvc_didTapViewOnceAttachment(_ interaction: TSInteraction) {
        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return
        }
        let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
        ViewOnceMessageViewController.tryToPresent(interaction: itemViewModel.interaction,
                                                   from: self)
    }

    // TODO:
    func cvc_didTapViewOnceExpired(_ interaction: TSInteraction) {}
}
