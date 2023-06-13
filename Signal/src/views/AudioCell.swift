//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

class AudioCell: MediaTileListModeCell, AudioMessageViewDelegate {
    static let reuseIdentifier = "AudioCell"
    private var audioItem: AudioItem?
    // TODO(george): Add support for dynamic size.
    override class var desiredHeight: CGFloat { 86.0 }
    private var tapGestureRecognizer: UITapGestureRecognizer!
    private var panGestureRecognizer: UIPanGestureRecognizer!
    private var itemModel: CVItemModel?
    private var audioAttachment: AudioAttachment?
    private var presentation: AudioAllMediaPresenter?
    private var conversationStyle: ConversationStyle?
    private var cellMeasurement: CVCellMeasurement?

    private func createAudioMessageView(audioItem: AudioItem?, spoilerReveal: SpoilerRevealState, transaction: SDSAnyReadTransaction) -> AudioMessageView? {
        guard let audioItem else {
            return nil
        }
        guard let attachment = AudioAttachment(attachment: audioItem.attachmentStream,
                                               owningMessage: audioItem.message,
                                               metadata: audioItem.metadata) else {
            return nil
        }
        self.audioAttachment = attachment

        guard let thread = TSThread.anyFetch(
            uniqueId: audioItem.interaction.uniqueThreadId,
            transaction: transaction
        ) else {
            owsFailDebug("Missing thread.")
            return nil
        }
        let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: thread,
                                                                       transaction: transaction)
        // Make an itemModel which is needed to play the audio file.
        // This is only used to save the playback rate, which is kind of nuts.
        let threadViewModel = ThreadViewModel(thread: audioItem.thread,
                                              forChatList: false,
                                              transaction: transaction)
        let conversationStyle = ConversationStyle(type: .default,
                                                  thread: audioItem.thread,
                                                  viewWidth: contentView.bounds.width,
                                                  hasWallpaper: false,
                                                  isWallpaperPhoto: false,
                                                  chatColor: ChatColor.placeholderValue)
        let coreState = CVCoreState(conversationStyle: conversationStyle,
                                    mediaCache: audioItem.mediaCache)
        let viewStateSnapshot = CVViewStateSnapshot.mockSnapshotForStandaloneItems(
            coreState: coreState, spoilerReveal: spoilerReveal)
        let itemBuildingContext = CVItemBuildingContextImpl(
            threadViewModel: threadViewModel,
            viewStateSnapshot: viewStateSnapshot,
            transaction: transaction,
            avatarBuilder: CVAvatarBuilder(transaction: transaction))
        guard let componentState = try? CVComponentState.build(interaction: audioItem.interaction,
                                                               itemBuildingContext: itemBuildingContext) else {
            return nil
        }
        itemModel = CVItemModel(interaction: audioItem.interaction,
                                thread: audioItem.thread,
                                threadAssociatedData: threadAssociatedData,
                                componentState: componentState,
                                itemViewState: CVItemViewState.Builder().build(),
                                coreState: coreState)
        guard let itemModel else {
            return nil
        }
        let presentation = AudioAllMediaPresenter(
            sender: audioItem.metadata.abbreviatedSender,
            audioAttachment: attachment,
            threadUniqueId: audioItem.message.thread(transaction: transaction).uniqueId,
            playbackRate: AudioPlaybackRate(rawValue: itemModel.itemViewState.audioPlaybackRate),
            isIncoming: audioItem.interaction is TSIncomingMessage)
        let view = AudioMessageView(
            presentation: presentation,
            audioMessageViewDelegate: self,
            mediaCache: audioItem.mediaCache)
        if let incomingMessage = audioItem.interaction as? TSIncomingMessage {
            view.setViewed(incomingMessage.wasViewed, animated: false)
        } else if let outgoingMessage = audioItem.interaction as? TSOutgoingMessage {
            view.setViewed(!outgoingMessage.viewedRecipientAddresses().isEmpty, animated: false)
        }

        self.presentation = presentation
        self.conversationStyle = conversationStyle
        let measurementBuilder = CVCellMeasurement.Builder()
        measurementBuilder.cellSize = AudioMessageView.measure(maxWidth: contentView.bounds.width - leadingMargin - trailingMargin,
                                                               sender: audioItem.metadata.abbreviatedSender,
                                                               conversationStyle: conversationStyle,
                                                               measurementBuilder: measurementBuilder,
                                                               presentation: presentation)
        cellMeasurement = measurementBuilder.build()
        view.translatesAutoresizingMaskIntoConstraints = false
        configureAudioMessageView(view)
        return view
    }

    private func configureAudioMessageView(_ view: AudioMessageView) {
        guard let conversationStyle, let cellMeasurement else {
            return
        }
        view.configureForRendering(cellMeasurement: cellMeasurement,
                                   conversationStyle: conversationStyle)
    }

    class AudioMessageContainerView: UIView {}
    private let audioMessageContainerView: AudioMessageContainerView = {
        let view = AudioMessageContainerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private static var textColor: UIColor {
        if #available(iOS 13, *) {
            return .secondaryLabel
        } else {
            return .ows_gray45
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let leadingMargin = 16.0
    private let trailingMargin = 14.0

    static func sizeForItem(_ item: AllMediaItem,
                            defaultSize: CGSize) -> CGSize {
        switch item {
        case .graphic:
            return defaultSize
        case .audio(let audioItem):
            if AudioAllMediaPresenter.hasAttachmentLabel(attachment: audioItem.attachmentStream) {
                var result = defaultSize
                result.height += 17
                return result
            }
            return defaultSize
        }
    }
    private func setupViews() {
        willSetupViews()

        contentView.addSubview(audioMessageContainerView)
        contentView.layer.cornerRadius = 10.0
        NSLayoutConstraint.activate([
            audioMessageContainerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            audioMessageContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            audioMessageContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -trailingMargin)
        ])

        let constraintWithSelectionButton = audioMessageContainerView.leadingAnchor.constraint(
            equalTo: selectionButton.trailingAnchor,
            constant: 13)
        let constraintWithoutSelectionButton = audioMessageContainerView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: leadingMargin)

        tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(cellTapped(_:)))
        addGestureRecognizer(tapGestureRecognizer)

        panGestureRecognizer = UIPanGestureRecognizer(
            target: self,
            action: #selector(pan(_:)))
        panGestureRecognizer.require(toFail: tapGestureRecognizer)
        addGestureRecognizer(panGestureRecognizer)
        super.setupViews(constraintWithSelectionButton: constraintWithSelectionButton,
                         constraintWithoutSelectionButton: constraintWithoutSelectionButton)
    }

    @objc
    func pan(_ sender: UIPanGestureRecognizer) {
        guard let audioMessageView, let audioItem else {
            return
        }
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
    func cellTapped(_ sender: UITapGestureRecognizer) {
        // TODO: When adding support for undownloaded attachments, tapping should cancel or retry downloading.
        // See the logic in CVComponentAudioAttachment.handleTap(sender:,componentDelegate:,componentView:,renderItem:)
        guard let itemModel, let audioMessageView, let audioItem, let audioAttachment else {
            return
        }
        if audioMessageView.handleTap(sender: sender, itemModel: itemModel) {
            return
        }
        let cvAudioPlayer = AppEnvironment.shared.cvAudioPlayerRef
        cvAudioPlayer.setPlaybackRate(
            itemModel.itemViewState.audioPlaybackRate,
            forThreadUniqueId: audioItem.thread.uniqueId)
        cvAudioPlayer.togglePlayState(forAudioAttachment: audioAttachment)
    }

    private func setUpAccessibility(item: AudioItem?) {
        self.isAccessibilityElement = true

        if let audioItem {
            self.accessibilityLabel = [
                audioItem.localizedString,
                MediaTileDateFormatter.formattedDateString(for: audioItem.date)
            ]
                .compactMap { $0 }
                .joined(separator: ", ")
        } else {
            self.accessibilityLabel = ""
        }
    }

    private var audioMessageView: AudioMessageView?

    override var cellsAbut: Bool { false }
    private var allMediaItem: AllMediaItem?
    private var spoilerReveal: SpoilerRevealState?

    override func configure(item: AllMediaItem,
                            spoilerReveal: SpoilerRevealState) {
        super.configure(item: item, spoilerReveal: spoilerReveal)
        guard case let .audio(audioItem) = item else {
            owsFailDebug("Unexpected item type")
            return
        }
        self.audioItem = audioItem
        self.allMediaItem = item
        self.spoilerReveal = spoilerReveal
        audioMessageContainerView.subviews.first?.removeFromSuperview()

        SDSDatabaseStorage.shared.read { transaction in
            if let audioMessageView = createAudioMessageView(audioItem: audioItem, spoilerReveal: spoilerReveal, transaction: transaction) {
                audioMessageContainerView.addSubview(audioMessageView)
                self.audioMessageView = audioMessageView
                audioMessageView.autoPinEdgesToSuperviewEdges()
            }
        }
    }

    override public func makePlaceholder() {
        audioMessageView?.removeFromSuperview()
        audioMessageView = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if let allMediaItem, let spoilerReveal {
            configure(item: allMediaItem, spoilerReveal: spoilerReveal)
        }
    }

    override func setAllowsMultipleSelection(_ allowed: Bool, animated: Bool) {
        tapGestureRecognizer.isEnabled = !allowed
        super.setAllowsMultipleSelection(allowed, animated: animated)
    }

    // MARK: - AudioMessageViewDelegate

    func beginCellAnimation(maximumDuration: TimeInterval) -> (() -> Void) {
        return {}
    }

    func enqueueReloadWithoutCaches() {
        if let allMediaItem, let spoilerReveal {
            configure(item: allMediaItem, spoilerReveal: spoilerReveal)
        }
    }

}
