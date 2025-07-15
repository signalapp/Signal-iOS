//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import PassKit
import SignalServiceKit
import SignalUI

class MediaGalleryFileCell: MediaTileListModeCell {

    static let reuseIdentifier = "MediaGalleryFileCell"

    private var attachment: ReferencedAttachmentStream?
    private var receivedAtDate: Date?
    private var owningMessage: TSMessage?
    private var mediaMetadata: MediaMetadata?

    private var fileItem: MediaGalleryCellItemOtherFile? {
        didSet {
            guard let fileItem else {
                attachment = nil
                receivedAtDate = nil
                owningMessage = nil
                mediaMetadata = nil
                return
            }
            attachment = fileItem.attachmentStream
            receivedAtDate = fileItem.receivedAtDate
            owningMessage = fileItem.message
            mediaMetadata = fileItem.metadata
        }
    }

    class var defaultCellHeight: CGFloat { 88 }

    private static let contentInset = UIEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 10)

    override class var contentCardVerticalInset: CGFloat { 6 }

    private static var cellHeights: [UIContentSizeCategory: CGFloat] = [:]

    class func cellHeight(for item: MediaGalleryCellItem, maxWidth: CGFloat) -> CGFloat {
        guard case let .otherFile(fileItem) = item else {
            owsFailDebug("Unexpected item type")
            return defaultCellHeight
        }

        let currentContentSizeCategory = UITraitCollection.current.preferredContentSizeCategory

        if let cellHeight: CGFloat = {
            return cellHeights[currentContentSizeCategory]
        }() {
            return cellHeight
        }

        guard let attachment = item.attachmentStream else {
            return defaultCellHeight
        }
        let genericAttachment = CVComponentState.GenericAttachment(
            attachment: .stream(attachment)
        )

        let genericAttachmentViewSize = CVComponentGenericAttachment.measure(
            maxWidth: maxWidth,
            measurementBuilder: CVCellMeasurement.Builder(),
            genericAttachment: genericAttachment,
            interaction: fileItem.interaction
        )

        let cellHeight = genericAttachmentViewSize.height + Self.contentInset.totalHeight + 2*Self.contentCardVerticalInset
        cellHeights[currentContentSizeCategory] = cellHeight

        return cellHeight
    }

    private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    private var itemModel: CVItemModel?

    private var genericAttachmentView: CVComponentView?

    private let genericAttachmentContainerView: UIView = {
        let view = UIView.container()
        view.backgroundColor = UIColor(dynamicProvider: { _ in Theme.tableCell2PresentedBackgroundColor })
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        return view
    }()

    private func createGenericAttachmentView(transaction: DBReadTransaction) {
        owsAssertDebug(genericAttachmentView == nil)

        guard let fileItem else {
            owsFailDebug("fileItem not set")
            return
        }

        let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: fileItem.thread, transaction: transaction)
        // Make an itemModel which is needed to play the audio file.
        // This is only used to save the playback rate, which is kind of nuts.
        let threadViewModel = ThreadViewModel(
            thread: fileItem.thread,
            forChatList: false,
            transaction: transaction
        )
        let conversationStyle = ConversationStyle(
            type: .default,
            thread: fileItem.thread,
            viewWidth: contentView.bounds.width,
            hasWallpaper: false,
            isWallpaperPhoto: false,
            chatColor: ChatColorSettingStore.Constants.defaultColor.colorSetting
        )
        let coreState = CVCoreState(conversationStyle: conversationStyle, mediaCache: fileItem.mediaCache)
        let viewStateSnapshot = CVViewStateSnapshot.mockSnapshotForStandaloneItems(
            coreState: coreState,
            spoilerReveal: spoilerState.revealState
        )
        let itemBuildingContext = CVItemBuildingContextImpl(
            threadViewModel: threadViewModel,
            viewStateSnapshot: viewStateSnapshot,
            transaction: transaction,
            avatarBuilder: CVAvatarBuilder(transaction: transaction)
        )
        guard let componentState = try? CVComponentState.build(
            interaction: fileItem.interaction,
            itemBuildingContext: itemBuildingContext
        ) else {
            return
        }
        let itemViewState = CVItemViewState.Builder()
        itemViewState.audioPlaybackRate = threadAssociatedData.audioPlaybackRate
        let itemModel = CVItemModel(
            interaction: fileItem.interaction,
            thread: fileItem.thread,
            threadAssociatedData: threadAssociatedData,
            componentState: componentState,
            itemViewState: itemViewState.build(),
            coreState: coreState
        )
        let genericAttachment = CVComponentState.GenericAttachment(attachment: .stream(fileItem.attachmentStream))
        let component = CVComponentGenericAttachment(
            itemModel: itemModel,
            genericAttachment: genericAttachment
        )
        // Always treat as incoming so we get the right colors.
        component.isIncomingOverride = true
        let view = component.buildComponentView(componentDelegate: self)
        view.rootView.translatesAutoresizingMaskIntoConstraints = false

        let measurementBuilder = CVCellMeasurement.Builder()
        measurementBuilder.cellSize = CVComponentGenericAttachment.measure(
            maxWidth: contentView.bounds.width, // actual max width doesn't matter because there's no multiline text
            measurementBuilder: measurementBuilder,
            genericAttachment: genericAttachment,
            interaction: fileItem.interaction
        )
        let cellMeasurement = measurementBuilder.build()
        component.configureForRendering(componentView: view, cellMeasurement: cellMeasurement, componentDelegate: self)
        genericAttachmentContainerView.addSubview(view.rootView)
        view.rootView.autoPinEdgesToSuperviewEdges(with: Self.contentInset)

        self.itemModel = itemModel
        self.genericAttachmentView = view
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.addSubview(genericAttachmentContainerView)
        NSLayoutConstraint.activate([
            genericAttachmentContainerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.contentCardVerticalInset),
            genericAttachmentContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.contentCardVerticalInset),
            genericAttachmentContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -OWSTableViewController2.defaultHOuterMargin)
        ])

        let constraintWithSelectionButton = genericAttachmentContainerView.leadingAnchor.constraint(
            equalTo: selectionButton.trailingAnchor,
            constant: 12
        )
        let constraintWithoutSelectionButton = genericAttachmentContainerView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: OWSTableViewController2.defaultHOuterMargin
        )

        addGestureRecognizer(tapGestureRecognizer)

        super.setupViews(constraintWithSelectionButton: constraintWithSelectionButton,
                         constraintWithoutSelectionButton: constraintWithoutSelectionButton)
    }

    @objc
    private func handleTapGesture(_ sender: UITapGestureRecognizer) {
        guard let fileItem, let itemModel else {
            return
        }
        let genericAttachment = CVComponentGenericAttachment(
            itemModel: itemModel,
            genericAttachment: .init(attachment: .stream(fileItem.attachmentStream))
        )
        if
            PKAddPassesViewController.canAddPasses(),
            let pkPass = genericAttachment.representedPKPass(),
            let addPassesVC = PKAddPassesViewController(pass: pkPass)
        {
            CurrentAppContext().frontmostViewController()?.present(addPassesVC, animated: true, completion: nil)
            return
        } else if let previewController = genericAttachment.createQLPreviewController() {
            CurrentAppContext().frontmostViewController()?.present(previewController, animated: true, completion: nil)
            return
        }
    }

    private func setUpAccessibility(item: MediaGalleryCellItemAudio?) {
        isAccessibilityElement = true

        if let fileItem {
            accessibilityLabel = [
                fileItem.localizedString,
                MediaTileDateFormatter.formattedDateString(for: fileItem.receivedAtDate)
            ]
                .compactMap { $0 }
                .joined(separator: ", ")
        } else {
            accessibilityLabel = ""
        }
    }

    override var cellsAbut: Bool { false }

    private(set) var spoilerState = SpoilerRenderState()

    override func configure(item: MediaGalleryCellItem, spoilerState: SpoilerRenderState) {
        super.configure(item: item, spoilerState: spoilerState)

        guard case let .otherFile(fileItem) = item else {
            owsFailDebug("Unexpected item type")
            return
        }
        self.fileItem = fileItem
        self.spoilerState = spoilerState

        if let genericAttachmentView {
            genericAttachmentView.rootView.removeFromSuperview()
            self.genericAttachmentView = nil
        }

        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            createGenericAttachmentView(transaction: transaction)
        }
    }

    override func makePlaceholder() {
        genericAttachmentView?.rootView.removeFromSuperview()
        genericAttachmentView = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if let item {
            configure(item: item, spoilerState: spoilerState)
        }
    }

    override func setAllowsMultipleSelection(_ allowed: Bool, animated: Bool) {
        tapGestureRecognizer.isEnabled = !allowed
        super.setAllowsMultipleSelection(allowed, animated: animated)
    }
}

extension MediaGalleryFileCell: UIGestureRecognizerDelegate {

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return !allowsMultipleSelection
    }
}

extension MediaGalleryFileCell: CVComponentDelegate {

    var view: UIView! {
        return self
    }

    func enqueueReload() {}

    func enqueueReloadWithoutCaches() {}

    func didTapBodyTextItem(_ item: CVTextLabel.Item) {}

    func didLongPressBodyTextItem(_ item: CVTextLabel.Item) {}

    func didTapSystemMessageItem(_ item: CVTextLabel.Item) {}

    func didDoubleTapTextViewItem(_ itemViewModel: CVItemViewModelImpl) {}

    func didLongPressTextViewItem(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool) {}

    func didLongPressMediaViewItem(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool) {}

    func didLongPressQuote(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool) {}

    func didLongPressSystemMessage(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl) {}

    func didLongPressSticker(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool) {}

    func didLongPressPaymentMessage(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowReply: Bool
    ) {}

    func didTapPayment(_ payment: PaymentsHistoryItem) {}

    func didChangeLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    func didEndLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    func didCancelLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    // MARK: -

    func willBecomeVisibleWithFailedOrPendingDownloads(_ message: TSMessage) {}

    func didTapFailedOrPendingDownloads(_ message: TSMessage) {}

    func didCancelDownload(_ message: TSMessage, attachmentId: Attachment.IDType) {}

    // MARK: -

    func didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapSenderAvatar(_ interaction: TSInteraction) {}

    func shouldAllowReplyForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool { false }

    func didTapReactions(
        reactionState: InteractionReactionState,
        message: TSMessage) {}

    func didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapShowEditHistory(_ itemViewModel: CVItemViewModelImpl) {}

    var hasPendingMessageRequest: Bool { false }

    func didTapUndownloadableMedia() {}

    func didTapUndownloadableGenericFile() {}

    func didTapUndownloadableOversizeText() {}

    func didTapUndownloadableAudio() {}

    func didTapUndownloadableSticker() {}

    func didTapBrokenVideo() {}

    func didTapBodyMedia(
        itemViewModel: CVItemViewModelImpl,
        attachmentStream: ReferencedAttachmentStream,
        imageView: UIView
    ) {}

    func didTapGenericAttachment(
        _ attachment: CVComponentGenericAttachment
    ) -> CVAttachmentTapAction { .default }

    func didTapQuotedReply(_ quotedReply: QuotedReplyModel) {}

    func didTapLinkPreview(_ linkPreview: OWSLinkPreview) {}

    func didTapContactShare(_ contactShare: ContactShareViewModel) {}

    func didTapSendMessage(to phoneNumbers: [String]) {}

    func didTapSendInvite(toContactShare contactShare: ContactShareViewModel) {}

    func didTapAddToContacts(contactShare: ContactShareViewModel) {}

    func didTapStickerPack(_ stickerPackInfo: StickerPackInfo) {}

    func didTapGroupInviteLink(url: URL) {}

    func didTapProxyLink(url: URL) {}

    func didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl) {}

    func willWrapGift(_ messageUniqueId: String) -> Bool { false }

    func willShakeGift(_ messageUniqueId: String) -> Bool { false }

    func willUnwrapGift(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapGiftBadge(
        _ itemViewModel: CVItemViewModelImpl,
        profileBadge: ProfileBadge,
        isExpired: Bool,
        isRedeemed: Bool) {}

    func prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {}

    func beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation {
        return {}
    }

    var isConversationPreview: Bool { true }

    var wallpaperBlurProvider: WallpaperBlurProvider? { nil }

    public var selectionState: CVSelectionState { CVSelectionState() }

    func didTapPreviouslyVerifiedIdentityChange(_ address: SignalServiceAddress) {}

    func didTapUnverifiedIdentityChange(_ address: SignalServiceAddress) {}

    func didTapCorruptedMessage(_ message: TSErrorMessage) {}

    func didTapSessionRefreshMessage(_ message: TSErrorMessage) {}

    func didTapResendGroupUpdateForErrorMessage(_ errorMessage: TSErrorMessage) {}

    func didTapShowFingerprint(_ address: SignalServiceAddress) {}

    func didTapIndividualCall(_ call: TSCall) {}

    func didTapLearnMoreMissedCallFromBlockedContact(_ call: TSCall) {}

    func didTapGroupCall() {}

    func didTapPendingOutgoingMessage(_ message: TSOutgoingMessage) {}

    func didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {}

    func didTapGroupMigrationLearnMore() {}

    func didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) {}

    func didTapViewGroupDescription(newGroupDescription: String) {}

    func didTapNameEducation(type: SafetyTipsType) {}

    func didTapShowConversationSettings() {}

    func didTapShowConversationSettingsAndShowMemberRequests() {}

    func didTapBlockRequest(
        groupModel: TSGroupModelV2,
        requesterName: String,
        requesterAci: Aci) {}

    func didTapShowUpgradeAppUI() {}

    func didTapUpdateSystemContact(
        _ address: SignalServiceAddress,
        newNameComponents: PersonNameComponents) {}

    func didTapPhoneNumberChange(aci: Aci, phoneNumberOld: String, phoneNumberNew: String) {}

    func didTapViewOnceAttachment(_ interaction: TSInteraction) {}

    func didTapViewOnceExpired(_ interaction: TSInteraction) {}

    func didTapContactName(thread: TSContactThread) {}

    func didTapUnknownThreadWarningGroup() {}
    func didTapUnknownThreadWarningContact() {}
    func didTapDeliveryIssueWarning(_ message: TSErrorMessage) {}

    func didTapActivatePayments() {}
    func didTapSendPayment() {}

    func didTapThreadMergeLearnMore(phoneNumber: String) {}

    func didTapReportSpamLearnMore() {}

    func didTapMessageRequestAcceptedOptions() {}

    func didTapJoinCallLinkCall(callLink: CallLink) {}
}
