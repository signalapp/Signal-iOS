//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
public import SignalServiceKit

public class SearchableNameFinder {
    private let contactManager: any ContactManager
    private let searchableNameIndexer: any SearchableNameIndexer
    private let phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher
    private let recipientDatabaseTable: any RecipientDatabaseTable

    public init(
        contactManager: any ContactManager,
        searchableNameIndexer: any SearchableNameIndexer,
        phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher,
        recipientDatabaseTable: any RecipientDatabaseTable
    ) {
        self.contactManager = contactManager
        self.searchableNameIndexer = searchableNameIndexer
        self.phoneNumberVisibilityFetcher = phoneNumberVisibilityFetcher
        self.recipientDatabaseTable = recipientDatabaseTable
    }

    public func searchNames(
        for searchText: String,
        maxResults: Int,
        localIdentifiers: LocalIdentifiers,
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
                contactMatches.addResult(for: userProfile, localIdentifiers: localIdentifiers)

            case let signalRecipient as SignalRecipient:
                contactMatches.addResult(
                    for: signalRecipient,
                    phoneNumberVisibilityFetcher: phoneNumberVisibilityFetcher,
                    tx: tx
                )

            case let usernameLookupRecord as UsernameLookupRecord:
                contactMatches.addResult(for: usernameLookupRecord)

            case let nicknameRecord as NicknameRecord:
                contactMatches.addResult(
                    for: nicknameRecord,
                    recipientDatabaseTable: self.recipientDatabaseTable,
                    tx: tx
                )

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
        var nickname: NicknameRecord?
        var signalAccount: SignalAccount?
        var userProfile: OWSUserProfile?
        var signalRecipient: SignalRecipient?
        var usernameLookupRecord: UsernameLookupRecord?
    }

    private var rawValue = [SignalServiceAddress: ContactMatch]()

    public var count: Int { rawValue.count }

    mutating func addResult(
        for nickname: NicknameRecord,
        recipientDatabaseTable: any RecipientDatabaseTable,
        tx: DBReadTransaction
    ) {
        guard let recipient = recipientDatabaseTable.fetchRecipient(rowId: nickname.recipientRowID, tx: tx) else { return }
        let address = recipient.address
        withUnsafeMutablePointer(to: &rawValue[address, default: ContactMatch()]) {
            $0.pointee.nickname = nickname
        }
    }

    mutating func addResult(for signalAccount: SignalAccount) {
        let address = signalAccount.recipientAddress
        withUnsafeMutablePointer(to: &rawValue[address, default: ContactMatch()]) {
            $0.pointee.signalAccount = signalAccount
        }
    }

    mutating func addResult(for userProfile: OWSUserProfile, localIdentifiers: LocalIdentifiers) {
        let address = userProfile.publicAddress(localIdentifiers: localIdentifiers)
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
            case .nickname:
                isValidName = contactMatch.nickname != nil
            case .systemContactName:
                isValidName = contactMatch.signalAccount != nil
            case .profileName:
                isValidName = contactMatch.userProfile != nil
            case .username:
                isValidName = contactMatch.usernameLookupRecord != nil
            case .phoneNumber, .deletedAccount, .unknown:
                isValidName = false
            }
            if isValidName || contactMatch.signalRecipient != nil {
                results.append(address)
            }
        }
        return results
    }
}
