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
    /// **Note:** The 'trackingConstantRegion' is optimised in such a way that the request needs to be static
    /// otherwise there may be situations where it doesn't get updates, this means we can't have conditional queries
    public lazy var observableViewData = ValueObservation
        .trackingConstantRegion { db -> [ArraySection<Section, SessionThreadViewModel>] in
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            let unreadMessageRequestCount: Int = try SessionThread
                .filter(SessionThread.isMessageRequest(userPublicKey: userPublicKey))
                .joining(optional: SessionThread.contact)
                .joining(
                    required: SessionThread.interactions
                        .filter(Interaction.Columns.wasRead == false)
                )
                .group(SessionThread.Columns.id)
                .fetchCount(db)
            let finalUnreadMessageRequestCount: Int = (db[.hasHiddenMessageRequests] ? 0 : unreadMessageRequestCount)
            
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
                    elements: try SessionThreadViewModel
                        .homeQuery(userPublicKey: userPublicKey)
                        .fetchAll(db)
                )
            ]
        }
        .removeDuplicates()
    
    // MARK: - Functions
    
    public func updateData(_ updatedData: [ArraySection<Section, SessionThreadViewModel>]) {
        self.viewData = updatedData
    }
}
