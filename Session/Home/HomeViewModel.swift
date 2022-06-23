// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SignalUtilitiesKit

public class HomeViewModel {
    public enum Section: Differentiable {
        case messageRequests
        case threads
    }
    
    public struct State: Equatable {
        let showViewedSeedBanner: Bool
        let userProfile: Profile?
        let sections: [ArraySection<Section, SessionThreadViewModel>]
        
        func with(
            showViewedSeedBanner: Bool? = nil,
            userProfile: Profile? = nil,
            sections: [ArraySection<Section, SessionThreadViewModel>]? = nil
        ) -> State {
            return State(
                showViewedSeedBanner: (showViewedSeedBanner ?? self.showViewedSeedBanner),
                userProfile: (userProfile ?? self.userProfile),
                sections: (sections ?? self.sections)
            )
        }
    }
    
    /// This value is the current state of the view
    public private(set) var state: State = State(
        showViewedSeedBanner: !GRDBStorage.shared[.hasViewedSeed],
        userProfile: nil,
        sections: []
    )
    
    /// This is all the data the screen needs to populate itself, please see the following link for tips to help optimise
    /// performance https://github.com/groue/GRDB.swift#valueobservation-performance
    ///
    /// **Note:** This observation will be triggered twice immediately (and be de-duped by the `removeDuplicates`)
    /// this is due to the behaviour of `ValueConcurrentObserver.asyncStartObservation` which triggers it's own
    /// fetch (after the ones in `ValueConcurrentObserver.asyncStart`/`ValueConcurrentObserver.syncStart`)
    /// just in case the database has changed between the two reads - unfortunately it doesn't look like there is a way to prevent this
    public lazy var observableState = ValueObservation
        .tracking(
            regions: [
                // We explicitly define the regions we want to track as the automatic detection
                // seems to include a bunch of columns we will fetch but probably don't need to
                // track changes for
                SessionThread.select(
                    .id,
                    .shouldBeVisible,
                    .isPinned,
                    .mutedUntilTimestamp,
                    .onlyNotifyForMentions
                ),
                Setting.filter(ids: [
                    Setting.BoolKey.hasHiddenMessageRequests.rawValue,
                    Setting.BoolKey.hasViewedSeed.rawValue
                ]),
                Contact.select(.isBlocked, .isApproved),    // 'isApproved' for message requests
                Profile.select(.name, .nickname, .profilePictureFileName),
                ClosedGroup.select(.name),
                OpenGroup.select(.name, .imageData),
                GroupMember.select(.groupId),
                Interaction.select(
                    .body,
                    .wasRead
                ),
                Attachment.select(.state),
                RecipientState.select(.state),
                ThreadTypingIndicator.select(.threadId)
            ],
            fetch: { db -> State in
                let hasViewedSeed: Bool = db[.hasViewedSeed]
                let userProfile: Profile = Profile.fetchOrCreateCurrentUser(db)
                let unreadMessageRequestCount: Int = try SessionThread
                    .unreadMessageRequestsQuery(userPublicKey: userProfile.id)
                    .fetchCount(db)
                let finalUnreadMessageRequestCount: Int = (db[.hasHiddenMessageRequests] ? 0 : unreadMessageRequestCount)
                let threads: [SessionThreadViewModel] = try SessionThreadViewModel
                    .homeQuery(userPublicKey: userProfile.id)
                    .fetchAll(db)
                
                return State(
                    showViewedSeedBanner: !hasViewedSeed,
                    userProfile: userProfile,
                    sections: [
                        ArraySection(
                            model: .messageRequests,
                            elements: [
                                // If there are no unread message requests then hide the message request banner
                                (finalUnreadMessageRequestCount == 0 ?
                                    nil :
                                    SessionThreadViewModel(
                                        unreadCount: UInt(finalUnreadMessageRequestCount)
                                    )
                                )
                            ].compactMap { $0 }
                        ),
                        ArraySection(
                            model: .threads,
                            elements: threads
                        )
                    ]
                )
            }
        )
        .removeDuplicates()
    
    // MARK: - Functions
    
    public func updateState(_ updatedState: State) {
        self.state = updatedState
    }
}
