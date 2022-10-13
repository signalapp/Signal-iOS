//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Contact {
    public func isEqualForCache(_ other: Contact) -> Bool {
        guard self.firstName == other.firstName,
              self.lastName == other.lastName,
              self.nickname == other.nickname,
              self.fullName == other.fullName,
              self.comparableNameFirstLast == other.comparableNameFirstLast,
              self.comparableNameLastFirst == other.comparableNameLastFirst,
              self.uniqueId == other.uniqueId,
              self.cnContactId == other.cnContactId,
              self.isFromContactSync == other.isFromContactSync,
              self.phoneNumberNameMap == other.phoneNumberNameMap else {
                  return false
              }

        // Ignore ordering of these properties.
        guard Set(self.userTextPhoneNumbers) == Set(other.userTextPhoneNumbers),
              Set(self.emails) == Set(other.emails) else {
                  return false
              }

        // Ignore ordering of this property,
        // Don't rely on equality of PhoneNumber.
        let parsedPhoneNumbersSelf = Set(self.parsedPhoneNumbers.compactMap { $0.toE164() })
        let parsedPhoneNumbersOther = Set(other.parsedPhoneNumbers.compactMap { $0.toE164() })
        guard parsedPhoneNumbersSelf == parsedPhoneNumbersOther else {
            return false
        }

        return true
    }
}
