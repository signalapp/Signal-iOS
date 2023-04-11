//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

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
        nameResolver: NameResolver = NameResolverImpl(contactsManager: TSGroupThread.contactsManager),
        transaction: SDSAnyReadTransaction
    ) -> [String] {
        let transactionV2 = transaction.asV2Read

        let members = groupMembership.fullMembers.compactMap { address -> (
            address: SignalServiceAddress,
            comparableName: String,
            matchedDisplayName: String?
        )? in
            guard !address.isLocalAddress else {
                return nil
            }
            guard includingBlocked || !blockingManager.isAddressBlocked(address, transaction: transaction) else {
                return nil
            }

            var wrappedDisplayNameMatch: String?
            if let searchText {
                wrappedDisplayNameMatch = wrapIfMatch(
                    searchText: searchText,
                    displayName: nameResolver.displayName(
                        for: address,
                        useShortNameIfAvailable: useShortNameIfAvailable,
                        transaction: transactionV2
                    )
                )
            }

            return (
                address: address,
                comparableName: nameResolver.comparableName(for: address, transaction: transactionV2),
                matchedDisplayName: wrappedDisplayNameMatch
            )
        }

        let sortedMembers = members.sorted { lhs, rhs in
            // Bubble matched members to the top
            if (rhs.matchedDisplayName != nil) != (lhs.matchedDisplayName != nil) {
                return lhs.matchedDisplayName != nil
            }
            // Sort numbers to the end of the list
            if lhs.comparableName.hasPrefix("+") != rhs.comparableName.hasPrefix("+") {
                return !lhs.comparableName.hasPrefix("+")
            }
            // Otherwise, sort by comparable name
            return lhs.comparableName.caseInsensitiveCompare(rhs.comparableName) == .orderedAscending
        }

        return sortedMembers.lazy.prefix(limit).map {
            if let matchedDisplayName = $0.matchedDisplayName {
                return matchedDisplayName
            }
            return nameResolver.displayName(
                for: $0.address,
                useShortNameIfAvailable: useShortNameIfAvailable,
                transaction: transactionV2
            )
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
            with: "<\(FullTextSearchFinder.matchTag)>\(displayName[matchRange])</\(FullTextSearchFinder.matchTag)>"
        )
    }
}
