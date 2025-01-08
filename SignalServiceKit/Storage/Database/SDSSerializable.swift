//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

func convertDateForGrdb(_ value: Date) -> Double {
    return value.timeIntervalSince1970
}

// MARK: - SDSSerializer

public protocol SDSSerializer {
    func asRecord() -> SDSRecord
}

// MARK: - SDSSerializer Helpers

public extension SDSSerializer {

    // MARK: - Numeric Primitive

    func archiveOptionalNSNumber<T>(_ value: NSNumber?, conversion: (NSNumber) -> T) -> T? {
        guard let value = value else {
            return nil
        }
        return conversion(value)
    }

    func archiveNSNumber<T>(_ value: NSNumber, conversion: (NSNumber) -> T) -> T {
        return conversion(value)
    }

    // MARK: - Date

    func archiveOptionalDate(_ value: Date?) -> Double? {
        guard let value = value else {
            return nil
        }
        return archiveDate(value)
    }

    func archiveDate(_ value: Date) -> Double {
        return convertDateForGrdb(value)
    }

    // MARK: - Blob

    func optionalArchive(_ value: Any?) -> Data? {
        guard let value = value else {
            return nil
        }
        return requiredArchive(value)
    }

    /// Avoid the cost of actually archiving empty string arrays that are
    /// declared optional (e.g. TSInteraction.attachmentIds)
    func optionalArchive(_ value: [String]?) -> Data? {
        guard let value = value, !value.isEmpty else {
            return nil
        }
        return requiredArchive(value)
    }

    /// Avoide the cost of actually archiving empty message body range objects.
    func optionalArchive(_ value: MessageBodyRanges?) -> Data? {
        guard let value = value, value.hasRanges else {
            return nil
        }
        return requiredArchive(value)
    }

    func requiredArchive(_ value: Any) -> Data {
        return try! NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false)
    }
}
