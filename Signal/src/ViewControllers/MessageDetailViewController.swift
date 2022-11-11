//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import QuickLook
import SignalServiceKit
import SignalMessaging

protocol MessageDetailViewDelegate: AnyObject {
    func detailViewMessageWasDeleted(_ messageDetailViewController: MessageDetailViewController)
}

class MessageDetailViewController: OWSTableViewController2 {

    private enum DetailViewError: Error {
        case messageWasDeleted
    }

    weak var detailDelegate: MessageDetailViewDelegate?

    // MARK: Properties

    weak var pushPercentDrivenTransition: UIPercentDrivenInteractiveTransition?
    private var popPercentDrivenTransition: UIPercentDrivenInteractiveTransition?

    private var renderItem: CVRenderItem?
    private var thread: TSThread? { renderItem?.itemModel.thread }

    private(set) var message: TSMessage
    private var wasDeleted: Bool = false
    private var isIncoming: Bool { message as? TSIncomingMessage != nil }
    private var expires: Bool { message.expiresInSeconds > 0 }

    private struct MessageRecipientModel {
        let address: SignalServiceAddress
        let accessoryText: String
        let displayUDIndicator: Bool
    }
    private let messageRecipients = AtomicOptional<[MessageReceiptStatus: [MessageRecipientModel]]>(nil)

    private let cellView = CVCellView()

    private var attachments: [TSAttachment]?
    private var attachmentStreams: [TSAttachmentStream]? {
        return attachments?.compactMap { $0 as? TSAttachmentStream }
    }
    var hasMediaAttachment: Bool {
        guard let attachmentStreams = self.attachmentStreams, !attachmentStreams.isEmpty else {
            return false
        }
        return true
    }

    private let byteCountFormatter: ByteCountFormatter = ByteCountFormatter()

    private lazy var contactShareViewHelper: ContactShareViewHelper = {
        let contactShareViewHelper = ContactShareViewHelper()
        contactShareViewHelper.delegate = self
        return contactShareViewHelper
    }()

    private var databaseUpdateTimer: Timer?

    private var expiryLabelTimer: Timer?

    private var expiryLabelName: String {
        NSLocalizedString(
            "MESSAGE_METADATA_VIEW_DISAPPEARS_IN",
            comment: "Label for the 'disappears' field of the 'message metadata' view."
        )
    }

    private lazy var expirationLabelFormatter: DateComponentsFormatter = {
        let expirationLabelFormatter = DateComponentsFormatter()
        expirationLabelFormatter.unitsStyle = .full
        expirationLabelFormatter.allowedUnits = [.weekOfMonth, .day, .hour, .minute, .second]
        expirationLabelFormatter.maximumUnitCount = 2
        return expirationLabelFormatter
    }()

    private var expiryLabelValue: String {
        let expiresAt = message.expiresAt
        guard expiresAt > 0 else {
            owsFailDebug("We should never hit this code, because we should never show the label")
            return NSLocalizedString(
                "MESSAGE_METADATA_VIEW_NEVER_DISAPPEARS",
                comment: "On the 'message metadata' view, if a message never disappears, this text is shown as a fallback."
            )
        }

        let now = Date()
        let expiresAtDate = Date(millisecondsSince1970: expiresAt)

        let result: String?
        if expiresAtDate >= now {
            result = expirationLabelFormatter.string(from: now, to: expiresAtDate)
        } else {
            // This is unusual, but could happen if you change your device clock.
            result = expirationLabelFormatter.string(from: 0)
        }

        guard let result = result else {
            owsFailDebug("Could not format duration")
            return ""
        }
        return result
    }

    private var expiryLabelAttributedText: NSAttributedString {
        Self.valueLabelAttributedText(name: expiryLabelName, value: expiryLabelValue)
    }

    private lazy var expiryLabel: UILabel = {
        Self.buildValueLabel(name: expiryLabelName, value: expiryLabelValue)
    }()

    // MARK: Initializers

    required init(
        message: TSMessage,
        thread: TSThread
    ) {
        self.message = message
        super.init()
    }

    // MARK: De-initializers

    deinit {
        expiryLabelTimer?.invalidate()
    }

    // MARK: View Lifecycle

    override func themeDidChange() {
        super.themeDidChange()

        refreshContent()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString(
            "MESSAGE_METADATA_VIEW_TITLE",
            comment: "Title for the 'message metadata' view."
        )

        databaseStorage.appendDatabaseChangeDelegate(self)

        startExpiryLabelTimerIfNecessary()

        // Use our own swipe back animation, since the message
        // details are presented as a "drawer" type view.
        let panGesture = DirectionalPanGestureRecognizer(direction: .horizontal, target: self, action: #selector(handlePan))

        // Allow panning with trackpad
        if #available(iOS 13.4, *) { panGesture.allowedScrollTypesMask = .continuous }

        view.addGestureRecognizer(panGesture)

        if let interactivePopGestureRecognizer = navigationController?.interactivePopGestureRecognizer {
            interactivePopGestureRecognizer.require(toFail: panGesture)
        }

        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        refreshContent()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.refreshContent()
        }
    }

    private func startExpiryLabelTimerIfNecessary() {
        guard message.expiresAt > 0 else { return }
        guard expiryLabelTimer == nil else { return }
        expiryLabelTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            self?.updateExpiryLabel()
        }
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        contents.addSection(buildMessageSection())

        if isIncoming {
            contents.addSection(buildSenderSection())
        } else {
            contents.addSections(buildStatusSections())
        }

        self.contents = contents
    }

    private func buildRenderItem(interactionId: String) -> CVRenderItem? {
        databaseStorage.read { transaction in
            guard let interaction = TSInteraction.anyFetch(
                uniqueId: interactionId,
                transaction: transaction
            ) else {
                owsFailDebug("Missing interaction.")
                return nil
            }
            guard let thread = TSThread.anyFetch(
                uniqueId: interaction.uniqueThreadId,
                transaction: transaction
            ) else {
                owsFailDebug("Missing thread.")
                return nil
            }
            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction)

            let chatColor = ChatColors.chatColorForRendering(thread: thread, transaction: transaction)

            let conversationStyle = ConversationStyle(
                type: .messageDetails,
                thread: thread,
                viewWidth: view.width - (cellOuterInsets.totalWidth + (Self.cellHInnerMargin * 2)),
                hasWallpaper: false,
                isWallpaperPhoto: false,
                chatColor: chatColor
            )

            return CVLoader.buildStandaloneRenderItem(
                interaction: interaction,
                thread: thread,
                threadAssociatedData: threadAssociatedData,
                conversationStyle: conversationStyle,
                transaction: transaction
            )
        }
    }

    private func buildMessageSection() -> OWSTableSection {
        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return OWSTableSection()
        }

        let messageStack = UIStackView()
        messageStack.axis = .vertical

        cellView.reset()

        cellView.configure(renderItem: renderItem, componentDelegate: self)
        cellView.isCellVisible = true
        cellView.autoSetDimension(.height, toSize: renderItem.cellSize.height)

        let cellContainer = UIView()
        cellContainer.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)

        cellContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapCell)))

        cellContainer.addSubview(cellView)
        cellView.autoPinHeightToSuperviewMargins()

        cellView.autoPinEdge(toSuperviewEdge: .leading)
        cellView.autoPinEdge(toSuperviewEdge: .trailing)

        messageStack.addArrangedSubview(cellContainer)

        // Sent time

        let sentTimeLabel = Self.buildValueLabel(
            name: NSLocalizedString("MESSAGE_METADATA_VIEW_SENT_DATE_TIME",
                                    comment: "Label for the 'sent date & time' field of the 'message metadata' view."),
            value: DateUtil.formatPastTimestampRelativeToNow(message.timestamp)
        )
        messageStack.addArrangedSubview(sentTimeLabel)
        sentTimeLabel.isUserInteractionEnabled = true
        sentTimeLabel.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(didLongPressSent)))

        if isIncoming {
            // Received time
            messageStack.addArrangedSubview(Self.buildValueLabel(
                name: NSLocalizedString("MESSAGE_METADATA_VIEW_RECEIVED_DATE_TIME",
                                        comment: "Label for the 'received date & time' field of the 'message metadata' view."),
                value: DateUtil.formatPastTimestampRelativeToNow(message.receivedAtTimestamp)
            ))
        }

        if expires {
            messageStack.addArrangedSubview(expiryLabel)
        }

        if hasMediaAttachment, attachments?.count == 1, let attachment = attachments?.first {
            if let sourceFilename = attachment.sourceFilename {
                messageStack.addArrangedSubview(Self.buildValueLabel(
                    name: NSLocalizedString("MESSAGE_METADATA_VIEW_SOURCE_FILENAME",
                                            comment: "Label for the original filename of any attachment in the 'message metadata' view."),
                    value: sourceFilename
                ))
            }

            if let formattedByteCount = byteCountFormatter.string(for: attachment.byteCount) {
                messageStack.addArrangedSubview(Self.buildValueLabel(
                    name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_FILE_SIZE",
                                            comment: "Label for file size of attachments in the 'message metadata' view."),
                    value: formattedByteCount
                ))
            } else {
                owsFailDebug("formattedByteCount was unexpectedly nil")
            }

            if DebugFlags.messageDetailsExtraInfo {
                let contentType = attachment.contentType
                messageStack.addArrangedSubview(Self.buildValueLabel(
                    name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_MIME_TYPE",
                                            comment: "Label for the MIME type of attachments in the 'message metadata' view."),
                    value: contentType
                ))
            }
        }

        let section = OWSTableSection()
        section.add(.init(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none
                cell.contentView.addSubview(messageStack)
                messageStack.autoPinWidthToSuperviewMargins()
                messageStack.autoPinHeightToSuperview(withMargin: 20)
                return cell
            }, actionBlock: {

            }
        ))

        return section
    }

    @objc
    private func didTapCell(_ sender: UITapGestureRecognizer) {
        // For now, only allow tapping on audio cells. The full gamut of cell types
        // might result in unexpected behaviors if made tappable from the detail view.
        guard renderItem?.componentState.audioAttachment != nil else {
            return
        }

        _ = cellView.handleTap(sender: sender, componentDelegate: self)
    }

    private func buildSenderSection() -> OWSTableSection {
        guard let incomingMessage = message as? TSIncomingMessage else {
            owsFailDebug("Unexpected message type")
            return OWSTableSection()
        }

        let section = OWSTableSection()
        section.headerTitle = NSLocalizedString(
            "MESSAGE_DETAILS_VIEW_SENT_FROM_TITLE",
            comment: "Title for the 'sent from' section on the 'message details' view."
        )
        section.add(contactItem(
            for: incomingMessage.authorAddress,
            accessoryText: DateUtil.formatPastTimestampRelativeToNow(incomingMessage.timestamp),
            displayUDIndicator: incomingMessage.wasReceivedByUD
        ))
        return section
    }

    private func buildStatusSections() -> [OWSTableSection] {
        guard nil != message as? TSOutgoingMessage else {
            owsFailDebug("Unexpected message type")
            return []
        }

        var sections = [OWSTableSection]()

        let orderedStatusGroups: [MessageReceiptStatus] = [
            .viewed,
            .read,
            .delivered,
            .sent,
            .uploading,
            .sending,
            .pending,
            .failed,
            .skipped
        ]

        guard let messageRecipients = messageRecipients.get() else { return [] }

        for statusGroup in orderedStatusGroups {
            guard let recipients = messageRecipients[statusGroup], !recipients.isEmpty else { continue }

            let section = OWSTableSection()
            sections.append(section)

            let sectionTitle = self.sectionTitle(for: statusGroup)
            if let iconName = sectionIconName(for: statusGroup) {
                let headerView = UIView()
                headerView.layoutMargins = cellOuterInsetsWithMargin(
                    top: (defaultSpacingBetweenSections ?? 0) + 12,
                    left: Self.cellHInnerMargin * 0.5,
                    bottom: 10,
                    right: Self.cellHInnerMargin * 0.5
                )

                let label = UILabel()
                label.textColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90
                label.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
                label.text = sectionTitle

                headerView.addSubview(label)
                label.autoPinHeightToSuperviewMargins()
                label.autoPinEdge(toSuperviewMargin: .leading)

                let iconView = UIImageView()
                iconView.contentMode = .scaleAspectFit
                iconView.setTemplateImageName(
                    iconName,
                    tintColor: Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90
                )
                headerView.addSubview(iconView)
                iconView.autoAlignAxis(.horizontal, toSameAxisOf: label)
                iconView.autoPinEdge(.leading, to: .trailing, of: label)
                iconView.autoPinEdge(toSuperviewMargin: .trailing)
                iconView.autoSetDimension(.height, toSize: 12)

                section.customHeaderView = headerView
            } else {
                section.headerTitle = sectionTitle
            }

            section.separatorInsetLeading = NSNumber(value: Float(Self.cellHInnerMargin + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing))

            for recipient in recipients {
                section.add(contactItem(
                    for: recipient.address,
                    accessoryText: recipient.accessoryText,
                    displayUDIndicator: recipient.displayUDIndicator
                ))
            }
        }

        return sections
    }

    private func contactItem(for address: SignalServiceAddress, accessoryText: String, displayUDIndicator: Bool) -> OWSTableItem {
        return .init(customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                let tableView = self.tableView
                guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                    owsFailDebug("Missing cell.")
                    return UITableViewCell()
                }

                Self.databaseStorage.read { transaction in
                    let configuration = ContactCellConfiguration(address: address, localUserDisplayMode: .asUser)
                    configuration.accessoryView = self.buildAccessoryView(text: accessoryText,
                                                                          displayUDIndicator: displayUDIndicator,
                                                                          transaction: transaction)
                    cell.configure(configuration: configuration, transaction: transaction)
                }
                return cell
            },
            actionBlock: { [weak self] in
                guard let self = self else { return }
                let actionSheet = MemberActionSheet(address: address, groupViewHelper: nil)
                actionSheet.present(from: self)
            }
        )
    }

    private func updateExpiryLabel() {
        expiryLabel.attributedText = expiryLabelAttributedText
    }

    private func buildAccessoryView(text: String,
                                    displayUDIndicator: Bool,
                                    transaction: SDSAnyReadTransaction) -> ContactCellAccessoryView {
        let label = CVLabel()
        label.textAlignment = .right
        let labelConfig = CVLabelConfig(text: text,
                                        font: .ows_dynamicTypeFootnoteClamped,
                                        textColor: Theme.ternaryTextColor)
        labelConfig.applyForRendering(label: label)
        let labelSize = CVText.measureLabel(config: labelConfig, maxWidth: .greatestFiniteMagnitude)

        let shouldShowUD = preferences.shouldShowUnidentifiedDeliveryIndicators(transaction: transaction)

        guard displayUDIndicator && shouldShowUD else {
            return ContactCellAccessoryView(accessoryView: label, size: labelSize)
        }

        let imageView = CVImageView()
        imageView.setTemplateImageName(Theme.iconName(.sealedSenderIndicator), tintColor: Theme.ternaryTextColor)
        let imageSize = CGSize.square(20)

        let hStack = ManualStackView(name: "hStack")
        let hStackConfig = CVStackViewConfig(axis: .horizontal,
                                             alignment: .center,
                                             spacing: 8,
                                             layoutMargins: .zero)
        let hStackMeasurement = hStack.configure(config: hStackConfig,
                                                 subviews: [imageView, label],
                                                 subviewInfos: [
                                                    imageSize.asManualSubviewInfo(hasFixedSize: true),
                                                    labelSize.asManualSubviewInfo
                                                 ])
        let hStackSize = hStackMeasurement.measuredSize
        return ContactCellAccessoryView(accessoryView: hStack, size: hStackSize)
    }

    private static func valueLabelAttributedText(name: String, value: String) -> NSAttributedString {
        .composed(of: [
            name.styled(with: .font(UIFont.ows_dynamicTypeFootnoteClamped.ows_semibold)),
            " ",
            value
        ])
    }

    private static func buildValueLabel(name: String, value: String) -> UILabel {
        let label = UILabel()
        label.textColor = Theme.primaryTextColor
        label.font = .ows_dynamicTypeFootnoteClamped
        label.attributedText = valueLabelAttributedText(name: name, value: value)
        return label
    }

    // MARK: - Actions

    private func sectionIconName(for messageReceiptStatus: MessageReceiptStatus) -> String? {
        switch messageReceiptStatus {
        case .uploading, .sending, .pending:
            return "message_status_sending"
        case .sent:
            return "message_status_sent"
        case .delivered:
            return "message_status_delivered"
        case .read, .viewed:
            return "message_status_read"
        case .failed, .skipped:
            return nil
        }
    }

    private func sectionTitle(for messageReceiptStatus: MessageReceiptStatus) -> String {
        switch messageReceiptStatus {
        case .uploading:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_UPLOADING",
                              comment: "Status label for messages which are uploading.")
        case .sending:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_SENDING",
                                     comment: "Status label for messages which are sending.")
        case .pending:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_PAUSED",
                                     comment: "Status label for messages which are paused.")
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
        case .viewed:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_VIEWED",
                              comment: "Status label for messages which are viewed.")
        }
    }

    private var isPanning = false

    @objc
    func handlePan(_ sender: UIPanGestureRecognizer) {
        var xOffset = sender.translation(in: view).x
        var xVelocity = sender.velocity(in: view).x

        if CurrentAppContext().isRTL {
            xOffset = -xOffset
            xVelocity = -xVelocity
        }

        if xOffset < 0 { xOffset = 0 }

        let percentage = xOffset / view.width

        switch sender.state {
        case .began:
            popPercentDrivenTransition = UIPercentDrivenInteractiveTransition()
            navigationController?.popViewController(animated: true)
        case .changed:
            popPercentDrivenTransition?.update(percentage)
        case .ended:
            let percentageThreshold: CGFloat = 0.5
            let velocityThreshold: CGFloat = 500

            let shouldFinish = (percentage >= percentageThreshold && xVelocity >= 0) || (xVelocity >= velocityThreshold)
            if shouldFinish {
                popPercentDrivenTransition?.finish()
            } else {
                popPercentDrivenTransition?.cancel()
            }
            popPercentDrivenTransition = nil
        case .cancelled, .failed:
            popPercentDrivenTransition?.cancel()
            popPercentDrivenTransition = nil
        case .possible:
            break
        @unknown default:
            break
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

        let toast = ToastController(text: NSLocalizedString(
            "MESSAGE_DETAIL_VIEW_DID_COPY_SENT_TIMESTAMP",
            comment: "Toast indicating that the user has copied the sent timestamp."
        ))
        toast.presentToastView(from: .bottom, of: view, inset: view.safeAreaInsets.bottom + 8)
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
        self.didReloadAllSectionsInMediaGallery(mediaGallery)
    }

    func didAddSectionInMediaGallery(_ mediaGallery: MediaGallery) {
        // Does not affect the current item.
    }

    func didReloadAllSectionsInMediaGallery(_ mediaGallery: MediaGallery) {
        if let firstAttachment = self.attachments?.first,
           mediaGallery.ensureLoadedForDetailView(focusedAttachment: firstAttachment) == nil {
            // Assume the item was deleted.
            self.dismiss(animated: true) {
                self.navigationController?.popViewController(animated: true)
            }
        }
    }
}

// MARK: -

extension MessageDetailViewController: ContactShareViewHelperDelegate {
    public func didCreateOrEditContact() {
        updateTableContents()
        self.dismiss(animated: true)
    }
}

extension MessageDetailViewController: LongTextViewDelegate {
    public func longTextViewMessageWasDeleted(_ longTextViewController: LongTextViewController) {
        self.detailDelegate?.detailViewMessageWasDeleted(self)
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
                                        cornerRadius: CVComponentMessage.bubbleSharpCornerRadius * 2)
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

extension MessageDetailViewController: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()

        guard databaseChanges.didUpdate(interaction: self.message) else {
            return
        }

        refreshContentForDatabaseUpdate()
    }

    public func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()

        refreshContentForDatabaseUpdate()
    }

    public func databaseChangesDidReset() {
        AssertIsOnMainThread()

        refreshContentForDatabaseUpdate()
    }

    /// ForceImmediately should only be used based on user input, since it ignores any debouncing
    /// and makes an update happen right away (killing any scheduled/debounced updates)
    private func refreshContentForDatabaseUpdate(forceImmediately: Bool = false) {
        // Updating this view is slightly expensive and there will be tons of relevant
        // database updates when sending to a large group. Update latency isn't that
        // imporant, so we de-bounce to never update this view more than once every N seconds.

        let updateBlock = { [weak self] in
            guard let self = self else {
                return
            }
            self.databaseUpdateTimer?.invalidate()
            self.databaseUpdateTimer = nil
            self.refreshContent()
        }
        if forceImmediately {
            updateBlock()
            return
        }

        guard databaseUpdateTimer == nil else { return }

        self.databaseUpdateTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0,
            repeats: false
        ) { _ in
            assert(self.databaseUpdateTimer != nil)
            updateBlock()
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
            try databaseStorage.readThrows { transaction in
                let uniqueId = self.message.uniqueId
                guard let newMessage = TSInteraction.anyFetch(uniqueId: uniqueId,
                                                              transaction: transaction) as? TSMessage else {
                    Logger.error("Message was deleted")
                    throw DetailViewError.messageWasDeleted
                }
                self.message = newMessage
                self.attachments = newMessage.mediaAttachments(with: transaction.unwrapGrdbRead)
            }

            guard let renderItem = buildRenderItem(interactionId: message.uniqueId) else {
                owsFailDebug("Could not build renderItem.")
                throw DetailViewError.messageWasDeleted
            }
            self.renderItem = renderItem

            if isIncoming {
                updateTableContents()
            } else {
                refreshMessageRecipientsAsync()
            }
        } catch DetailViewError.messageWasDeleted {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.detailDelegate?.detailViewMessageWasDeleted(self)
            }
        } catch {
            owsFailDebug("unexpected error: \(error)")
        }
    }

    private func refreshMessageRecipientsAsync() {
        guard let outgoingMessage = message as? TSOutgoingMessage else {
            return owsFailDebug("Unexpected message type")
        }

        DispatchQueue.sharedUserInitiated.async { [weak self] in
            guard let self = self else { return }

            let messageRecipientAddressesUnsorted = outgoingMessage.recipientAddresses()
            let messageRecipientAddressesSorted = self.databaseStorage.read { transaction in
                self.contactsManagerImpl.sortSignalServiceAddresses(
                    messageRecipientAddressesUnsorted,
                    transaction: transaction
                )
            }
            let messageRecipientAddressesGrouped = messageRecipientAddressesSorted.reduce(
                into: [MessageReceiptStatus: [MessageRecipientModel]]()
            ) { result, address in
                guard let recipientState = outgoingMessage.recipientState(for: address) else {
                    return owsFailDebug("no message status for recipient: \(address).")
                }

                let (status, statusMessage, _) = MessageRecipientStatusUtils.recipientStatusAndStatusMessage(
                    outgoingMessage: outgoingMessage,
                    recipientState: recipientState
                )
                var bucket = result[status] ?? []

                switch status {
                case .delivered, .read, .sent, .viewed:
                    bucket.append(MessageRecipientModel(
                        address: address,
                        accessoryText: statusMessage,
                        displayUDIndicator: recipientState.wasSentByUD
                    ))
                case .sending, .failed, .skipped, .uploading, .pending:
                    bucket.append(MessageRecipientModel(
                        address: address,
                        accessoryText: "",
                        displayUDIndicator: false
                    ))
                }

                result[status] = bucket
            }

            self.messageRecipients.set(messageRecipientAddressesGrouped)
            DispatchQueue.main.async { self.updateTableContents() }
        }
    }
}

// MARK: -

extension MessageDetailViewController: CVComponentDelegate {

    func cvc_enqueueReload() {
        self.refreshContent()
    }

    func cvc_enqueueReloadWithoutCaches() {
        self.refreshContentForDatabaseUpdate(forceImmediately: true)
    }

    // MARK: - Body Text Items

    func cvc_didTapBodyTextItem(_ item: CVTextLabel.Item) {}

    func cvc_didLongPressBodyTextItem(_ item: CVTextLabel.Item) {}

    // MARK: - System Message Items

    func cvc_didTapSystemMessageItem(_ item: CVTextLabel.Item) {}

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

    func cvc_didTapBrokenVideo() {}

    // MARK: - Messages

    func cvc_didTapBodyMedia(
        itemViewModel: CVItemViewModelImpl,
        attachmentStream: TSAttachmentStream,
        imageView: UIView
    ) {
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

    func cvc_didTapProxyLink(url: URL) {}

    func cvc_didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl) {}

    // Never wrap gifts on the message details screen
    func cvc_willWrapGift(_ messageUniqueId: String) -> Bool { false }

    func cvc_willShakeGift(_ messageUniqueId: String) -> Bool { false }

    func cvc_willUnwrapGift(_ itemViewModel: CVItemViewModelImpl) {}

    func cvc_didTapGiftBadge(_ itemViewModel: CVItemViewModelImpl, profileBadge: ProfileBadge, isExpired: Bool, isRedeemed: Bool) {}

    func cvc_prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {}

    func cvc_beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation {
        return {}
    }

    var isConversationPreview: Bool { true }

    var wallpaperBlurProvider: WallpaperBlurProvider? { nil }

    // MARK: - Selection

    public var selectionState: CVSelectionState { CVSelectionState() }

    // MARK: - System Cell

    // TODO:
    func cvc_didTapPreviouslyVerifiedIdentityChange(_ address: SignalServiceAddress) {}

    // TODO:
    func cvc_didTapUnverifiedIdentityChange(_ address: SignalServiceAddress) {}

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
    func cvc_didTapPendingOutgoingMessage(_ message: TSOutgoingMessage) {}

    // TODO:
    func cvc_didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {}

    // TODO:
    func cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: TSInfoMessage,
                                                          oldGroupModel: TSGroupModel,
                                                          newGroupModel: TSGroupModel) {}

    func cvc_didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) {}

    func cvc_didTapViewGroupDescription(groupModel: TSGroupModel?) {}

    // TODO:
    func cvc_didTapShowConversationSettings() {}

    // TODO:
    func cvc_didTapShowConversationSettingsAndShowMemberRequests() {}

    // TODO:
    func cvc_didTapBlockRequest(
        groupModel: TSGroupModelV2,
        requesterName: String,
        requesterUuid: UUID
    ) {}

    // TODO:
    func cvc_didTapShowUpgradeAppUI() {}

    // TODO:
    func cvc_didTapUpdateSystemContact(_ address: SignalServiceAddress,
                                       newNameComponents: PersonNameComponents) {}

    // TODO:
    func cvc_didTapPhoneNumberChange(uuid: UUID, phoneNumberOld: String, phoneNumberNew: String) {}

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

    // TODO:
    func cvc_didTapUnknownThreadWarningGroup() {}
    // TODO:
    func cvc_didTapUnknownThreadWarningContact() {}
    func cvc_didTapDeliveryIssueWarning(_ message: TSErrorMessage) {}
}

extension MessageDetailViewController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return (animationController as? AnimationController)?.percentDrivenTransition
    }

    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let animationController = AnimationController(operation: operation)
        if operation == .push { animationController.percentDrivenTransition = pushPercentDrivenTransition }
        if operation == .pop { animationController.percentDrivenTransition = popPercentDrivenTransition }
        return animationController
    }
}

private class AnimationController: NSObject, UIViewControllerAnimatedTransitioning {
    weak var percentDrivenTransition: UIPercentDrivenInteractiveTransition?

    let operation: UINavigationController.Operation
    required init(operation: UINavigationController.Operation) {
        self.operation = operation
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.35
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to) else {
            owsFailDebug("Missing view controllers.")
            return transitionContext.completeTransition(false)
        }

        let containerView = transitionContext.containerView
        let directionMultiplier: CGFloat = CurrentAppContext().isRTL ? -1 : 1

        let bottomViewHiddenTransform = CGAffineTransform(translationX: (fromView.width / 3) * directionMultiplier, y: 0)
        let topViewHiddenTransform = CGAffineTransform(translationX: -fromView.width * directionMultiplier, y: 0)

        let bottomViewOverlay = UIView()
        bottomViewOverlay.backgroundColor = .ows_blackAlpha10

        let topView: UIView
        let bottomView: UIView

        let isPushing = operation == .push

        if isPushing {
            topView = fromView
            bottomView = toView
            bottomView.transform = bottomViewHiddenTransform
            bottomViewOverlay.alpha = 1
        } else {
            topView = toView
            bottomView = fromView
            topView.transform = topViewHiddenTransform
            bottomViewOverlay.alpha = 0
        }

        containerView.addSubview(bottomView)
        containerView.addSubview(topView)

        bottomView.addSubview(bottomViewOverlay)
        bottomViewOverlay.frame = bottomView.bounds

        let animationOptions: UIView.AnimationOptions
        if percentDrivenTransition != nil {
            animationOptions = .curveLinear
        } else {
            animationOptions = .curveEaseInOut
        }

        UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0, options: animationOptions) {
            if isPushing {
                topView.transform = topViewHiddenTransform
                bottomView.transform = .identity
                bottomViewOverlay.alpha = 0
            } else {
                topView.transform = .identity
                bottomView.transform = bottomViewHiddenTransform
                bottomViewOverlay.alpha = 1
            }
        } completion: { _ in
            bottomView.transform = .identity
            topView.transform = .identity
            bottomViewOverlay.removeFromSuperview()

            if transitionContext.transitionWasCancelled {
                toView.removeFromSuperview()
            } else {
                fromView.removeFromSuperview()

                // When completing the transition, the first responder chain gets
                // messed with. We don't want the keyboard to present when returning
                // from message details, so we dismiss it when we leave the view.
                if let fromViewController = transitionContext.viewController(forKey: .from) as? ConversationViewController {
                    fromViewController.dismissKeyBoard()
                }
            }

            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
}
