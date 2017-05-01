//
//  GroupContactsResult.swift
//  Signal
//
//  Created by Tran Son on 4/10/17.
//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc class GroupContactsResult: NSObject {

    private var unknownNumbers: [String]
    private var knownNumbers: [String]
    private var associatedContactDict: [String: Contact]

    init(withMembersId memberIdentifiers: [String], without removeIds: [String]) {
        let manager = Environment.getCurrent().contactsManager
        var remainingNumbers = Set(memberIdentifiers)
        var numbers = [String]()
        var associatedContacts = [Contact]()
        for identifier in memberIdentifiers {
            if identifier == TSAccountManager.localNumber() {
                // Remove local number
                remainingNumbers.remove(identifier)
                continue
            }
            if removeIds.contains(identifier) {
                // Remove id
                remainingNumbers.remove(identifier)
                continue
            }
            guard let number = PhoneNumber(fromE164: identifier), let contact = manager?.latestContact(for: number) else {
                continue
            }
            numbers.append(identifier)
            associatedContacts.append(contact)
            remainingNumbers.remove(identifier)
        }
        unknownNumbers = Array(remainingNumbers)
        unknownNumbers.sort(by: { return $0.compare($1) == .orderedAscending })
        // Populate mapping dictionary.
        var contactDict = [String: Contact]()
        for i in 0 ..< numbers.count {
            let identifier = numbers[i]
            let contact = associatedContacts[i]
            contactDict[identifier] = contact
        }
        // Known Numbers
        knownNumbers = Array(numbers)
        knownNumbers.sort(by: {
            (number1, number2) -> Bool in
            guard let contact1 = contactDict[number1], let contact2 = contactDict[number2] else {
                return false
            }
            return OWSContactsManager.contactComparator()(contact1, contact2) == .orderedAscending
        })
        associatedContactDict = contactDict
        super.init()
    }

    func numberOfMembers() -> Int {
        return knownNumbers.count + unknownNumbers.count
    }

    func isContact(at indexPath: IndexPath) -> Bool {
        return indexPath.row >= unknownNumbers.count
    }

    func contact(for indexPath: IndexPath) -> Contact? {
        if isContact(at: indexPath) {
            return associatedContactDict[knownNumbers[knownNumbersIndex(for: indexPath)]]
        } else {
            return nil
        }
    }

    func identifier(for indexPath: IndexPath) -> String? {
        return (isContact(at: indexPath) ? knownNumbers[knownNumbersIndex(for: indexPath)] : unknownNumbers[indexPath.row])
    }

    // MARK: - Helpers

    private func knownNumbersIndex(for indexPath: IndexPath) -> Int {
        guard indexPath.row >= unknownNumbers.count else {
            return 0
        }
        return indexPath.row - unknownNumbers.count
    }
}
