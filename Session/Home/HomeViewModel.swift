// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SignalUtilitiesKit
import SessionUtilitiesKit

public class HomeViewModel {
    public typealias SectionModel = ArraySection<Section, SessionThreadViewModel>
    
    // MARK: - Section
    
    public enum Section: Differentiable {
        case messageRequests
        case threads
        case loadMore
    }
    
    // MARK: - Variables
    
    public static let pageSize: Int = 15
    
    public struct State: Equatable {
        let showViewedSeedBanner: Bool
        let hasHiddenMessageRequests: Bool
        let unreadMessageRequestThreadCount: Int
        let userProfile: Profile?
        
        init(
            showViewedSeedBanner: Bool = !Storage.shared[.hasViewedSeed],
            hasHiddenMessageRequests: Bool = Storage.shared[.hasHiddenMessageRequests],
            unreadMessageRequestThreadCount: Int = 0,
            userProfile: Profile? = nil
        ) {
            self.showViewedSeedBanner = showViewedSeedBanner
            self.hasHiddenMessageRequests = hasHiddenMessageRequests
            self.unreadMessageRequestThreadCount = unreadMessageRequestThreadCount
            self.userProfile = userProfile
        }
    }
    
    // MARK: - Initialization
    
    init() {
        self.state = State()
        self.pagedDataObserver = nil
        
        // Note: Since this references self we need to finish initializing before setting it, we
        // also want to skip the initial query and trigger it async so that the push animation
        // doesn't stutter (it should load basically immediately but without this there is a
        // distinct stutter)
        let userPublicKey: String = getUserHexEncodedPublicKey()
        let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
        self.pagedDataObserver = PagedDatabaseObserver(
            pagedTable: SessionThread.self,
            pageSize: HomeViewModel.pageSize,
            idColumn: .id,
            observedChanges: [
                PagedData.ObservedChanges(
                    table: SessionThread.self,
                    columns: [
                        .id,
                        .shouldBeVisible,
                        .isPinned,
                        .mutedUntilTimestamp,
                        .onlyNotifyForMentions
                    ]
                ),
                PagedData.ObservedChanges(
                    table: Interaction.self,
                    columns: [
                        .body,
                        .wasRead
                    ],
                    joinToPagedType: {
                        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                        
                        return SQL("LEFT JOIN \(Interaction.self) ON \(interaction[.threadId]) = \(thread[.id])")
                    }()
                ),
                PagedData.ObservedChanges(
                    table: Contact.self,
                    columns: [.isBlocked],
                    joinToPagedType: {
                        let contact: TypedTableAlias<Contact> = TypedTableAlias()
                        
                        return SQL("LEFT JOIN \(Contact.self) ON \(contact[.id]) = \(thread[.id])")
                    }()
                ),
                PagedData.ObservedChanges(
                    table: Profile.self,
                    columns: [.name, .nickname, .profilePictureFileName],
                    joinToPagedType: {
                        let profile: TypedTableAlias<Profile> = TypedTableAlias()
                        
                        return SQL("LEFT JOIN \(Profile.self) ON \(profile[.id]) = \(thread[.id])")
                    }()
                ),
                PagedData.ObservedChanges(
                    table: ClosedGroup.self,
                    columns: [.name],
                    joinToPagedType: {
                        let closedGroup: TypedTableAlias<ClosedGroup> = TypedTableAlias()
                        
                        return SQL("LEFT JOIN \(ClosedGroup.self) ON \(closedGroup[.threadId]) = \(thread[.id])")
                    }()
                ),
                PagedData.ObservedChanges(
                    table: OpenGroup.self,
                    columns: [.name, .imageData],
                    joinToPagedType: {
                        let openGroup: TypedTableAlias<OpenGroup> = TypedTableAlias()
                        
                        return SQL("LEFT JOIN \(OpenGroup.self) ON \(openGroup[.threadId]) = \(thread[.id])")
                    }()
                ),
                PagedData.ObservedChanges(
                    table: RecipientState.self,
                    columns: [.state],
                    joinToPagedType: {
                        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
                        let recipientState: TypedTableAlias<RecipientState> = TypedTableAlias()
                        
                        return """
                            LEFT JOIN \(Interaction.self) ON \(interaction[.threadId]) = \(thread[.id])
                            LEFT JOIN \(RecipientState.self) ON \(recipientState[.interactionId]) = \(interaction[.id])
                        """
                    }()
                ),
                PagedData.ObservedChanges(
                    table: ThreadTypingIndicator.self,
                    columns: [.threadId],
                    joinToPagedType: {
                        let typingIndicator: TypedTableAlias<ThreadTypingIndicator> = TypedTableAlias()
                        
                        return SQL("LEFT JOIN \(typingIndicator[.threadId]) = \(thread[.id])")
                    }()
                ),
                PagedData.ObservedChanges(
                    table: Setting.self,
                    columns: [.value],
                    joinToPagedType: {
                        let setting: TypedTableAlias<Setting> = TypedTableAlias()
                        let targetSetting: String = Setting.BoolKey.showScreenshotNotifications.rawValue
                        
                        return SQL("LEFT JOIN \(Setting.self) ON \(setting[.key]) = \(targetSetting)")
                    }()
                )
            ],
            /// **Note:** This `optimisedJoinSQL` value includes the required minimum joins needed for the query but differs
            /// from the JOINs that are actually used for performance reasons as the basic logic can be simpler for where it's used
            joinSQL: SessionThreadViewModel.optimisedJoinSQL,
            filterSQL: SessionThreadViewModel.homeFilterSQL(userPublicKey: userPublicKey),
            groupSQL: SessionThreadViewModel.groupSQL,
            orderSQL: SessionThreadViewModel.homeOrderSQL,
            dataQuery: SessionThreadViewModel.baseQuery(
                userPublicKey: userPublicKey,
                groupSQL: SessionThreadViewModel.groupSQL,
                orderSQL: SessionThreadViewModel.homeOrderSQL
            ),
            onChangeUnsorted: { [weak self] updatedData, updatedPageInfo in
                guard let updatedThreadData: [SectionModel] = self?.process(data: updatedData, for: updatedPageInfo) else {
                    return
                }
                
                // If we have the 'onThreadChange' callback then trigger it, otherwise just store the changes
                // to be sent to the callback if we ever start observing again (when we have the callback it needs
                // to do the data updating as it's tied to UI updates and can cause crashes if not updated in the
                // correct order)
                guard let onThreadChange: (([SectionModel]) -> ()) = self?.onThreadChange else {
                    self?.unobservedThreadDataChanges = updatedThreadData
                    return
                }

                onThreadChange(updatedThreadData)
            }
        )
        
        // Run the initial query on the main thread so we prevent the app from leaving the loading screen
        // until we have data (Note: the `.pageBefore` will query from a `0` offset loading the first page)
        self.pagedDataObserver?.load(.pageBefore)
    }
    
    // MARK: - State
    
    /// This value is the current state of the view
    public private(set) var state: State
    
    /// This is all the data the screen needs to populate itself, please see the following link for tips to help optimise
    /// performance https://github.com/groue/GRDB.swift#valueobservation-performance
    ///
    /// **Note:** This observation will be triggered twice immediately (and be de-duped by the `removeDuplicates`)
    /// this is due to the behaviour of `ValueConcurrentObserver.asyncStartObservation` which triggers it's own
    /// fetch (after the ones in `ValueConcurrentObserver.asyncStart`/`ValueConcurrentObserver.syncStart`)
    /// just in case the database has changed between the two reads - unfortunately it doesn't look like there is a way to prevent this
    public lazy var observableState = ValueObservation
        .trackingConstantRegion { db -> State in try HomeViewModel.retrieveState(db) }
        .removeDuplicates()
    
    private static func retrieveState(_ db: Database) throws -> State {
        let hasViewedSeed: Bool = db[.hasViewedSeed]
        let hasHiddenMessageRequests: Bool = db[.hasHiddenMessageRequests]
        let userProfile: Profile = Profile.fetchOrCreateCurrentUser(db)
        let unreadMessageRequestThreadCount: Int = try SessionThread
            .unreadMessageRequestsCountQuery(userPublicKey: userProfile.id)
            .fetchOne(db)
            .defaulting(to: 0)
        
        return State(
            showViewedSeedBanner: !hasViewedSeed,
            hasHiddenMessageRequests: hasHiddenMessageRequests,
            unreadMessageRequestThreadCount: unreadMessageRequestThreadCount,
            userProfile: userProfile
        )
    }
    
    public func updateState(_ updatedState: State) {
        let oldState: State = self.state
        self.state = updatedState
        
        // If the messageRequest content changed then we need to re-process the thread data
        guard
            (
                oldState.hasHiddenMessageRequests != updatedState.hasHiddenMessageRequests ||
                oldState.unreadMessageRequestThreadCount != updatedState.unreadMessageRequestThreadCount
            ),
            let currentPageInfo: PagedData.PageInfo = self.pagedDataObserver?.pageInfo.wrappedValue
        else { return }
        
        /// **MUST** have the same logic as in the 'PagedDataObserver.onChangeUnsorted' above
        let currentData: [SessionThreadViewModel] = (self.unobservedThreadDataChanges ?? self.threadData)
            .flatMap { $0.elements }
        let updatedThreadData: [SectionModel] = self.process(data: currentData, for: currentPageInfo)
        
        guard let onThreadChange: (([SectionModel]) -> ()) = self.onThreadChange else {
            self.unobservedThreadDataChanges = updatedThreadData
            return
        }
        
        onThreadChange(updatedThreadData)
    }
    
    // MARK: - Thread Data
    
    public private(set) var unobservedThreadDataChanges: [SectionModel]?
    public private(set) var threadData: [SectionModel] = []
    public private(set) var pagedDataObserver: PagedDatabaseObserver<SessionThread, SessionThreadViewModel>?
    
    public var onThreadChange: (([SectionModel]) -> ())? {
        didSet {
            // When starting to observe interaction changes we want to trigger a UI update just in case the
            // data was changed while we weren't observing
            if let unobservedThreadDataChanges: [SectionModel] = self.unobservedThreadDataChanges {
                onThreadChange?(unobservedThreadDataChanges)
                self.unobservedThreadDataChanges = nil
            }
        }
    }
    
    private func process(data: [SessionThreadViewModel], for pageInfo: PagedData.PageInfo) -> [SectionModel] {
        let finalUnreadMessageRequestCount: Int = (self.state.hasHiddenMessageRequests ?
            0 :
            self.state.unreadMessageRequestThreadCount
        )
        let groupedOldData: [String: [SessionThreadViewModel]] = (self.threadData
            .first(where: { $0.model == .threads })?
            .elements)
            .defaulting(to: [])
            .grouped(by: \.threadId)
        
        return [
            // If there are no unread message requests then hide the message request banner
            (finalUnreadMessageRequestCount == 0 ?
                [] :
                [SectionModel(
                    section: .messageRequests,
                    elements: [
                        SessionThreadViewModel(unreadCount: UInt(finalUnreadMessageRequestCount))
                    ]
                )]
            ),
            [
                SectionModel(
                    section: .threads,
                    elements: data
                        .filter { $0.id != SessionThreadViewModel.invalidId }
                        .sorted { lhs, rhs -> Bool in
                            if lhs.threadIsPinned && !rhs.threadIsPinned { return true }
                            if !lhs.threadIsPinned && rhs.threadIsPinned { return false }
                            
                            return lhs.lastInteractionDate > rhs.lastInteractionDate
                        }
                        .map { viewModel -> SessionThreadViewModel in
                            viewModel.populatingCurrentUserBlindedKey(
                                currentUserBlindedPublicKeyForThisThread: groupedOldData[viewModel.threadId]?
                                    .first?
                                    .currentUserBlindedPublicKey
                            )
                        }
                )
            ],
            (!data.isEmpty && (pageInfo.pageOffset + pageInfo.currentCount) < pageInfo.totalCount ?
                [SectionModel(section: .loadMore)] :
                []
            )
        ].flatMap { $0 }
    }
    
    public func updateThreadData(_ updatedData: [SectionModel]) {
        self.threadData = updatedData
    }
    
    // MARK: - Functions
    
    public func delete(threadId: String, threadVariant: SessionThread.Variant) {
        Storage.shared.writeAsync { db in
            switch threadVariant {
                case .closedGroup:
                    try MessageSender
                        .leave(db, groupPublicKey: threadId)
                        .retainUntilComplete()
                    
                case .openGroup:
                    OpenGroupManager.shared.delete(db, openGroupId: threadId)
                    
                default: break
            }
            
            _ = try SessionThread
                .filter(id: threadId)
                .deleteAll(db)
        }
    }
}
