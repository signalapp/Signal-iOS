//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit

public class SearchableNameFinder {
    private let contactManager: any ContactManager
    private let searchableNameIndexer: any SearchableNameIndexer
    private let phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher

    public init(
        contactManager: any ContactManager,
        searchableNameIndexer: any SearchableNameIndexer,
        phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher
    ) {
        self.contactManager = contactManager
        self.searchableNameIndexer = searchableNameIndexer
        self.phoneNumberVisibilityFetcher = phoneNumberVisibilityFetcher
    }

    public func searchNames(
        for searchText: String,
        maxResults: Int,
        tx: DBReadTransaction,
        checkCancellation: () throws -> Void,
        addGroupThread: (TSGroupThread) -> Void,
        addStoryThread: (TSPrivateStoryThread) -> Void
    ) rethrows -> [SignalServiceAddress] {
        var contactMatches = ContactMatches()
        try searchableNameIndexer.search(
            for: searchText,
            maxResults: maxResults,
            tx: tx
        ) { indexableName in
            try checkCancellation()

            switch indexableName {
            case let signalAccount as SignalAccount:
                contactMatches.addResult(for: signalAccount)

            case let userProfile as OWSUserProfile:
                contactMatches.addResult(for: userProfile)

            case let signalRecipient as SignalRecipient:
                contactMatches.addResult(
                    for: signalRecipient,
                    phoneNumberVisibilityFetcher: phoneNumberVisibilityFetcher,
                    tx: tx
                )

            case let usernameLookupRecord as UsernameLookupRecord:
                contactMatches.addResult(for: usernameLookupRecord)

            case let groupThread as TSGroupThread:
                addGroupThread(groupThread)

            case let storyThread as TSPrivateStoryThread:
                addStoryThread(storyThread)

            case is TSContactThread:
                break

            default:
                owsFailDebug("Unexpected match of type \(type(of: indexableName))")
            }
        }
        return contactMatches.matchedAddresses(contactManager: contactManager, tx: SDSDB.shimOnlyBridge(tx))
    }
}

private struct ContactMatches {
    private struct ContactMatch {
        var signalAccount: SignalAccount?
        var userProfile: OWSUserProfile?
        var signalRecipient: SignalRecipient?
        var usernameLookupRecord: UsernameLookupRecord?
    }

    private var rawValue = [SignalServiceAddress: ContactMatch]()

    public var count: Int { rawValue.count }

    mutating func addResult(for signalAccount: SignalAccount) {
        let address = signalAccount.recipientAddress
        withUnsafeMutablePointer(to: &rawValue[address, default: ContactMatch()]) {
            $0.pointee.signalAccount = signalAccount
        }
    }

    mutating func addResult(for userProfile: OWSUserProfile) {
        let address = userProfile.publicAddress
        withUnsafeMutablePointer(to: &rawValue[address, default: ContactMatch()]) {
            $0.pointee.userProfile = userProfile
        }
    }

    mutating func addResult(
        for signalRecipient: SignalRecipient,
        phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher,
        tx: DBReadTransaction
    ) {
        guard signalRecipient.isRegistered else {
            return
        }
        guard phoneNumberVisibilityFetcher.isPhoneNumberVisible(for: signalRecipient, tx: tx) else {
            return
        }
        let address = signalRecipient.address
        withUnsafeMutablePointer(to: &rawValue[address, default: ContactMatch()]) {
            $0.pointee.signalRecipient = signalRecipient
        }
    }

    mutating func addResult(for usernameLookupRecord: UsernameLookupRecord) {
        let address = SignalServiceAddress(Aci(fromUUID: usernameLookupRecord.aci))
        withUnsafeMutablePointer(to: &rawValue[address, default: ContactMatch()]) {
            $0.pointee.usernameLookupRecord = usernameLookupRecord
        }
    }

    mutating func removeResult(for address: SignalServiceAddress) {
        rawValue.removeValue(forKey: address)
    }

    func matchedAddresses(contactManager: any ContactManager, tx: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        var results = [SignalServiceAddress]()
        for (address, contactMatch) in rawValue {
            let displayName = contactManager.displayName(for: address, tx: tx)
            let isValidName: Bool
            switch displayName {
            case .systemContactName:
                isValidName = contactMatch.signalAccount != nil
            case .profileName:
                isValidName = contactMatch.userProfile != nil
            case .username:
                isValidName = contactMatch.usernameLookupRecord != nil
            case .phoneNumber, .unknown:
                isValidName = false
            }
            if isValidName || contactMatch.signalRecipient != nil {
                results.append(address)
            }
        }
        return results
    }
}
