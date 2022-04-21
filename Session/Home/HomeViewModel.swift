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
    
    public struct Item: Equatable, Differentiable {
        public var differenceIdentifier: String {
            return (threadViewModel?.thread.id ?? "\(unreadCount)")
        }
        
        let unreadCount: Int
        let threadViewModel: ThreadViewModel?
    }
    
    /// This value is the current state of the view
    public private(set) var viewData: [ArraySection<Section, Item>] = []
    
    /// This is all the data the HomeVC needs to populate itself, please see the following link for tips to help optimise
    /// performance https://github.com/groue/GRDB.swift#valueobservation-performance
    public lazy var observableViewData = ValueObservation.tracking { db -> [ArraySection<Section, Item>] in
        // If message requests are hidden then don't bother fetching the unread count
        let unreadMessageRequestCount: Int = (db[.hasHiddenMessageRequests] ?
            0 :
            try SessionThread
                .messageRequestThreads(db)
                .joining(
                    required: SessionThread.interactions
                        .filter(Interaction.Columns.wasRead == false)
                )
                .fetchCount(db)
        )
        
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        let threadViewModels = try SessionThread
            .fetchAll(db)
            .compactMap { thread -> ThreadViewModel? in
                let lastInteraction: Interaction? = try thread
                    .interactions
                    .order(Interaction.Columns.id.desc)
                    .fetchOne(db)
                
                // Only show the 'Note to Self' thread if it has interactions
                guard !thread.isNoteToSelf(db) || lastInteraction != nil else { return nil }
                
                let unreadMessageCount: Int = try thread
                    .interactions
                    .filter(Interaction.Columns.wasRead == false)
                    .fetchCount(db)
                let quoteAlias: TableAlias = TableAlias()
                let unreadMentionCount: Int = try thread
                    .interactions
                    .filter(Interaction.Columns.wasRead == false)
                    .joining(
                        optional: Interaction.quote
                            .aliased(quoteAlias)// TODO: Test that this works
                    )
                    .filter(
                        Interaction.Columns.body.like("%@\(userPublicKey)") ||
                        quoteAlias[Quote.Columns.authorId] == userPublicKey
                    )
                    .fetchCount(db)
                
                return ThreadViewModel(
                    thread: thread,
                    name: thread.name(db),
                    unreadCount: UInt(unreadMessageCount),
                    unreadMentionCount: UInt(unreadMentionCount),
                    lastInteraction: lastInteraction,
                    lastInteractionDate: (
                        lastInteraction.map { Date(timeIntervalSince1970: Double($0.timestampMs / 1000)) } ??
                        Date(timeIntervalSince1970: thread.creationDateTimestamp)
                    ),
                    lastInteractionText: lastInteraction?.previewText(db),
                    lastInteractionState: try lastInteraction?.state(db)
                )
            }
        
        return [
            ArraySection(
                model: .messageRequests,
                elements: [
                    // If there are no unread message requests then hide the message request banner
                    (unreadMessageRequestCount == 0 ?
                        nil :
                        Item(
                            unreadCount: unreadMessageRequestCount,
                            threadViewModel: nil
                        )
                    )
                ].compactMap { $0 }
            ),
            ArraySection(
                model: .threads,
                elements: threadViewModels
                    .sorted(by: { lhs, rhs in lhs.lastInteractionDate > rhs.lastInteractionDate })
                    .map {
                        Item(
                            unreadCount: Int($0.unreadCount),
                            threadViewModel: $0
                        )
                    }
            ),
        ]
    }
    
    // MARK: - Functions
    
    public func updateData(_ updatedData: [ArraySection<Section, Item>]) {
        self.viewData = updatedData
    }
}
