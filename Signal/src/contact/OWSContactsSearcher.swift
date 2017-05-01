//
//  OWSContactsSearcher.swift
//  Signal
//
//  Created by Tran Son on 4/28/17.
//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc class OWSContactsSearcher: NSObject {

    private var contacts: [Contact]

    init(withContacts contacts: [Contact]) {
        self.contacts = contacts
        super.init()
    }

    func filter(with string: String) -> [Contact] {
        let searchTerm = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if searchTerm == "" {
            return contacts
        }
        let formattedNumber = PhoneNumber.removeFormattingCharacters(searchTerm)
        // TODO: This assumes there's a single search term.
        let predicate = NSPredicate(format: "(fullName contains[c] %@) OR (ANY parsedPhoneNumbers.toE164 contains[c] %@)", searchTerm, formattedNumber!) // FIX: Use optional value
        return (contacts as NSArray).filtered(using: predicate) as! [Contact] // FIX: Use optional value
    }
}
