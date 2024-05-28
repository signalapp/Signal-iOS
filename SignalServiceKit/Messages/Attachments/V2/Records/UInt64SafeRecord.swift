//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// UInt64 can be unsafe in a GRDB context; they fit into a SQL INTEGER column
/// but GRDB will always attempt to interpret them as Int64 and crash at read time.
///
/// This a bug/limitation in GRDB, and means to be safe, we should ensure that
/// all UInt64 values we insert fit in Int64.max.
protocol UInt64SafeRecord: FetchableRecord {

    static var uint64Fields: [KeyPath<Self, UInt64>] { get }
    static var uint64OptionalFields: [KeyPath<Self, UInt64?>] { get }
}

extension UInt64SafeRecord {

    /// Checks that all UInt64 fields in `uint64Fields` fit in Int64 for database insertions,
    /// and throws if this validation fails.
    ///
    /// This breaks for nested types; for the flat record types this does the trick without needing
    /// to keep it in sync with the field names.
    public func checkAllUInt64FieldsFitInInt64() throws {
        for keyPath in Self.uint64Fields {
            if !SDS.fitsInInt64(self[keyPath: keyPath]) {
                throw OWSAssertionError("\(keyPath) doesn't fit in Int64")
            }
        }
        for keyPath in Self.uint64OptionalFields {
            guard let uintValue = self[keyPath: keyPath] else {
                continue
            }
            if !SDS.fitsInInt64(uintValue) {
                throw OWSAssertionError("\(keyPath) doesn't fit in Int64")
            }
        }
    }
}
