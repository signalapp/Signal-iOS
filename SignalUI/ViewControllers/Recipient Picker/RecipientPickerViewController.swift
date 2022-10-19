//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension RecipientPickerViewController {
    @objc(groupSectionForSearchResults:)
    public func groupSection(for searchResults: ComposeScreenSearchResultSet) -> OWSTableSection? {
        let groupThreads: [TSGroupThread]
        switch groupsToShow {
        case .showNoGroups:
            return nil
        case .showGroupsThatUserIsMemberOfWhenSearching:
            groupThreads = searchResults.groupThreads.filter { thread in
                thread.isLocalUserFullMember
            }
        case .showAllGroupsWhenSearching:
            groupThreads = searchResults.groupThreads
        }

        guard !groupThreads.isEmpty else { return nil }

        return OWSTableSection(
            title: NSLocalizedString(
                "COMPOSE_MESSAGE_GROUP_SECTION_TITLE",
                comment: "Table section header for group listing when composing a new message"
            ),
            items: groupThreads.map {
                self.item(forRecipient: PickedRecipient.for(groupThread: $0))
            }
        )
    }

    @objc
    func discover(phoneNumbers: Set<String>, success: @escaping (Set<SignalRecipient>) -> Void) {
        firstly {
            ContactDiscoveryTask(phoneNumbers: phoneNumbers).perform(at: .userInitiated)
        }.done(on: .main) {
            success($0)
        }.cauterize()
    }
}
