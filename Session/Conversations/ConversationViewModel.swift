// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SessionMessagingKit
import SessionUtilitiesKit

public class ConversationViewModel: OWSAudioPlayerDelegate {
    public typealias SectionModel = ArraySection<Section, MessageViewModel>
    
    // MARK: - Action
    
    public enum Action {
        case none
        case compose
        case audioCall
        case videoCall
    }
    
    // MARK: - Section
    
    public enum Section: Differentiable, Equatable, Comparable, Hashable {
        case loadOlder
        case messages
        case loadNewer
    }
    
    // MARK: - Variables
    
    public static let pageSize: Int = 50
    
    private var threadId: String
    public let initialThreadVariant: SessionThread.Variant
    public var sentMessageBeforeUpdate: Bool = false
    public var lastSearchedText: String?
    public let focusedInteractionId: Int64?    // Note: This is used for global search
    
    public lazy var blockedBannerMessage: String = {
        switch self.threadData.threadVariant {
            case .contact:
                let name: String = Profile.displayName(
                    id: self.threadData.threadId,
                    threadVariant: self.threadData.threadVariant
                )
                
                return "\(name) is blocked. Unblock them?"
                
            default: return "Thread is blocked. Unblock it?"
        }
    }()
    
    // MARK: - Initialization
    
    init(threadId: String, threadVariant: SessionThread.Variant, focusedInteractionId: Int64?) {
        // If we have a specified 'focusedInteractionId' then use that, otherwise retrieve the oldest
        // unread interaction and start focused around that one
        let targetInteractionId: Int64? = {
            if let focusedInteractionId: Int64 = focusedInteractionId { return focusedInteractionId }
            
            return Storage.shared.read { db in
                let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                
                return try Interaction
                    .select(.id)
                    .filter(interaction[.wasRead] == false)
                    .filter(interaction[.threadId] == threadId)
                    .order(interaction[.timestampMs].asc)
                    .asRequest(of: Int64.self)
                    .fetchOne(db)
            }
        }()
        
        self.threadId = threadId
        self.initialThreadVariant = threadVariant
        self.focusedInteractionId = targetInteractionId
        self.pagedDataObserver = nil
        
        // Note: Since this references self we need to finish initializing before setting it, we
        // also want to skip the initial query and trigger it async so that the push animation
        // doesn't stutter (it should load basically immediately but without this there is a
        // distinct stutter)
        self.pagedDataObserver = self.setupPagedObserver(
            for: threadId,
            userPublicKey: getUserHexEncodedPublicKey()
        )
        
        // Run the initial query on a background thread so we don't block the push transition
        DispatchQueue.global(qos: .default).async { [weak self] in
            // If we don't have a `initialFocusedId` then default to `.pageBefore` (it'll query
            // from a `0` offset)
            guard let initialFocusedId: Int64 = targetInteractionId else {
                self?.pagedDataObserver?.load(.pageBefore)
                return
            }
            
            self?.pagedDataObserver?.load(.initialPageAround(id: initialFocusedId))
        }
    }
    
    // MARK: - Thread Data
    
    /// This value is the current state of the view
    public private(set) lazy var threadData: SessionThreadViewModel = SessionThreadViewModel(
        threadId: self.threadId,
        threadVariant: self.initialThreadVariant,
        currentUserIsClosedGroupMember: (self.initialThreadVariant != .closedGroup ?
            nil :
            Storage.shared.read { db in
                try GroupMember
                    .filter(GroupMember.Columns.groupId == self.threadId)
                    .filter(GroupMember.Columns.profileId == getUserHexEncodedPublicKey(db))
                    .filter(GroupMember.Columns.role == GroupMember.Role.standard)
                    .isNotEmpty(db)
            }
        )
    )
    
    /// This is all the data the screen needs to populate itself, please see the following link for tips to help optimise
    /// performance https://github.com/groue/GRDB.swift#valueobservation-performance
    ///
    /// **Note:** The 'trackingConstantRegion' is optimised in such a way that the request needs to be static
    /// otherwise there may be situations where it doesn't get updates, this means we can't have conditional queries
    ///
    /// **Note:** This observation will be triggered twice immediately (and be de-duped by the `removeDuplicates`)
    /// this is due to the behaviour of `ValueConcurrentObserver.asyncStartObservation` which triggers it's own
    /// fetch (after the ones in `ValueConcurrentObserver.asyncStart`/`ValueConcurrentObserver.syncStart`)
    /// just in case the database has changed between the two reads - unfortunately it doesn't look like there is a way to prevent this
    public lazy var observableThreadData: ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Fetch<SessionThreadViewModel?>>> = setupObservableThreadData(for: self.threadId)
    
    private func setupObservableThreadData(for threadId: String) -> ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Fetch<SessionThreadViewModel?>>> {
        return ValueObservation
            .trackingConstantRegion { db -> SessionThreadViewModel? in
                let userPublicKey: String = getUserHexEncodedPublicKey(db)
                let recentReactionEmoji: [String] = try Emoji.getRecent(db, withDefaultEmoji: true)
                let threadViewModel: SessionThreadViewModel? = try SessionThreadViewModel
                    .conversationQuery(threadId: threadId, userPublicKey: userPublicKey)
                    .fetchOne(db)
                
                return threadViewModel
                    .map { $0.with(recentReactionEmoji: recentReactionEmoji) }
            }
            .removeDuplicates()
    }

    public func updateThreadData(_ updatedData: SessionThreadViewModel) {
        self.threadData = updatedData
    }
    
    // MARK: - Interaction Data
    
    private var lastInteractionIdMarkedAsRead: Int64?
    public private(set) var unobservedInteractionDataChanges: [SectionModel]?
    public private(set) var interactionData: [SectionModel] = []
    public private(set) var reactionExpandedInteractionIds: Set<Int64> = []
    public private(set) var pagedDataObserver: PagedDatabaseObserver<Interaction, MessageViewModel>?
    
    public var onInteractionChange: (([SectionModel]) -> ())? {
        didSet {
            // When starting to observe interaction changes we want to trigger a UI update just in case the
            // data was changed while we weren't observing
            if let unobservedInteractionDataChanges: [SectionModel] = self.unobservedInteractionDataChanges {
                onInteractionChange?(unobservedInteractionDataChanges)
                self.unobservedInteractionDataChanges = nil
            }
        }
    }
    
    private func setupPagedObserver(for threadId: String, userPublicKey: String) -> PagedDatabaseObserver<Interaction, MessageViewModel> {
        return PagedDatabaseObserver(
            pagedTable: Interaction.self,
            pageSize: ConversationViewModel.pageSize,
            idColumn: .id,
            observedChanges: [
                PagedData.ObservedChanges(
                    table: Interaction.self,
                    columns: Interaction.Columns
                        .allCases
                        .filter { $0 != .wasRead }
                ),
                PagedData.ObservedChanges(
                    table: Contact.self,
                    columns: [.isTrusted],
                    joinToPagedType: {
                        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                        let contact: TypedTableAlias<Contact> = TypedTableAlias()
                        
                        return SQL("LEFT JOIN \(Contact.self) ON \(contact[.id]) = \(interaction[.threadId])")
                    }()
                ),
                PagedData.ObservedChanges(
                    table: Profile.self,
                    columns: [.profilePictureFileName],
                    joinToPagedType: {
                        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                        let profile: TypedTableAlias<Profile> = TypedTableAlias()
                        
                        return SQL("LEFT JOIN \(Profile.self) ON \(profile[.id]) = \(interaction[.authorId])")
                    }()
                )
            ],
            joinSQL: MessageViewModel.optimisedJoinSQL,
            filterSQL: MessageViewModel.filterSQL(threadId: threadId),
            groupSQL: MessageViewModel.groupSQL,
            orderSQL: MessageViewModel.orderSQL,
            dataQuery: MessageViewModel.baseQuery(
                userPublicKey: userPublicKey,
                orderSQL: MessageViewModel.orderSQL,
                groupSQL: MessageViewModel.groupSQL
            ),
            associatedRecords: [
                AssociatedRecord<MessageViewModel.AttachmentInteractionInfo, MessageViewModel>(
                    trackedAgainst: Attachment.self,
                    observedChanges: [
                        PagedData.ObservedChanges(
                            table: Attachment.self,
                            columns: [.state]
                        )
                    ],
                    dataQuery: MessageViewModel.AttachmentInteractionInfo.baseQuery,
                    joinToPagedType: MessageViewModel.AttachmentInteractionInfo.joinToViewModelQuerySQL,
                    associateData: MessageViewModel.AttachmentInteractionInfo.createAssociateDataClosure()
                ),
                AssociatedRecord<MessageViewModel.ReactionInfo, MessageViewModel>(
                    trackedAgainst: Reaction.self,
                    observedChanges: [
                        PagedData.ObservedChanges(
                            table: Reaction.self,
                            columns: [.count]
                        )
                    ],
                    dataQuery: MessageViewModel.ReactionInfo.baseQuery,
                    joinToPagedType: MessageViewModel.ReactionInfo.joinToViewModelQuerySQL,
                    associateData: MessageViewModel.ReactionInfo.createAssociateDataClosure()
                ),
                AssociatedRecord<MessageViewModel.TypingIndicatorInfo, MessageViewModel>(
                    trackedAgainst: ThreadTypingIndicator.self,
                    observedChanges: [
                        PagedData.ObservedChanges(
                            table: ThreadTypingIndicator.self,
                            events: [.insert, .delete],
                            columns: []
                        )
                    ],
                    dataQuery: MessageViewModel.TypingIndicatorInfo.baseQuery,
                    joinToPagedType: MessageViewModel.TypingIndicatorInfo.joinToViewModelQuerySQL,
                    associateData: MessageViewModel.TypingIndicatorInfo.createAssociateDataClosure()
                )
            ],
            onChangeUnsorted: { [weak self] updatedData, updatedPageInfo in
                guard let updatedInteractionData: [SectionModel] = self?.process(data: updatedData, for: updatedPageInfo) else {
                    return
                }
                
                // If we have the 'onInteractionChanged' callback then trigger it, otherwise just store the changes
                // to be sent to the callback if we ever start observing again (when we have the callback it needs
                // to do the data updating as it's tied to UI updates and can cause crashes if not updated in the
                // correct order)
                guard let onInteractionChange: (([SectionModel]) -> ()) = self?.onInteractionChange else {
                    self?.unobservedInteractionDataChanges = updatedInteractionData
                    return
                }

                onInteractionChange(updatedInteractionData)
            }
        )
    }
    
    private func process(data: [MessageViewModel], for pageInfo: PagedData.PageInfo) -> [SectionModel] {
        let typingIndicator: MessageViewModel? = data.first(where: { $0.isTypingIndicator == true })
        let sortedData: [MessageViewModel] = data
            .filter { $0.isTypingIndicator != true }
            .sorted { lhs, rhs -> Bool in lhs.timestampMs < rhs.timestampMs }
        
        // We load messages from newest to oldest so having a pageOffset larger than zero means
        // there are newer pages to load
        return [
            (!data.isEmpty && (pageInfo.pageOffset + pageInfo.currentCount) < pageInfo.totalCount ?
                [SectionModel(section: .loadOlder)] :
                []
            ),
            [
                SectionModel(
                    section: .messages,
                    elements: sortedData
                        .enumerated()
                        .map { index, cellViewModel -> MessageViewModel in
                            cellViewModel.withClusteringChanges(
                                prevModel: (index > 0 ? sortedData[index - 1] : nil),
                                nextModel: (index < (sortedData.count - 1) ? sortedData[index + 1] : nil),
                                isLast: (
                                    // The database query sorts by timestampMs descending so the "last"
                                    // interaction will actually have a 'pageOffset' of '0' even though
                                    // it's the last element in the 'sortedData' array
                                    index == (sortedData.count - 1) &&
                                    pageInfo.pageOffset == 0
                                ),
                                currentUserBlindedPublicKey: threadData.currentUserBlindedPublicKey
                            )
                        }
                        .reduce([]) { result, message in
                            guard message.shouldShowDateHeader else {
                                return result.appending(message)
                            }
                            
                            return result
                                .appending(
                                    MessageViewModel(
                                        timestampMs: message.timestampMs,
                                        cellType: .dateHeader
                                    )
                                )
                                .appending(message)
                        }
                        .appending(typingIndicator)
                )
            ],
            (!data.isEmpty && pageInfo.pageOffset > 0 ?
                [SectionModel(section: .loadNewer)] :
                []
            )
        ].flatMap { $0 }
    }
    
    public func updateInteractionData(_ updatedData: [SectionModel]) {
        self.interactionData = updatedData
    }
    
    public func expandReactions(for interactionId: Int64) {
        reactionExpandedInteractionIds.insert(interactionId)
    }
    
    public func collapseReactions(for interactionId: Int64) {
        reactionExpandedInteractionIds.remove(interactionId)
    }
    
    // MARK: - Mentions
    
    public func mentions(for query: String = "") -> [MentionInfo] {
        let threadData: SessionThreadViewModel = self.threadData
        
        return Storage.shared
            .read { db -> [MentionInfo] in
                let userPublicKey: String = getUserHexEncodedPublicKey(db)
                let pattern: FTS5Pattern? = try? SessionThreadViewModel.pattern(db, searchTerm: query, forTable: Profile.self)
                let capabilities: Set<Capability.Variant> = (threadData.threadVariant != .openGroup ?
                    nil :
                    try? Capability
                        .select(.variant)
                        .filter(Capability.Columns.openGroupServer == threadData.openGroupServer)
                        .asRequest(of: Capability.Variant.self)
                        .fetchSet(db)
                )
                .defaulting(to: [])
                let targetPrefix: SessionId.Prefix = (capabilities.contains(.blind) ?
                    .blinded :
                    .standard
                )
                
                return (try MentionInfo
                    .query(
                        userPublicKey: userPublicKey,
                        threadId: threadData.threadId,
                        threadVariant: threadData.threadVariant,
                        targetPrefix: targetPrefix,
                        pattern: pattern
                    )?
                    .fetchAll(db))
                    .defaulting(to: [])
            }
            .defaulting(to: [])
    }
    
    // MARK: - Functions
    
    public func updateDraft(to draft: String) {
        let threadId: String = self.threadId
        let currentDraft: String = Storage.shared
            .read { db in
                try SessionThread
                    .select(.messageDraft)
                    .filter(id: threadId)
                    .asRequest(of: String.self)
                    .fetchOne(db)
            }
            .defaulting(to: "")
        
        // Only write the updated draft to the database if it's changed (avoid unnecessary writes)
        guard draft != currentDraft else { return }
        
        Storage.shared.writeAsync { db in
            try SessionThread
                .filter(id: threadId)
                .updateAll(db, SessionThread.Columns.messageDraft.set(to: draft))
        }
    }
    
    /// This method will mark all interactions as read before the specified interaction id, if no id is provided then all interactions for
    /// the thread will be marked as read
    public func markAsRead(beforeInclusive interactionId: Int64?) {
        /// Since this method now gets triggered when scrolling we want to try to optimise it and avoid busying the database
        /// write queue when it isn't needed, in order to do this we:
        ///
        ///   - Don't bother marking anything as read if there are no unread interactions (we can rely on the
        ///     `threadData.threadUnreadCount` to always be accurate)
        ///   - Don't bother marking anything as read if this was called with the same `interactionId` that we
        ///     previously marked as read (ie. when scrolling and the last message hasn't changed)
        guard
            (self.threadData.threadUnreadCount ?? 0) > 0,
            let targetInteractionId: Int64 = (interactionId ?? self.threadData.interactionId),
            self.lastInteractionIdMarkedAsRead != targetInteractionId
        else { return }
        
        let threadId: String = self.threadData.threadId
        let trySendReadReceipt: Bool = (self.threadData.threadIsMessageRequest == false)
        self.lastInteractionIdMarkedAsRead = targetInteractionId
        
        Storage.shared.writeAsync { db in
            try Interaction.markAsRead(
                db,
                interactionId: targetInteractionId,
                threadId: threadId,
                includingOlder: true,
                trySendReadReceipt: trySendReadReceipt
            )
        }
    }
    
    public func swapToThread(updatedThreadId: String) {
        let oldestMessageId: Int64? = self.interactionData
            .filter { $0.model == .messages }
            .first?
            .elements
            .first?
            .id
        
        self.threadId = updatedThreadId
        self.observableThreadData = self.setupObservableThreadData(for: updatedThreadId)
        self.pagedDataObserver = self.setupPagedObserver(
            for: updatedThreadId,
            userPublicKey: getUserHexEncodedPublicKey()
        )
        
        // Try load everything up to the initial visible message, fallback to just the initial page of messages
        // if we don't have one
        switch oldestMessageId {
            case .some(let id): self.pagedDataObserver?.load(.untilInclusive(id: id, padding: 0))
            case .none: self.pagedDataObserver?.load(.pageBefore)
        }
    }
    
    public func trustContact() {
        guard self.threadData.threadVariant == .contact else { return }
        
        let threadId: String = self.threadId
        
        Storage.shared.writeAsync { db in
            try Contact
                .filter(id: threadId)
                .updateAll(db, Contact.Columns.isTrusted.set(to: true))
            
            // Start downloading any pending attachments for this contact (UI will automatically be
            // updated due to the database observation)
            try Attachment
                .stateInfo(authorId: threadId, state: .pendingDownload)
                .fetchAll(db)
                .forEach { attachmentDownloadInfo in
                    JobRunner.add(
                        db,
                        job: Job(
                            variant: .attachmentDownload,
                            threadId: threadId,
                            interactionId: attachmentDownloadInfo.interactionId,
                            details: AttachmentDownloadJob.Details(
                                attachmentId: attachmentDownloadInfo.attachmentId
                            )
                        )
                    )
                }
        }
    }
    
    public func unblockContact() {
        guard self.threadData.threadVariant == .contact else { return }
        
        let threadId: String = self.threadId
        
        Storage.shared.writeAsync { db in
            try Contact
                .filter(id: threadId)
                .updateAll(db, Contact.Columns.isBlocked.set(to: false))
        
            try MessageSender
                .syncConfiguration(db, forceSyncNow: true)
                .retainUntilComplete()
        }
    }
    
    // MARK: - Audio Playback
    
    public struct PlaybackInfo {
        let state: AudioPlaybackState
        let progress: TimeInterval
        let playbackRate: Double
        let oldPlaybackRate: Double
        let updateCallback: (PlaybackInfo?, Error?) -> ()
        
        public func with(
            state: AudioPlaybackState? = nil,
            progress: TimeInterval? = nil,
            playbackRate: Double? = nil,
            updateCallback: ((PlaybackInfo?, Error?) -> ())? = nil
        ) -> PlaybackInfo {
            return PlaybackInfo(
                state: (state ?? self.state),
                progress: (progress ?? self.progress),
                playbackRate: (playbackRate ?? self.playbackRate),
                oldPlaybackRate: self.playbackRate,
                updateCallback: (updateCallback ?? self.updateCallback)
            )
        }
    }
    
    private var audioPlayer: Atomic<OWSAudioPlayer?> = Atomic(nil)
    private var currentPlayingInteraction: Atomic<Int64?> = Atomic(nil)
    private var playbackInfo: Atomic<[Int64: PlaybackInfo]> = Atomic([:])
    
    public func playbackInfo(for viewModel: MessageViewModel, updateCallback: ((PlaybackInfo?, Error?) -> ())? = nil) -> PlaybackInfo? {
        // Use the existing info if it already exists (update it's callback if provided as that means
        // the cell was reloaded)
        if let currentPlaybackInfo: PlaybackInfo = playbackInfo.wrappedValue[viewModel.id] {
            let updatedPlaybackInfo: PlaybackInfo = currentPlaybackInfo
                .with(updateCallback: updateCallback)
            
            playbackInfo.mutate { $0[viewModel.id] = updatedPlaybackInfo }
            
            return updatedPlaybackInfo
        }
        
        // Validate the item is a valid audio item
        guard
            let updateCallback: ((PlaybackInfo?, Error?) -> ()) = updateCallback,
            let attachment: Attachment = viewModel.attachments?.first,
            attachment.isAudio,
            attachment.isValid,
            let originalFilePath: String = attachment.originalFilePath,
            FileManager.default.fileExists(atPath: originalFilePath)
        else { return nil }
        
        // Create the info with the update callback
        let newPlaybackInfo: PlaybackInfo = PlaybackInfo(
            state: .stopped,
            progress: 0,
            playbackRate: 1,
            oldPlaybackRate: 1,
            updateCallback: updateCallback
        )
        
        // Cache the info
        playbackInfo.mutate { $0[viewModel.id] = newPlaybackInfo }
        
        return newPlaybackInfo
    }
    
    public func playOrPauseAudio(for viewModel: MessageViewModel) {
        guard
            let attachment: Attachment = viewModel.attachments?.first,
            let originalFilePath: String = attachment.originalFilePath,
            FileManager.default.fileExists(atPath: originalFilePath)
        else { return }
        
        // If the user interacted with the currently playing item
        guard currentPlayingInteraction.wrappedValue != viewModel.id else {
            let currentPlaybackInfo: PlaybackInfo? = playbackInfo.wrappedValue[viewModel.id]
            let updatedPlaybackInfo: PlaybackInfo? = currentPlaybackInfo?
                .with(
                    state: (currentPlaybackInfo?.state != .playing ? .playing : .paused),
                    playbackRate: 1
                )
            
            audioPlayer.wrappedValue?.playbackRate = 1
            
            switch currentPlaybackInfo?.state {
                case .playing: audioPlayer.wrappedValue?.pause()
                default: audioPlayer.wrappedValue?.play()
            }
            
            // Update the state and then update the UI with the updated state
            playbackInfo.mutate { $0[viewModel.id] = updatedPlaybackInfo }
            updatedPlaybackInfo?.updateCallback(updatedPlaybackInfo, nil)
            return
        }
        
        // First stop any existing audio
        audioPlayer.wrappedValue?.stop()
        
        // Then setup the state for the new audio
        currentPlayingInteraction.mutate { $0 = viewModel.id }
        
        audioPlayer.mutate { [weak self] player in
            // Note: We clear the delegate and explicitly set to nil here as when the OWSAudioPlayer
            // gets deallocated it triggers state changes which cause UI bugs when auto-playing
            player?.delegate = nil
            player = nil
            
            let audioPlayer: OWSAudioPlayer = OWSAudioPlayer(
                mediaUrl: URL(fileURLWithPath: originalFilePath),
                audioBehavior: .audioMessagePlayback,
                delegate: self
            )
            audioPlayer.play()
            audioPlayer.setCurrentTime(playbackInfo.wrappedValue[viewModel.id]?.progress ?? 0)
            player = audioPlayer
        }
    }
    
    public func speedUpAudio(for viewModel: MessageViewModel) {
        // If we aren't playing the specified item then just start playing it
        guard viewModel.id == currentPlayingInteraction.wrappedValue else {
            playOrPauseAudio(for: viewModel)
            return
        }
        
        let updatedPlaybackInfo: PlaybackInfo? = playbackInfo.wrappedValue[viewModel.id]?
            .with(playbackRate: 1.5)
        
        // Speed up the audio player
        audioPlayer.wrappedValue?.playbackRate = 1.5
        
        playbackInfo.mutate { $0[viewModel.id] = updatedPlaybackInfo }
        updatedPlaybackInfo?.updateCallback(updatedPlaybackInfo, nil)
    }
    
    public func stopAudio() {
        audioPlayer.wrappedValue?.stop()
        
        currentPlayingInteraction.mutate { $0 = nil }
        audioPlayer.mutate {
            // Note: We clear the delegate and explicitly set to nil here as when the OWSAudioPlayer
            // gets deallocated it triggers state changes which cause UI bugs when auto-playing
            $0?.delegate = nil
            $0 = nil
        }
    }
    
    // MARK: - OWSAudioPlayerDelegate
    
    public func audioPlaybackState() -> AudioPlaybackState {
        guard let interactionId: Int64 = currentPlayingInteraction.wrappedValue else { return .stopped }
        
        return (playbackInfo.wrappedValue[interactionId]?.state ?? .stopped)
    }
    
    public func setAudioPlaybackState(_ state: AudioPlaybackState) {
        guard let interactionId: Int64 = currentPlayingInteraction.wrappedValue else { return }
        
        let updatedPlaybackInfo: PlaybackInfo? = playbackInfo.wrappedValue[interactionId]?
            .with(state: state)
        
        playbackInfo.mutate { $0[interactionId] = updatedPlaybackInfo }
        updatedPlaybackInfo?.updateCallback(updatedPlaybackInfo, nil)
    }
    
    public func setAudioProgress(_ progress: CGFloat, duration: CGFloat) {
        guard let interactionId: Int64 = currentPlayingInteraction.wrappedValue else { return }
        
        let updatedPlaybackInfo: PlaybackInfo? = playbackInfo.wrappedValue[interactionId]?
            .with(progress: TimeInterval(progress))
        
        playbackInfo.mutate { $0[interactionId] = updatedPlaybackInfo }
        updatedPlaybackInfo?.updateCallback(updatedPlaybackInfo, nil)
    }
    
    public func audioPlayerDidFinishPlaying(_ player: OWSAudioPlayer, successfully: Bool) {
        guard let interactionId: Int64 = currentPlayingInteraction.wrappedValue else { return }
        guard successfully else { return }
        
        let updatedPlaybackInfo: PlaybackInfo? = playbackInfo.wrappedValue[interactionId]?
            .with(
                state: .stopped,
                progress: 0,
                playbackRate: 1
            )
        
        // Safe the changes and send one final update to the UI
        playbackInfo.mutate { $0[interactionId] = updatedPlaybackInfo }
        updatedPlaybackInfo?.updateCallback(updatedPlaybackInfo, nil)
        
        // Clear out the currently playing record
        currentPlayingInteraction.mutate { $0 = nil }
        audioPlayer.mutate {
            // Note: We clear the delegate and explicitly set to nil here as when the OWSAudioPlayer
            // gets deallocated it triggers state changes which cause UI bugs when auto-playing
            $0?.delegate = nil
            $0 = nil
        }
        
        // If the next interaction is another voice message then autoplay it
        guard
            let messageSection: SectionModel = self.interactionData
                .first(where: { $0.model == .messages }),
            let currentIndex: Int = messageSection.elements
                .firstIndex(where: { $0.id == interactionId }),
            currentIndex < (messageSection.elements.count - 1),
            messageSection.elements[currentIndex + 1].cellType == .audio,
            Storage.shared[.shouldAutoPlayConsecutiveAudioMessages] == true
        else { return }
        
        let nextItem: MessageViewModel = messageSection.elements[currentIndex + 1]
        playOrPauseAudio(for: nextItem)
    }
    
    public func showInvalidAudioFileAlert() {
        guard let interactionId: Int64 = currentPlayingInteraction.wrappedValue else { return }
        
        let updatedPlaybackInfo: PlaybackInfo? = playbackInfo.wrappedValue[interactionId]?
            .with(
                state: .stopped,
                progress: 0,
                playbackRate: 1
            )
        
        currentPlayingInteraction.mutate { $0 = nil }
        playbackInfo.mutate { $0[interactionId] = updatedPlaybackInfo }
        updatedPlaybackInfo?.updateCallback(updatedPlaybackInfo, AttachmentError.invalidData)
    }
}
