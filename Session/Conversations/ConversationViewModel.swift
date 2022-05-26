// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SessionMessagingKit
import SessionUtilitiesKit

public class ConversationViewModel: OWSAudioPlayerDelegate {
    public typealias SectionModel = ArraySection<Section, MessageCell.ViewModel>
    
    // MARK: - Action
    
    public enum Action {
        case none
        case compose
        case audioCall
        case videoCall
    }
    
    public static let pageSize: Int = 50
    // MARK: - Section
    
    public enum Section: Differentiable, Equatable, Comparable, Hashable {
        case loadOlder
        case messages
        case loadNewer
    }
    
    // MARK: - Variables
    
    
    // MARK: - Initialization
    
    init?(threadId: String, focusedInteractionId: Int64?) {
        let maybeThreadData: ConversationCell.ViewModel? = GRDBStorage.shared.read { db in
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            
            return try ConversationCell.ViewModel
                .conversationQuery(
                    threadId: threadId,
                    userPublicKey: userPublicKey
                )
                .fetchOne(db)
        }
        
        guard let threadData: ConversationCell.ViewModel = maybeThreadData else { return nil }
        
        self.threadId = threadId
        self.threadData = threadData
        self.focusedInteractionId = focusedInteractionId
        self.pagedDataObserver = nil
        
        DispatchQueue.global(qos: .default).async { [weak self] in
            self?.pagedDataObserver = PagedDatabaseObserver(
                pagedTable: Interaction.self,
                pageSize: ConversationViewModel.pageSize,
                idColumn: .id,
                initialFocusedId: focusedInteractionId,
                observedChanges: [
                    PagedData.ObservedChanges(
                        table: Interaction.self,
                        columns: Interaction.Columns
                            .allCases
                            .filter { $0 != .wasRead }
                    )
                ],
                filterSQL: MessageCell.ViewModel.filterSQL(threadId: threadId),
                orderSQL: MessageCell.ViewModel.orderSQL,
                dataQuery: MessageCell.ViewModel.baseQuery(
                    orderSQL: MessageCell.ViewModel.orderSQL,
                    baseFilterSQL: MessageCell.ViewModel.filterSQL(threadId: threadId)
                ),
                associatedRecords: [
                    AssociatedRecord<MessageCell.AttachmentInteractionInfo, MessageCell.ViewModel>(
                        trackedAgainst: Attachment.self,
                        observedChanges: [
                            PagedData.ObservedChanges(
                                table: Attachment.self,
                                columns: [.state]
                            )
                        ],
                        dataQuery: MessageCell.AttachmentInteractionInfo.baseQuery,
                        joinToPagedType: MessageCell.AttachmentInteractionInfo.joinToViewModelQuerySQL,
                        associateData: MessageCell.AttachmentInteractionInfo.createAssociateDataClosure()
                    )
                ],
                onChangeUnsorted: { [weak self] updatedData, updatedPageInfo in
                    guard let updatedInteractionData: [SectionModel] = self?.process(data: updatedData, for: updatedPageInfo) else {
                        return
                    }
                    
                    self?.onInteractionChange?(updatedInteractionData)
                }
            )
        }
    }
    
    // MARK: - Variables
    
    private let threadId: String
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
    
    // MARK: - Thread Data
    
    /// This value is the current state of the view
    public private(set) var threadData: ConversationCell.ViewModel
    
    public lazy var observableThreadData = ValueObservation
        .trackingConstantRegion { [threadId = self.threadId] db -> ConversationCell.ViewModel? in
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            
            return try ConversationCell.ViewModel
                .conversationQuery(threadId: threadId, userPublicKey: userPublicKey)
                .fetchOne(db)
        }
        .removeDuplicates()

    public func updateThreadData(_ updatedData: ConversationCell.ViewModel) {
        self.threadData = updatedData
    }
    
    // MARK: - Interaction Data
    
    public private(set) var interactionData: [SectionModel] = []
    public private(set) var pagedDataObserver: PagedDatabaseObserver<Interaction, MessageCell.ViewModel>?
    public var onInteractionChange: (([SectionModel]) -> ())?
    
    private func process(data: [MessageCell.ViewModel], for pageInfo: PagedData.PageInfo) -> [SectionModel] {
        let sortedData: [MessageCell.ViewModel] = data
            .sorted { lhs, rhs -> Bool in lhs.timestampMs < rhs.timestampMs }
        
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
                        .map { index, cellViewModel -> MessageCell.ViewModel in
                            cellViewModel.withClusteringChanges(
                                prevModel: (index > 0 ? sortedData[index - 1] : nil),
                                nextModel: (index < (sortedData.count - 2) ? sortedData[index + 1] : nil),
                                isLast: (
                                    index == (sortedData.count - 1) &&
                                    pageInfo.currentCount == pageInfo.totalCount
                                )
                            )
                        }
                )
            ],
            (data.isEmpty && pageInfo.pageOffset > 0 ?
                [SectionModel(section: .loadNewer)] :
                []
            )
        ].flatMap { $0 }
    }
    
    public func updateInteractionData(_ updatedData: [SectionModel]) {
        self.interactionData = updatedData
    }
    
    // MARK: - Mentions
    
    public struct MentionInfo: FetchableRecord, Decodable {
        fileprivate static let threadVariantKey = CodingKeys.threadVariant.stringValue
        fileprivate static let openGroupRoomKey = CodingKeys.openGroupRoom.stringValue
        fileprivate static let openGroupServerKey = CodingKeys.openGroupServer.stringValue
        
        let profile: Profile
        let threadVariant: SessionThread.Variant
        let openGroupRoom: String?
        let openGroupServer: String?
    }
    
    public func mentions(for query: String = "") -> [MentionInfo] {
        let threadData: ConversationCell.ViewModel = self.threadData
        
        let results: [MentionInfo] = GRDBStorage.shared
            .read { db -> [MentionInfo] in
                let userPublicKey: String = getUserHexEncodedPublicKey(db)
                
                switch threadData.threadVariant {
                    case .contact:
                        guard userPublicKey != threadData.threadId else { return [] }
                        
                        return [Profile.fetchOrCreate(db, id: threadData.threadId)]
                            .map { profile in
                                MentionInfo(
                                    profile: profile,
                                    threadVariant: threadData.threadVariant,
                                    openGroupRoom: nil,
                                    openGroupServer: nil
                                )
                            }
                            .filter {
                                query.count < 2 ||
                                $0.profile.displayName(for: $0.threadVariant).contains(query)
                            }
                        
                    case .closedGroup:
                        let profile: TypedTableAlias<Profile> = TypedTableAlias()
                        
                        return try GroupMember
                            .select(
                                profile.allColumns(),
                                SQL("\(threadData.threadVariant)").forKey(MentionInfo.threadVariantKey)
                            )
                            .filter(GroupMember.Columns.groupId == threadData.threadId)
                            .filter(GroupMember.Columns.profileId != userPublicKey)
                            .filter(GroupMember.Columns.role == GroupMember.Role.standard)
                            .joining(
                                required: GroupMember.profile
                                    .aliased(profile)
                                    // Note: LIKE is case-insensitive in SQLite
                                    .filter(
                                        query.count < 2 || (
                                            profile[.nickname] != nil &&
                                            profile[.nickname].like("%\(query)%")
                                        ) || (
                                            profile[.nickname] == nil &&
                                            profile[.name].like("%\(query)%")
                                        )
                                    )
                            )
                            .asRequest(of: MentionInfo.self)
                            .fetchAll(db)
                        
                    case .openGroup:
                        let profile: TypedTableAlias<Profile> = TypedTableAlias()
                        
                        return try Interaction
                            .select(
                                profile.allColumns(),
                                SQL("\(threadData.threadVariant)").forKey(MentionInfo.threadVariantKey),
                                SQL("\(threadData.openGroupRoom)").forKey(MentionInfo.openGroupRoomKey),
                                SQL("\(threadData.openGroupServer)").forKey(MentionInfo.openGroupServerKey)
                            )
                            .distinct()
                            .group(Interaction.Columns.authorId)
                            .filter(Interaction.Columns.threadId == threadData.threadId)
                            .filter(Interaction.Columns.authorId != userPublicKey)
                            .joining(
                                required: Interaction.profile
                                    .aliased(profile)
                                    // Note: LIKE is case-insensitive in SQLite
                                    .filter(
                                        query.count < 2 || (
                                            profile[.nickname] != nil &&
                                            profile[.nickname].like("%\(query)%")
                                        ) || (
                                            profile[.nickname] == nil &&
                                            profile[.name].like("%\(query)%")
                                        )
                                    )
                            )
                            .order(Interaction.Columns.timestampMs.desc)
                            .limit(20)
                            .asRequest(of: MentionInfo.self)
                            .fetchAll(db)
                }
            }
            .defaulting(to: [])
        
        guard query.count >= 2 else {
            return results.sorted { lhs, rhs -> Bool in
                lhs.profile.displayName(for: lhs.threadVariant) < rhs.profile.displayName(for: rhs.threadVariant)
            }
        }
        
        return results
            .sorted { lhs, rhs -> Bool in
                let maybeLhsRange = lhs.profile.displayName(for: lhs.threadVariant).lowercased().range(of: query.lowercased())
                let maybeRhsRange = rhs.profile.displayName(for: rhs.threadVariant).lowercased().range(of: query.lowercased())
                
                guard let lhsRange: Range<String.Index> = maybeLhsRange, let rhsRange: Range<String.Index> = maybeRhsRange else {
                    return true
                }
                
                return (lhsRange.lowerBound < rhsRange.lowerBound)
            }
    }
    
    // MARK: - Functions
    
    public func updateDraft(to draft: String) {
        GRDBStorage.shared.write { db in
            try SessionThread
                .filter(id: self.threadId)
                .updateAll(db, SessionThread.Columns.messageDraft.set(to: draft))
        }
    }
    
    public func markAllAsRead() {
        guard
            let lastInteractionId: Int64 = self.interactionData
                .first(where: { $0.model == .messages })?
                .elements
                .last?
                .id
        else { return }
        
        GRDBStorage.shared.write { db in
            try Interaction.markAsRead(
                db,
                interactionId: lastInteractionId,
                threadId: self.threadData.threadId,
                includingOlder: true,
                trySendReadReceipt: (self.threadData.threadIsMessageRequest == false)
            )
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
    
    public func playbackInfo(for viewModel: MessageCell.ViewModel, updateCallback: ((PlaybackInfo?, Error?) -> ())? = nil) -> PlaybackInfo? {
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
    
    public func playOrPauseAudio(for viewModel: MessageCell.ViewModel) {
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
    
    public func speedUpAudio(for viewModel: MessageCell.ViewModel) {
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
        audioPlayer.mutate { $0 = nil }
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
        audioPlayer.mutate { $0 = nil }
        
        // If the next interaction is another voice message then autoplay it
        guard
            let messageSection: SectionModel = self.interactionData
                .first(where: { $0.model == .messages }),
            let currentIndex: Int = messageSection.elements
                .firstIndex(where: { $0.id == interactionId }),
            currentIndex < (messageSection.elements.count - 1),
            messageSection.elements[currentIndex + 1].cellType == .audio
        else { return }
        
        let nextItem: MessageCell.ViewModel = messageSection.elements[currentIndex + 1]
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
