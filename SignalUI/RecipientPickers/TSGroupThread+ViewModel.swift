//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public extension TSGroupThread {
    /// Returns a list of up to `limit` names of group members.
    ///
    /// The list will not contain the local user. If `includingBlocked` is
    /// `false`, it will also not contain any users that have been blocked by
    /// the local user.
    ///
    /// The name returned is computed by `getDisplayName`, but sorting is always
    /// done using `ContactsManager.comparableName(for:transaction:)`. Phone
    /// numbers are sorted to the end of the list.
    ///
    /// If `searchText` is provided, members will be sorted to the front of the
    /// list if their display names (as returned by `getDisplayName`) contain
    /// the string. The names will also have the matching substring bracketed as
    /// `<match>substring</match>`, similar to the results of
    /// FullTextSearchFinder.
    func sortedMemberNames(
        searchText: String? = nil,
        includingBlocked: Bool,
        limit: Int = .max,
        useShortNameIfAvailable: Bool = false,
        nameResolver: NameResolver = NameResolverImpl(contactsManager: SSKEnvironment.shared.contactManagerRef),
        transaction: SDSAnyReadTransaction
    ) -> [String] {
        let tx = transaction.asV2Read
        let config: DisplayName.ComparableValue.Config = .current()

        let members = groupMembership.fullMembers.compactMap { address -> (
            comparableName: ComparableDisplayName,
            matchedDisplayName: String?
        )? in
            guard !address.isLocalAddress else {
                return nil
            }
            guard includingBlocked || !SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(address, transaction: transaction) else {
                return nil
            }

            let displayName = nameResolver.displayName(for: address, tx: tx)
            let comparableName = ComparableDisplayName(address: address, displayName: displayName, config: config)

            var wrappedDisplayNameMatch: String?
            if let searchText {
                wrappedDisplayNameMatch = wrapIfMatch(
                    searchText: searchText,
                    displayName: comparableName.resolvedValue(useShortNameIfAvailable: useShortNameIfAvailable)
                )
            }

            return (comparableName: comparableName, matchedDisplayName: wrappedDisplayNameMatch)
        }

        let sortedMembers = members.sorted { lhs, rhs in
            // Bubble matched members to the top
            if (rhs.matchedDisplayName != nil) != (lhs.matchedDisplayName != nil) {
                return lhs.matchedDisplayName != nil
            }
            return lhs.comparableName < rhs.comparableName
        }

        return sortedMembers.lazy.prefix(limit).map {
            if let matchedDisplayName = $0.matchedDisplayName {
                return matchedDisplayName
            }
            return $0.comparableName.resolvedValue(useShortNameIfAvailable: useShortNameIfAvailable)
        }
    }

    private func wrapIfMatch(searchText: String, displayName: String) -> String? {
        guard
            let matchRange = displayName.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive])
        else {
            return nil
        }
        return displayName.replacingCharacters(
            in: matchRange,
            with: "<\(FullTextSearchIndexer.matchTag)>\(displayName[matchRange])</\(FullTextSearchIndexer.matchTag)>"
        )
    }
}
