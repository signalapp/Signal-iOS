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
    
    /// This value is the current state of the view
    public private(set) var viewData: [ArraySection<Section, SessionThreadViewModel>] = []
    
    /// This is all the data the screen needs to populate itself, please see the following link for tips to help optimise
    /// performance https://github.com/groue/GRDB.swift#valueobservation-performance
    ///
    /// **Note:** This observation will be triggered twice immediately (and be de-duped by the `removeDuplicates`)
    /// this is due to the behaviour of `ValueConcurrentObserver.asyncStartObservation` which triggers it's own
    /// fetch (after the ones in `ValueConcurrentObserver.asyncStart`/`ValueConcurrentObserver.syncStart`)
    /// just in case the database has changed between the two reads - unfortunately it doesn't look like there is a way to prevent this
    public lazy var observableViewData = ValueObservation
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
                Setting.filter(id: Setting.BoolKey.hasHiddenMessageRequests.rawValue),
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
            fetch: { db -> [ArraySection<Section, SessionThreadViewModel>] in
                let userPublicKey: String = getUserHexEncodedPublicKey(db)
                let unreadMessageRequestCount: Int = try SessionThread
                    .unreadMessageRequestsCountQuery(userPublicKey: userPublicKey)
                    .fetchOne(db)
                    .defaulting(to: 0)
                let finalUnreadMessageRequestCount: Int = (db[.hasHiddenMessageRequests] ? 0 : unreadMessageRequestCount)
                let threads: [SessionThreadViewModel] = try SessionThreadViewModel
                    .homeQuery(userPublicKey: userPublicKey)
                    .fetchAll(db)
                
                return [
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
            }
        )
        .removeDuplicates()
    
    // MARK: - Functions
    
    public func updateData(_ updatedData: [ArraySection<Section, SessionThreadViewModel>]) {
        self.viewData = updatedData
    }
}
