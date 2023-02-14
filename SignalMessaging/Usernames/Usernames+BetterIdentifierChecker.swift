//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension Usernames {
    /// Helps determine if a username is the best identifier we have for a
    /// contact, or if we have a better identifier.
    public struct BetterIdentifierChecker {
        private let recipient: SignalRecipient
        private var address: SignalServiceAddress { recipient.address }

        private var hasE164: Bool = false
        private var hasProfileGivenName: Bool = false
        private var hasProfileFamilyName: Bool = false
        private var hasSystemContactGivenName: Bool = false
        private var hasSystemContactFamilyName: Bool = false
        private var hasSystemContactNickname: Bool = false

        public init(forRecipient recipient: SignalRecipient) {
            self.recipient = recipient

            add(e164: recipient.recipientPhoneNumber)
        }

        public static func assembleByQuerying(
            forRecipient recipient: SignalRecipient,
            profileManager: ProfileManagerProtocol,
            contactManager: ContactsManagerProtocol,
            transaction: SDSAnyReadTransaction
        ) -> BetterIdentifierChecker {
            var checker = BetterIdentifierChecker(forRecipient: recipient)

            if let profileNameComponents = profileManager.nameComponentsForProfile(
                with: recipient.address,
                transaction: transaction
            ) {
                checker.add(profileGivenName: profileNameComponents.givenName)
                checker.add(profileFamilyName: profileNameComponents.familyName)
            }

            if
                let account = contactManager.fetchSignalAccount(
                    for: recipient.address,
                    transaction: transaction
                ),
                let contact = account.contact
            {
                checker.add(systemContactGivenName: contact.firstName)
                checker.add(systemContactFamilyName: contact.lastName)
                checker.add(systemContactNickname: contact.nickname)
            }

            return checker
        }

        // MARK: - Pick

        public func usernameIsBestIdentifier() -> Bool {
            return !(
                hasE164
                || hasProfileGivenName
                || hasProfileFamilyName
                || hasSystemContactGivenName
                || hasSystemContactFamilyName
                || hasSystemContactNickname
            )
        }

        // MARK: - Add identifiers

        public mutating func add(e164: String?) {
            self.hasE164 = e164 != nil
        }

        public mutating func add(profileGivenName: String?) {
            self.hasProfileGivenName = profileGivenName != nil
        }

        public mutating func add(profileFamilyName: String?) {
            self.hasProfileFamilyName = profileFamilyName != nil
        }

        public mutating func add(systemContactGivenName: String?) {
            self.hasSystemContactGivenName = systemContactGivenName != nil
        }

        public mutating func add(systemContactFamilyName: String?) {
            self.hasSystemContactFamilyName = systemContactFamilyName != nil
        }

        public mutating func add(systemContactNickname: String?) {
            self.hasSystemContactNickname = systemContactNickname != nil
        }
    }
}
