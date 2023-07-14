//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

class AudioCell: MediaTileListModeCell {

    static let reuseIdentifier = "AudioCell"

    private var audioAttachment: AudioAttachment?

    private var audioItem: MediaGalleryCellItemAudio? {
        didSet {
            guard let audioItem else {
                audioAttachment = nil
                return
            }
            audioAttachment = AudioAttachment(
                attachment: audioItem.attachmentStream,
                owningMessage: audioItem.message,
                metadata: audioItem.metadata
            )
        }
    }

    class var defaultCellHeight: CGFloat { 88 }

    private static let contentInset = UIEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 10)

    private static var cellHeightsWithTopLabel: [UIContentSizeCategory: CGFloat] = [:]

    private static var cellHeightsWithoutTopLabel: [UIContentSizeCategory: CGFloat] = [:]

    class func cellHeight(for item: MediaGalleryCellItem, maxWidth: CGFloat) -> CGFloat {
        guard case let .audio(audioItem) = item else {
            owsFailDebug("Unexpected item type")
            return defaultCellHeight
        }

        let currentContentSizeCategory = UITraitCollection.current.preferredContentSizeCategory
        let displaysTopLabel = AudioAllMediaPresenter.hasAttachmentLabel(attachment: audioItem.attachmentStream)

        if let cellHeight: CGFloat = {
            if displaysTopLabel {
                return cellHeightsWithTopLabel[currentContentSizeCategory]
            } else {
                return cellHeightsWithoutTopLabel[currentContentSizeCategory]
            }
        }() {
            return cellHeight
        }

        guard let audioAttachment = AudioAttachment(
            attachment: audioItem.attachmentStream,
            owningMessage: audioItem.message,
            metadata: audioItem.metadata
        ) else {
            return defaultCellHeight
        }
        let presenter = AudioAllMediaPresenter(
            sender: "",
            audioAttachment: audioAttachment,
            threadUniqueId: audioItem.thread.uniqueId,
            playbackRate: .normal
        )
        let audioMessageViewSize = AudioMessageView.measure(
            maxWidth: maxWidth,
            measurementBuilder: CVCellMeasurement.Builder(),
            presentation: presenter
        )

        let cellHeight = audioMessageViewSize.height + AudioCell.contentInset.totalHeight
        if displaysTopLabel {
            cellHeightsWithTopLabel[currentContentSizeCategory] = cellHeight
        } else {
            cellHeightsWithoutTopLabel[currentContentSizeCategory] = cellHeight
        }

        return cellHeight
    }

    private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    private lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        let gestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    private var itemModel: CVItemModel?

    private var audioMessageView: AudioMessageView?

    private let audioMessageContainerView: UIView = {
        let view = UIView.container()
        view.backgroundColor = UIColor(dynamicProvider: { _ in Theme.tableCell2PresentedBackgroundColor })
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        return view
    }()

    private func createAudioMessageView(transaction: SDSAnyReadTransaction) {
        owsAssertDebug(audioMessageView == nil)

        guard let audioItem, let audioAttachment, let spoilerState else {
            owsFailDebug("audioItem or spoilerReveal not set")
            return
        }

        let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: audioItem.thread, transaction: transaction)
        // Make an itemModel which is needed to play the audio file.
        // This is only used to save the playback rate, which is kind of nuts.
        let threadViewModel = ThreadViewModel(
            thread: audioItem.thread,
            forChatList: false,
            transaction: transaction
        )
        let conversationStyle = ConversationStyle(
            type: .default,
            thread: audioItem.thread,
            viewWidth: contentView.bounds.width,
            hasWallpaper: false,
            isWallpaperPhoto: false,
            chatColor: ChatColors.Constants.defaultColor.colorSetting
        )
        let coreState = CVCoreState(conversationStyle: conversationStyle, mediaCache: audioItem.mediaCache)
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
            interaction: audioItem.interaction,
            itemBuildingContext: itemBuildingContext
        ) else {
            return
        }
        let itemViewState = CVItemViewState.Builder()
        itemViewState.audioPlaybackRate = threadAssociatedData.audioPlaybackRate
        let itemModel = CVItemModel(
            interaction: audioItem.interaction,
            thread: audioItem.thread,
            threadAssociatedData: threadAssociatedData,
            componentState: componentState,
            itemViewState: itemViewState.build(),
            coreState: coreState
        )
        let presentation = AudioAllMediaPresenter(
            sender: audioItem.metadata.abbreviatedSender,
            audioAttachment: audioAttachment,
            threadUniqueId: audioItem.thread.uniqueId,
            playbackRate: AudioPlaybackRate(rawValue: itemModel.itemViewState.audioPlaybackRate)
        )
        let view = AudioMessageView(
            presentation: presentation,
            audioMessageViewDelegate: self,
            mediaCache: audioItem.mediaCache
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        if let incomingMessage = audioItem.interaction as? TSIncomingMessage {
            view.setViewed(incomingMessage.wasViewed, animated: false)
        } else if let outgoingMessage = audioItem.interaction as? TSOutgoingMessage {
            view.setViewed(!outgoingMessage.viewedRecipientAddresses().isEmpty, animated: false)
        }

        let measurementBuilder = CVCellMeasurement.Builder()
        measurementBuilder.cellSize = AudioMessageView.measure(
            maxWidth: contentView.bounds.width, // actual max width doesn't matter because there's no multiline text
            measurementBuilder: measurementBuilder,
            presentation: presentation
        )
        let cellMeasurement = measurementBuilder.build()
        view.configureForRendering(cellMeasurement: cellMeasurement, conversationStyle: conversationStyle)
        audioMessageContainerView.addSubview(view)
        view.autoPinEdgesToSuperviewEdges(with: AudioCell.contentInset)

        self.itemModel = itemModel
        self.audioMessageView = view
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.addSubview(audioMessageContainerView)
        NSLayoutConstraint.activate([
            audioMessageContainerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            audioMessageContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            audioMessageContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -OWSTableViewController2.defaultHOuterMargin)
        ])

        let constraintWithSelectionButton = audioMessageContainerView.leadingAnchor.constraint(
            equalTo: selectionButton.trailingAnchor,
            constant: 12
        )
        let constraintWithoutSelectionButton = audioMessageContainerView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: OWSTableViewController2.defaultHOuterMargin
        )

        addGestureRecognizer(tapGestureRecognizer)
        addGestureRecognizer(panGestureRecognizer)
        tapGestureRecognizer.require(toFail: panGestureRecognizer)

        super.setupViews(constraintWithSelectionButton: constraintWithSelectionButton,
                         constraintWithoutSelectionButton: constraintWithoutSelectionButton)
    }

    @objc
    private func handlePanGesture(_ sender: UIPanGestureRecognizer) {
        guard let audioMessageView, let audioItem else { return }

        let location = panGestureRecognizer.location(in: audioMessageView)
        switch panGestureRecognizer.state {
        case .began:
            if !audioMessageView.isPointInScrubbableRegion(location) {
                panGestureRecognizer.isEnabled = false
                panGestureRecognizer.isEnabled = true
            }
        case .changed:
            let progress = audioMessageView.progressForLocation(location)
            audioMessageView.setOverrideProgress(progress, animated: false)
        case .ended:
            audioMessageView.clearOverrideProgress(animated: false)
            let scrubbedTime = audioMessageView.scrubToLocation(location)
            let cvAudioPlayer = AppEnvironment.shared.cvAudioPlayerRef
            cvAudioPlayer.setPlaybackProgress(
                progress: scrubbedTime,
                forAttachmentStream: audioItem.attachmentStream)
        case .possible, .failed, .cancelled:
            audioMessageView.clearOverrideProgress(animated: false)
        @unknown default:
            owsFailDebug("Invalid state.")
            audioMessageView.clearOverrideProgress(animated: false)
        }
    }

    @objc
    private func handleTapGesture(_ sender: UITapGestureRecognizer) {
        // TODO: When adding support for undownloaded attachments, tapping should cancel or retry downloading.
        // See the logic in CVComponentAudioAttachment.handleTap(sender:,componentDelegate:,componentView:,renderItem:)
        guard let itemModel, let audioMessageView, let audioItem, let audioAttachment else {
            return
        }
        if audioMessageView.handleTap(sender: sender, itemModel: itemModel) {
            return
        }
        let cvAudioPlayer = AppEnvironment.shared.cvAudioPlayerRef
        cvAudioPlayer.setPlaybackRate(itemModel.itemViewState.audioPlaybackRate, forThreadUniqueId: audioItem.thread.uniqueId)
        cvAudioPlayer.togglePlayState(forAudioAttachment: audioAttachment)
    }

    private func setUpAccessibility(item: MediaGalleryCellItemAudio?) {
        isAccessibilityElement = true

        if let audioItem {
            accessibilityLabel = [
                audioItem.localizedString,
                MediaTileDateFormatter.formattedDateString(for: audioItem.date)
            ]
                .compactMap { $0 }
                .joined(separator: ", ")
        } else {
            accessibilityLabel = ""
        }
    }

    override var cellsAbut: Bool { false }

    private var spoilerState: SpoilerRenderState?

    override func configure(item: MediaGalleryCellItem, spoilerState: SpoilerRenderState) {
        super.configure(item: item, spoilerState: spoilerState)

        guard case let .audio(audioItem) = item else {
            owsFailDebug("Unexpected item type")
            return
        }
        self.audioItem = audioItem
        self.spoilerState = spoilerState

        if let audioMessageView {
            audioMessageView.removeFromSuperview()
            self.audioMessageView = nil
        }

        databaseStorage.read { transaction in
            createAudioMessageView(transaction: transaction)
        }
    }

    override func makePlaceholder() {
        audioMessageView?.removeFromSuperview()
        audioMessageView = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if let item, let spoilerState {
            configure(item: item, spoilerState: spoilerState)
        }
    }

    override func setAllowsMultipleSelection(_ allowed: Bool, animated: Bool) {
        tapGestureRecognizer.isEnabled = !allowed
        super.setAllowsMultipleSelection(allowed, animated: animated)
    }
}

extension AudioCell: UIGestureRecognizerDelegate {

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !allowsMultipleSelection else {
            return false
        }

        if gestureRecognizer == panGestureRecognizer {
            // Only allow the pan gesture to recognize horizontal panning,
            // to avoid conflicts with the collection view scroll gesture.
            let translation = panGestureRecognizer.translation(in: self)
            return abs(translation.x) > abs(translation.y)
        }

        return true
    }
}

extension AudioCell: AudioMessageViewDelegate {

    func beginCellAnimation(maximumDuration: TimeInterval) -> (() -> Void) {
        return {}
    }

    func enqueueReloadWithoutCaches() {
        if let item, let spoilerState {
            configure(item: item, spoilerState: spoilerState)
        }
    }
}
