//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension SDSCodableModel {
    typealias LegacySDSSerializer = SDSCodableModelLegacySerializer
}

/// Supports [de]serializing models that need to work with complex types stored
/// in BLOB columns. Specifically intended for use with types that previously
/// used SDS codegen that have been migrated to ``SDSCodableModel``.
struct SDSCodableModelLegacySerializer: SDSSerializer {
    func asRecord() -> SDSRecord {
        owsFail("Not actually implemented! This type is a shim - did it accidentally get used in a non-shim context?")
    }

    /// Serializes the given property in the same way the SDS codegen does.
    ///
    /// For use with complex properties that are stored in a single BLOB column.
    func serializeAsLegacySDSData<T: NSObject & NSSecureCoding>(_ value: T) -> Data {
        return try! NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
    }

    /// Deserialize the given data in the same way the SDS codegen does.
    ///
    /// For use with complex properties that are stored in a single BLOB column.
    func deserializeLegacySDSData<T: NSObject & NSSecureCoding>(_ encodedValue: Data, ofClass cls: T.Type) throws -> T {
        guard let result = try? NSKeyedUnarchiver.unarchivedObject(ofClass: cls, from: encodedValue) else {
            throw SDSError.invalidValue()
        }
        return result
    }
}
