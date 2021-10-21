//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol ContactsState: AnyObject {
    func unsortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount]

    // Order respects the systems contact sorting preference.
    func sortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount]

    func setSortedSignalAccounts(_ signalAccounts: [SignalAccount])

//    var allContacts: [Contact] { get set }
//
//    var allContactsMap: [String: Contact] { get set }
//
//    // order of the signalAccounts array respects the systems contact sorting preference
//    var signalAccounts: [SignalAccount] { get set }
}

// MARK: -

@objc
public class ContactsStateInDatabase: NSObject, ContactsState {
    @objc
    public func unsortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        SignalAccount.anyFetchAll(transaction: transaction)
    }

    // Order respects the systems contact sorting preference.
    @objc
    public func sortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        contactsManagerImpl.sortSignalAccounts(unsortedSignalAccounts(transaction: transaction),
                                               transaction: transaction)
    }

    @objc
    public func setSortedSignalAccounts(_ signalAccounts: [SignalAccount]) {
        // Ignore.
    }
}

// MARK: -

@objc
public class ContactsStateInMemory: NSObject, ContactsState {
    private let unfairLock = UnfairLock()

    private let contactsStateInDatabase = ContactsStateInDatabase()

    private var sortedSignalAccountsCache: [SignalAccount]?

    @objc
    public func unsortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        // Prefer cache.
        if let cachedValue = (unfairLock.withLock { sortedSignalAccountsCache }) {
            return cachedValue
        }
        // Fail over.
        return contactsStateInDatabase.unsortedSignalAccounts(transaction: transaction)
    }

    // Order respects the systems contact sorting preference.
    @objc
    public func sortedSignalAccounts(transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        // Prefer cache.
        if let cachedValue = (unfairLock.withLock { sortedSignalAccountsCache }) {
            return cachedValue
        }
        // Fail over.
        return contactsStateInDatabase.sortedSignalAccounts(transaction: transaction)
    }

    @objc
    public func setSortedSignalAccounts(_ signalAccounts: [SignalAccount]) {
        unfairLock.withLock {
            // Update cache.
            sortedSignalAccountsCache = signalAccounts
        }
        return contactsStateInDatabase.setSortedSignalAccounts(signalAccounts)
    }

    //    private var _allContacts = [Contact]()
    //    public var allContacts: [Contact] {
    //        get {
    //            unfairLock.withLock { _allContacts }
    //        }
    //        set {
    //            unfairLock.withLock { _allContacts = newValue }
    //        }
    //    }
    //
    //    private var _allContactsMap = [String: Contact]()
    //    public var allContactsMap: [String: Contact] {
    //        get {
    //            unfairLock.withLock { _allContactsMap }
    //        }
    //        set {
    //            unfairLock.withLock { _allContactsMap = newValue }
    //        }
    //    }
    //
    //    private var _signalAccounts = [SignalAccount]()
    //    public var signalAccounts: [SignalAccount] {
    //        get {
    //            unfairLock.withLock { _signalAccounts }
    //        }
    //        set {
    //            unfairLock.withLock { _signalAccounts = newValue }
    //        }
    //    }
}
